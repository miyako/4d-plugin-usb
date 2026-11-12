/*
 * Synthetic 4D engine boundary for LIBUSB ownership regressions.
 *
 * Links the real plugin source (4DPlugin.cpp), the plugin classes
 * (4D Plugin API/Classes) and the bundled, unmodified 4D Plugin API
 * (4DPluginAPI.c). Only gCall4D and libusb are replaced: libusb by
 * libusb_stub.cpp (two synthetic devices, no enumeration or I/O), gCall4D by
 * engine() below, which models engine-side allocations (Unistrings, handles,
 * pictures) with malloc/free so ASan reports double frees and
 * use-after-free, and keeps a live set of every engine string, handle and
 * picture so leaks are detected exactly.
 *
 * Engine semantics modelled (SDK contract):
 *  - PA_CreateVariable(eVK_Unistring / eVK_Picture) allocates an empty
 *    engine string / picture (4DPluginAPI.c); PA_SetStringVariable and
 *    PA_SetPictureVariable overwrite the variable shallowly.
 *  - PA_ClearVariable releases what the variable owns.
 *  - The value returned by PA_ExecuteMethodByID is owned by the caller when
 *    the call succeeds; on error the slot is not a valid value.
 *  - EXECUTE METHOD (1007) without "*" returns Undefined.
 *  - Pictures are reference counted: PA_DuplicatePicture(p, 1) retains,
 *    PA_DisposePicture releases one reference.
 *  - Commands that write a picture into an output parameter (READ PICTURE
 *    FILE, CREATE THUMBNAIL) release the picture previously held by that
 *    variable (the most forgiving engine model).
 *  - PA_ConvertCharsetToCharset returns the BYTE size written (SDK comment).
 *  - PA_RunInMainProcess runs the procedure synchronously; PA_NewProcess only
 *    records the procedure so a test can run it; PA_IsProcessDying reports a
 *    dying process from its second check, so the listener loop drains the
 *    queued hotplug events exactly once and returns.
 */

#include "4DPluginAPI.h"
#include "PrivateTypes.h"
#include "EntryPoints.h"
#include "4DPlugin.h"
#include "libusb_stub.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <map>
#include <set>
#include <string>
#include <vector>

extern "C" Call4DProcPtr gCall4D;

namespace {

typedef std::basic_string<PA_Unichar> u16;

struct Handle { char *data; PA_long32 len; };
struct Pic { int refs; };

std::set<void *> g_strings;
std::set<Handle *> g_handles;
std::set<Pic *> g_pics;

u16 g_read_path, g_convert_type;
int g_transform_op = 0, g_thumb_w = 0, g_thumb_h = 0;

/* listener / method model */
enum MethodResult { kReturnsNothing, kReturnsText, kFails };
u16 g_method_name;
PA_long32 g_method_id = 0;
MethodResult g_method_result = kReturnsNothing;
struct Call { bool byId; PA_long32 event, vendor, product; };
std::vector<Call> g_calls;
std::vector<void (*)()> g_processes;
int g_dying_checks = 0;
PA_Unichar g_foreign[] = { 'x', 0 }; /* not an engine string */

u16 to_u16(const char *s) { u16 r; for(; *s; ++s) r.push_back((PA_Unichar)(unsigned char)*s); return r; }

[[noreturn]] void die(const char *msg) {
    fprintf(stderr, "ENGINE VIOLATION: %s\n", msg);
    fflush(stderr);
    abort();
}

PA_Unistring new_string(const PA_Unichar *src, size_t len) {
    PA_Unichar *buf = (PA_Unichar *)malloc((len + 1) * sizeof(PA_Unichar));
    if(len) memcpy(buf, src, len * sizeof(PA_Unichar));
    buf[len] = 0;
    g_strings.insert(buf);
    PA_Unistring s;
    s.fLength = (PA_long32)len;
    s.fString = buf;
    s.fReserved1 = 0;
    s.fReserved2 = 0;
    return s;
}

void free_string(PA_Unistring *s) {
    if(!s->fString) return;
    if(!g_strings.erase(s->fString)) die("disposed a string the engine does not own");
    free(s->fString);
    s->fString = 0;
    s->fLength = 0;
}

Handle *new_handle(PA_long32 len) {
    Handle *h = (Handle *)malloc(sizeof(Handle));
    h->data = (char *)calloc(1, len ? len : 1);
    h->len = len;
    g_handles.insert(h);
    return h;
}

Handle *checked(PA_Handle ph) {
    Handle *h = (Handle *)ph;
    if(!g_handles.count(h)) die("used an unknown handle");
    return h;
}

void free_handle(Handle *h) {
    if(!h) return;
    checked((PA_Handle)h);
    g_handles.erase(h);
    free(h->data);
    free(h);
}

Pic *new_pic() {
    Pic *p = (Pic *)malloc(sizeof(Pic));
    p->refs = 1;
    g_pics.insert(p);
    return p;
}

Pic *live_pic(PA_Picture pp) {
    Pic *p = (Pic *)pp;
    if(!g_pics.count(p)) die("used a picture the engine does not own");
    return p;
}

void release_pic(PA_Picture pp) {
    if(!pp) return;
    Pic *p = live_pic(pp);
    if(--p->refs == 0) { g_pics.erase(p); free(p); }
}

void clear_var(PA_Variable *v) {
    switch(v->fType) {
        case eVK_Unistring: free_string(&v->uValue.fString); break;
        case eVK_Picture: release_pic(v->uValue.fPicture); v->uValue.fPicture = 0; break;
        case eVK_ArrayLongint: free_handle((Handle *)v->uValue.fArray.fData); break;
        case eVK_ArrayUnicode: {
            Handle *h = (Handle *)v->uValue.fArray.fData;
            if(h) {
                PA_Unistring *items = (PA_Unistring *)checked((PA_Handle)h)->data;
                for(PA_long32 i = 0; i <= v->uValue.fArray.fNbElements; ++i) free_string(&items[i]);
                free_handle(h);
            }
            break;
        }
        case eVK_Undefined: case eVK_Longint: break;
        default: die("unmodelled variable kind cleared");
    }
    v->fType = eVK_Undefined;
}

u16 live_text(const PA_Variable &v, const char *what) {
    if(v.fType != eVK_Unistring) die(what);
    if(!g_strings.count(v.uValue.fString.fString)) die("engine received a string it does not own");
    return u16(v.uValue.fString.fString, v.uValue.fString.fLength);
}

void live_picture_var(const PA_Variable &v, const char *what) {
    if(v.fType != eVK_Picture || !v.uValue.fPicture) die(what);
    live_pic(v.uValue.fPicture);
}

PA_long32 longint(const PA_Variable &v, const char *what) {
    if(v.fType != eVK_Longint) die(what);
    return v.uValue.fLongint;
}

/* output picture parameter: the engine releases the old value and stores a new picture */
void write_picture(PA_Variable *v) {
    if(v->fType == eVK_Picture) release_pic(v->uValue.fPicture);
    else if(v->fType != eVK_Undefined) die("picture output parameter has a non-picture value");
    v->fType = eVK_Picture;
    v->uValue.fPicture = new_pic();
}

void command(EngineBlock *eb) {
    PA_Variable **v = (PA_Variable **)eb->fPtr1;
    PA_long32 n = (PA_long32)eb->fParam2;
    switch(eb->fParam1) {
        case 1007: /* EXECUTE METHOD(name; event; vendor; product) */
            if(n != 4) die("EXECUTE METHOD parameter count");
            if(live_text(*v[0], "method name is not text") != g_method_name) die("method name");
            g_calls.push_back({ false, longint(*v[1], "event"), longint(*v[2], "vendor"), longint(*v[3], "product") });
            break; /* the return slot stays Undefined */
        case 678: /* READ PICTURE FILE(path; picture) */
            if(n != 2) die("READ PICTURE FILE parameter count");
            g_read_path = live_text(*v[0], "path parameter is not text");
            write_picture(v[1]);
            break;
        case 1002: /* CONVERT PICTURE(picture; type) */
            if(n != 2) die("CONVERT PICTURE parameter count");
            live_picture_var(*v[0], "CONVERT PICTURE picture");
            g_convert_type = live_text(*v[1], "type parameter is not text");
            break;
        case 988: /* TRANSFORM PICTURE(picture; operator) */
            if(n != 2) die("TRANSFORM PICTURE parameter count");
            live_picture_var(*v[0], "TRANSFORM PICTURE picture");
            g_transform_op = longint(*v[1], "operator is not longint");
            break;
        case 457: /* PICTURE PROPERTIES(picture; width; height) */
            if(n != 3) die("PICTURE PROPERTIES parameter count");
            live_picture_var(*v[0], "PICTURE PROPERTIES picture");
            v[1]->fType = eVK_Longint; v[1]->uValue.fLongint = 640;
            v[2]->fType = eVK_Longint; v[2]->uValue.fLongint = 480;
            break;
        case 679: /* CREATE THUMBNAIL(picture; thumbnail; width; height) */
            if(n != 4) die("CREATE THUMBNAIL parameter count");
            live_picture_var(*v[0], "CREATE THUMBNAIL source");
            g_thumb_w = longint(*v[2], "width is not longint");
            g_thumb_h = longint(*v[3], "height is not longint");
            write_picture(v[1]);
            break;
        default: die("unexpected command");
    }
    eb->fError = 0;
}

/* PA_ExecuteMethodByID: handle = [return slot, params...] */
void call_method(EngineBlock *eb) {
    if(eb->fParam1 != g_method_id || !g_method_id) die("unknown method id");
    if(eb->fParam2 != 3) die("method parameter count");
    PA_Variable *slot = (PA_Variable *)checked(eb->fHandle)->data;
    if(slot[0].fType != eVK_Undefined) die("return slot not initialised");
    g_calls.push_back({ true, longint(slot[1], "event"), longint(slot[2], "vendor"), longint(slot[3], "product") });
    eb->fError = 0;
    switch(g_method_result) {
        case kReturnsNothing: break;
        case kReturnsText:
            slot[0].fType = eVK_Unistring;
            slot[0].uValue.fString = new_string((const PA_Unichar *)u"handled", 7);
            break;
        case kFails:
            /* the slot is not a valid value: clearing it would free foreign memory */
            slot[0].fType = eVK_Unistring;
            slot[0].uValue.fString.fString = g_foreign;
            slot[0].uValue.fString.fLength = 1;
            eb->fError = 1;
            break;
    }
}

void engine(PA_long32 selector, void *p) {
    EngineBlock *eb = (EngineBlock *)p;
    switch(selector) {
        case EX_HANDLE_MANAGER:
            switch(eb->fParam1) {
                case 1: eb->fHandle = (PA_Handle)new_handle((PA_long32)eb->fParam2); eb->fError = 0; return;
                case 2: free_handle((Handle *)eb->fHandle); eb->fError = 0; return;
                case 3: {
                    Handle *h = checked(eb->fHandle);
                    PA_long32 n = (PA_long32)eb->fParam2;
                    h->data = (char *)realloc(h->data, n ? n : 1);
                    if(n > h->len) memset(h->data + h->len, 0, n - h->len);
                    h->len = n; eb->fError = 0; return;
                }
                case 4: eb->fParam2 = checked(eb->fHandle)->len; eb->fError = 0; return;
                case 5: eb->fParam3 = (sLONG_PTR)checked(eb->fHandle)->data; eb->fError = 0; return;
                case 6: checked(eb->fHandle); eb->fError = 0; return;
                default: die("unmodelled handle manager call");
            }
        case EX_CREATE_UNISTRING: {
            const PA_Unichar *s = (const PA_Unichar *)eb->fHandle;
            size_t n = 0; while(s[n]) ++n;
            eb->fUniString1 = new_string(s, n);
            return;
        }
        case EX_SET_UNISTRING: {
            const PA_Unichar *s = (const PA_Unichar *)eb->fHandle;
            size_t n = 0; while(s[n]) ++n;
            free_string(&eb->fUniString1);
            eb->fUniString1 = new_string(s, n);
            return;
        }
        case EX_DISPOSE_UNISTRING: free_string(&eb->fUniString1); return;
        case EX_CLEAR_VARIABLE: clear_var((PA_Variable *)eb->fPtr1); return;
        case EX_YIELD_ABSOLUTE: return;
        case EX_RUN_IN_MAIN_PROCESS: ((PA_RunInMainProcessProcPtr)eb->fPtr1)(eb->fPtr2); return;
        case EX_NEW_PROCESS:
            g_processes.push_back((void (*)())eb->fHandle);
            eb->fParam1 = (sLONG_PTR)(10 + g_processes.size());
            eb->fError = 0;
            return;
        case EX_IS_PROCESS_DYING: eb->fManyToOne = (g_dying_checks++ >= 1); return;
        case EX_CURRENT_PROCESS_NUMBER: eb->fParam1 = 11; return;
        case EX_PUT_PROCESS_TO_SLEEP: eb->fError = 0; return;
        case EX_KILL_PROCESS: return;
        case EX_GET_METHOD_ID: {
            size_t n = 0; while(eb->fUName[n]) ++n;
            eb->fParam1 = (u16(eb->fUName, n) == g_method_name) ? g_method_id : 0;
            eb->fError = 0;
            return;
        }
        case EX_CALL_BY_PROCID: call_method(eb); return;
        case EX_CREATE_PICTURE: eb->fPicture = new_pic(); eb->fError = 0; return;
        case EX_DISPOSE_PICTURE: release_pic(eb->fPicture); return;
        case EX_DUPLICATE_PICTURE:
            if(eb->fParam1 == 0) live_pic(eb->fPicture)->refs++;
            else { live_pic(eb->fPicture); eb->fPicture = new_pic(); }
            return;
        case EX_GET_PICTURE_DATA:
            live_pic(eb->fPicture);
            memset(&eb->fUniString1, 0, sizeof eb->fUniString1);
            eb->fError = -1; /* no stored formats */
            return;
        case EX_CONVERT_CHARSET_TO_CHARSET: {
            const char *from = (const char *)eb->fPtr1;
            PA_long32 fromSize = (PA_long32)eb->fParam1, toSize = (PA_long32)eb->fParam3, out = 0;
            if(eb->fParam2 == eVTC_UTF_8 && eb->fParam4 == eVTC_UTF_16) {
                PA_Unichar *to = (PA_Unichar *)eb->fPtr2;
                for(PA_long32 i = 0; i < fromSize && (out + 1) * (PA_long32)sizeof(PA_Unichar) <= toSize; ++i)
                    to[out++] = (unsigned char)from[i];
                eb->fParam3 = out * (PA_long32)sizeof(PA_Unichar); /* byte size */
            } else if(eb->fParam2 == eVTC_UTF_16 && eb->fParam4 == eVTC_UTF_8) {
                const PA_Unichar *f = (const PA_Unichar *)from;
                char *to = (char *)eb->fPtr2;
                for(PA_long32 i = 0; i < fromSize / 2 && out < toSize; ++i) to[out++] = (char)f[i];
                eb->fParam3 = out;
            } else die("unmodelled charset conversion");
            eb->fError = 0;
            return;
        }
        case EX_EXECUTE_COMMAND_BY_ID: command(eb); return;
        default: {
            char msg[64];
            snprintf(msg, sizeof msg, "unmodelled selector %d", (int)selector);
            die(msg);
        }
    }
}

void expect(bool ok, const char *what) {
    if(!ok) {
        fprintf(stderr, "FAIL: %s (live engine strings: %zu, handles: %zu, pictures: %zu)\n",
                what, g_strings.size(), g_handles.size(), g_pics.size());
        exit(1);
    }
}

void expect_nothing_live(const char *what) {
    expect(g_strings.empty(), what);
    expect(g_handles.empty(), what);
    expect(g_pics.empty(), what);
}


/* ---- LIBUSB through PluginMain ---- */

void plugin(PA_long32 selector, void **params, void *result) {
    PluginBlock pb = { params, result, 0 };
    PluginMain(selector, &pb);
}

void startup() {
    plugin(kInitPlugin, 0, 0);
}

/* USB SET HOTPLUG METHOD(method; error) */
PA_long32 set_hotplug_method(const u16 &name) {
    PA_Unistring p1 = new_string(name.c_str(), name.size());
    PA_long32 p2 = 0;
    void *params[2] = { &p1, &p2 };
    plugin(1, params, 0);
    free_string(&p1);
    return p2;
}

/* USB Get hotplug method(error):T */
u16 get_hotplug_method() {
    PA_long32 p1 = 0;
    PA_Unistring ret = new_string(0, 0);
    PA_Unistring *pret = &ret;
    void *params[1] = { &p1 };
    plugin(2, params, &pret);
    u16 r(ret.fString, ret.fLength);
    free_string(&ret);
    return r;
}

/* registers the method, fires hotplug events for both devices, runs the listener loop once */
void dispatch_hotplug(const char *method, PA_long32 id, MethodResult result) {
    g_method_name = to_u16(method);
    g_method_id = id;
    g_method_result = result;
    startup();
    expect(set_hotplug_method(g_method_name) == 0, "hotplug method set");
    expect(get_hotplug_method() == g_method_name, "hotplug method readable");
    expect(g_processes.size() == 2, "listener and server processes started");
    expect(stub_fire_hotplug(0, true), "arrival callback registered");
    expect(stub_fire_hotplug(1, false), "removal callback registered");
    g_processes[0](); /* listenerLoop */
    expect(g_calls.size() == 2, "one callback per event");
    expect(g_calls[0].event == LIBUSB_HOTPLUG_EVENT_DEVICE_ARRIVED
           && g_calls[0].vendor == stub_device_vid(0) && g_calls[0].product == stub_device_pid(0), "arrival delivered");
    expect(g_calls[1].event == LIBUSB_HOTPLUG_EVENT_DEVICE_LEFT
           && g_calls[1].vendor == stub_device_vid(1) && g_calls[1].product == stub_device_pid(1), "removal delivered");
    expect(get_hotplug_method().empty(), "listener cleared the method on exit");
}

/* ---- tests ---- */

/* Contract 3: the PA_ExecuteMethodByID result is owned and must be cleared. */
void defect_hotplug_method_result_leak() {
    dispatch_hotplug("Project_callback", 42, kReturnsText);
    for(auto &c : g_calls) expect(c.byId, "dispatched by method id");
    expect_nothing_live("method results released");
}

/* Contract 2: eVK_Unistring + shallow PA_SetStringVariable orphans the empty string. */
void defect_hotplug_execute_method_owner_leak() {
    dispatch_hotplug("Formula_callback", 0, kReturnsNothing);
    for(auto &c : g_calls) expect(!c.byId, "dispatched by EXECUTE METHOD");
    expect_nothing_live("EXECUTE METHOD parameters released");
}

void control_hotplug_method_no_result() {
    dispatch_hotplug("Project_callback", 42, kReturnsNothing);
    expect_nothing_live("nothing to release");
}

/* Contract 3: on error the result slot must not be cleared (gate on PA_GetLastError). */
void control_hotplug_method_error_not_cleared() {
    dispatch_hotplug("Project_callback", 42, kFails);
    expect_nothing_live("failed calls leave nothing behind");
}

/* USB GET DEVICE LIST(vid; pid; ref; error) and text-returning commands */
void control_device_list_and_text_returns() {
    startup();
    {
        PA_Variable a1 = PA_CreateVariable(eVK_ArrayLongint);
        PA_Variable a2 = PA_CreateVariable(eVK_ArrayLongint);
        PA_Variable a3 = PA_CreateVariable(eVK_ArrayLongint);
        PA_long32 err = 0;
        void *params[4] = { &a1, &a2, &a3, &err };
        plugin(7, params, 0);
        expect(err == 0, "device list error");
        expect(a1.uValue.fArray.fNbElements == STUB_DEVICE_COUNT, "two synthetic devices");
        PA_long32 *vids = *(PA_long32 **)a2.uValue.fArray.fData;
        expect(vids[1] == stub_device_vid(0) && vids[2] == stub_device_vid(1), "vendor ids");
        PA_ClearVariable(&a1);
        PA_ClearVariable(&a2);
        PA_ClearVariable(&a3);
    }
    {
        PA_long32 ref = 1, err = -1;
        PA_Unistring ret = new_string(0, 0);
        PA_Unistring *pret = &ret;
        void *params[2] = { &ref, &err };
        plugin(8, params, &pret); /* USB Get device descriptor */
        expect(err == 0, "descriptor error");
        u16 json(ret.fString, ret.fLength);
        expect(json.find(to_u16("\"idVendor\":4660")) != u16::npos, "descriptor JSON");
        free_string(&ret);
    }
    {
        PA_long32 code = LIBUSB_ERROR_NO_DEVICE;
        PA_Unistring ret = new_string(0, 0);
        PA_Unistring *pret = &ret;
        void *params[1] = { &code };
        plugin(6, params, &pret); /* USB Get error name */
        expect(u16(ret.fString, ret.fLength) == to_u16("LIBUSB_ERROR_NO_DEVICE"), "error name");
        free_string(&ret);
    }
    expect_nothing_live("command parameters and returns balanced");
}

/* Contract 1: ARRAY_TEXT fills the array via PA_SetStringInArray and must not dispose. */
void control_array_text_transfer() {
    {
        ARRAY_TEXT a;
        a.appendUTF16String((const PA_Unichar *)u"", 0);
        a.appendUTF16String((const PA_Unichar *)u"x", 1);
        a.appendUTF16String((const PA_Unichar *)u"yz", 2);
        PA_Variable arr = PA_CreateVariable(eVK_ArrayUnicode);
        void *params[1] = { &arr };
        a.toParamAtIndex((PackagePtr)params, 1);
        expect(arr.uValue.fArray.fNbElements == 2, "two elements");
        expect(g_strings.size() == 3, "array owns three strings");
        ARRAY_TEXT b;
        b.fromParamAtIndex((PackagePtr)params, 1);
        CUTF16String s; b.copyUTF16StringAtIndex(&s, 2);
        expect(s == CUTF16String((const PA_Unichar *)u"yz"), "borrowed read");
        PA_ClearVariable(&arr);
    }
    expect_nothing_live("array strings released with the array");
}

/* ---- C_PICTURE (built, unreachable from any LIBUSB command) ---- */

/* a picture held by C_PICTURE; the harness drops its own reference */
void with_picture(const std::function<void(C_PICTURE &)> &f) {
    {
        C_PICTURE pic;
        PA_Picture src = PA_CreatePicture(0, 0);
        pic.setPicture(src);
        PA_DisposePicture(src);
        expect(g_pics.size() == 1, "one picture held");
        f(pic);
    }
}

void defect_picture_fromfile_ownership() {
    {
        C_PICTURE pic;
        CUTF8String path((const uint8_t *)"/usb-synthetic/does-not-exist.png");
        pic.fromFileAtPath(&path);
        expect(g_read_path == to_u16("/usb-synthetic/does-not-exist.png"), "path delivered");
        expect(g_pics.size() == 1, "only the loaded picture is live");
    }
    expect_nothing_live("READ PICTURE FILE parameters and result released");
}

void defect_picture_setbytes_leak() {
    {
        C_PICTURE pic;
        const uint8_t bytes[] = { 1, 2, 3 };
        pic.setBytes(bytes, sizeof bytes);
        expect(g_pics.size() == 1, "only the held picture is live");
    }
    expect_nothing_live("picture created by setBytes released");
}

void defect_picture_createcopy_ownership() {
    with_picture([](C_PICTURE &pic) {
        PA_Picture p = pic.createCopyPNG();
        expect(g_convert_type == to_u16(".png"), "type delivered");
        expect(p == pic.getPicture(), "retained copy returned");
        PA_DisposePicture(p);
    });
    expect_nothing_live("CONVERT PICTURE parameters released");
}

void defect_picture_grayscale_owner_leak() {
    with_picture([](C_PICTURE &pic) {
        PA_Picture p = pic.createGrayScale();
        expect(g_transform_op == 101, "operator delivered");
        PA_DisposePicture(p);
    });
    expect_nothing_live("TRANSFORM PICTURE parameters released");
}

void defect_picture_getsize_owner_leak() {
    with_picture([](C_PICTURE &pic) {
        unsigned int w = 0, h = 0;
        pic.getSize(&w, &h);
        expect(w == 640 && h == 480, "size delivered");
    });
    expect_nothing_live("PICTURE PROPERTIES parameters released");
}

void defect_picture_thumbnail_owner_leak() {
    with_picture([](C_PICTURE &pic) {
        PA_Picture t = pic.createThumbnail(32, 24);
        expect(g_thumb_w == 32 && g_thumb_h == 24, "size delivered");
        expect(t && t != pic.getPicture() && g_pics.count((Pic *)t), "thumbnail handed to the caller");
        PA_DisposePicture(t);
    });
    expect_nothing_live("CREATE THUMBNAIL parameters released");
}

/* C_PICTURE parameter/return transfer. */
void control_picture_param_return() {
    PA_Picture in = PA_CreatePicture(0, 0);
    PA_Picture out = PA_CreatePicture(0, 0);
    PA_Picture ret = 0;
    {
        C_PICTURE pic;
        void *params[2] = { &in, &out };
        pic.fromParamAtIndex((PackagePtr)params, 1);
        pic.toParamAtIndex((PackagePtr)params, 2);
        pic.setReturn((sLONG_PTR *)&ret);
        expect(out == in && ret == in, "same picture retained");
    }
    PA_DisposePicture(in);
    PA_DisposePicture(out);
    PA_DisposePicture(ret);
    expect_nothing_live("all references balanced");
}

const std::map<std::string, std::function<void()>> kTests = {
    { "defect_hotplug_method_result_leak", defect_hotplug_method_result_leak },
    { "defect_hotplug_execute_method_owner_leak", defect_hotplug_execute_method_owner_leak },
    { "control_hotplug_method_no_result", control_hotplug_method_no_result },
    { "control_hotplug_method_error_not_cleared", control_hotplug_method_error_not_cleared },
    { "control_device_list_and_text_returns", control_device_list_and_text_returns },
    { "control_array_text_transfer", control_array_text_transfer },
    { "defect_picture_fromfile_ownership", defect_picture_fromfile_ownership },
    { "defect_picture_setbytes_leak", defect_picture_setbytes_leak },
    { "defect_picture_createcopy_ownership", defect_picture_createcopy_ownership },
    { "defect_picture_grayscale_owner_leak", defect_picture_grayscale_owner_leak },
    { "defect_picture_getsize_owner_leak", defect_picture_getsize_owner_leak },
    { "defect_picture_thumbnail_owner_leak", defect_picture_thumbnail_owner_leak },
    { "control_picture_param_return", control_picture_param_return },
};

} // namespace

int main(int argc, char **argv) {
    gCall4D = (Call4DProcPtr)engine;
    if(argc == 2 && std::string(argv[1]) == "--list") {
        for(auto &t : kTests) printf("%s\n", t.first.c_str());
        return 0;
    }
    if(argc != 2 || !kTests.count(argv[1])) { fprintf(stderr, "usage: %s --list | <test>\n", argv[0]); return 2; }
    kTests.at(argv[1])();
    printf("PASS %s\n", argv[1]);
    return 0;
}
