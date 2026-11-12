/*
 * Synthetic libusb for the ownership harness.
 *
 * Replaces a/libusb-1.0.a so that no IOKit/SetupAPI enumeration or USB I/O
 * ever happens. Two synthetic devices are enumerated; hotplug registration
 * only records the callback so the harness can fire synthetic events.
 * Everything that would touch a device fails with LIBUSB_ERROR_NOT_SUPPORTED.
 */

#include "libusb.h"
#include "libusb_stub.h"

#include <cstdlib>

struct libusb_context { int unused; };
struct libusb_device { uint16_t vid, pid; };
struct libusb_device_handle { libusb_device *dev; };

static libusb_device stub_devices[STUB_DEVICE_COUNT] = { { 0x1234, 0x0001 }, { 0x5678, 0x0002 } };

static libusb_context hotplug_context;
/* slot 0: ARRIVED, slot 1: LEFT */
static libusb_hotplug_callback_fn hotplug_fn[2];
static libusb_hotplug_callback_handle hotplug_handle[2];
static int hotplug_count = 0;

bool stub_fire_hotplug(int device, bool arrived) {
    int slot = arrived ? 0 : 1;
    if(!hotplug_fn[slot]) return false;
    hotplug_fn[slot](&hotplug_context, &stub_devices[device],
                     arrived ? LIBUSB_HOTPLUG_EVENT_DEVICE_ARRIVED : LIBUSB_HOTPLUG_EVENT_DEVICE_LEFT, 0);
    return true;
}

int stub_device_vid(int device) { return stub_devices[device].vid; }
int stub_device_pid(int device) { return stub_devices[device].pid; }

extern "C" {

int LIBUSB_CALL libusb_init(libusb_context **ctx) { if(ctx) *ctx = &hotplug_context; return LIBUSB_SUCCESS; }
void LIBUSB_CALL libusb_exit(libusb_context *) {}
int LIBUSB_CALL libusb_has_capability(uint32_t capability) { return capability == LIBUSB_CAP_HAS_HOTPLUG; }

const struct libusb_version * LIBUSB_CALL libusb_get_version(void) {
    static const libusb_version v = { 1, 0, 23, 0, "", "synthetic" };
    return &v;
}

const char * LIBUSB_CALL libusb_error_name(int errcode) {
    switch(errcode) {
        case LIBUSB_SUCCESS: return "LIBUSB_SUCCESS";
        case LIBUSB_ERROR_NO_DEVICE: return "LIBUSB_ERROR_NO_DEVICE";
        default: return "LIBUSB_ERROR_OTHER";
    }
}
const char * LIBUSB_CALL libusb_strerror(enum libusb_error errcode) { return libusb_error_name(errcode); }
int LIBUSB_CALL libusb_setlocale(const char *) { return LIBUSB_SUCCESS; }

ssize_t LIBUSB_CALL libusb_get_device_list(libusb_context *, libusb_device ***list) {
    libusb_device **l = (libusb_device **)calloc(STUB_DEVICE_COUNT + 1, sizeof(libusb_device *));
    for(int i = 0; i < STUB_DEVICE_COUNT; ++i) l[i] = &stub_devices[i];
    *list = l;
    return STUB_DEVICE_COUNT;
}
void LIBUSB_CALL libusb_free_device_list(libusb_device **list, int) { free(list); }

int LIBUSB_CALL libusb_get_device_descriptor(libusb_device *dev, struct libusb_device_descriptor *desc) {
    *desc = libusb_device_descriptor();
    desc->bLength = LIBUSB_DT_DEVICE_SIZE;
    desc->bDescriptorType = LIBUSB_DT_DEVICE;
    desc->idVendor = dev->vid;
    desc->idProduct = dev->pid;
    desc->bNumConfigurations = 1;
    return LIBUSB_SUCCESS;
}

uint8_t LIBUSB_CALL libusb_get_bus_number(libusb_device *) { return 1; }
uint8_t LIBUSB_CALL libusb_get_port_number(libusb_device *) { return 1; }
uint8_t LIBUSB_CALL libusb_get_device_address(libusb_device *dev) { return (uint8_t)(dev - stub_devices + 1); }
int LIBUSB_CALL libusb_get_device_speed(libusb_device *) { return LIBUSB_SPEED_FULL; }
int LIBUSB_CALL libusb_get_max_packet_size(libusb_device *, unsigned char) { return LIBUSB_ERROR_NOT_FOUND; }

int LIBUSB_CALL libusb_get_active_config_descriptor(libusb_device *, struct libusb_config_descriptor **) { return LIBUSB_ERROR_NOT_SUPPORTED; }
int LIBUSB_CALL libusb_get_config_descriptor(libusb_device *, uint8_t, struct libusb_config_descriptor **) { return LIBUSB_ERROR_NOT_SUPPORTED; }
int LIBUSB_CALL libusb_get_config_descriptor_by_value(libusb_device *, uint8_t, struct libusb_config_descriptor **) { return LIBUSB_ERROR_NOT_SUPPORTED; }
void LIBUSB_CALL libusb_free_config_descriptor(struct libusb_config_descriptor *) {}

/* no device can be opened, so no handle (and no I/O) ever exists */
int LIBUSB_CALL libusb_open(libusb_device *, libusb_device_handle **) { return LIBUSB_ERROR_NOT_SUPPORTED; }
libusb_device_handle * LIBUSB_CALL libusb_open_device_with_vid_pid(libusb_context *, uint16_t, uint16_t) { return 0; }
void LIBUSB_CALL libusb_close(libusb_device_handle *) { abort(); }
libusb_device * LIBUSB_CALL libusb_get_device(libusb_device_handle *) { abort(); }
int LIBUSB_CALL libusb_get_configuration(libusb_device_handle *, int *) { abort(); }
int LIBUSB_CALL libusb_set_configuration(libusb_device_handle *, int) { abort(); }
int LIBUSB_CALL libusb_claim_interface(libusb_device_handle *, int) { abort(); }
int LIBUSB_CALL libusb_release_interface(libusb_device_handle *, int) { abort(); }
int LIBUSB_CALL libusb_set_interface_alt_setting(libusb_device_handle *, int, int) { abort(); }
int LIBUSB_CALL libusb_clear_halt(libusb_device_handle *, unsigned char) { abort(); }
int LIBUSB_CALL libusb_control_transfer(libusb_device_handle *, uint8_t, uint8_t, uint16_t, uint16_t, unsigned char *, uint16_t, unsigned int) { abort(); }

struct libusb_transfer * LIBUSB_CALL libusb_alloc_transfer(int) { abort(); }
void LIBUSB_CALL libusb_free_transfer(struct libusb_transfer *) { abort(); }
int LIBUSB_CALL libusb_submit_transfer(struct libusb_transfer *) { abort(); }
int LIBUSB_CALL libusb_cancel_transfer(struct libusb_transfer *) { abort(); }
int LIBUSB_CALL libusb_handle_events_completed(libusb_context *, int *) { abort(); }
int LIBUSB_CALL libusb_handle_events_timeout_completed(libusb_context *, struct timeval *, int *) { return LIBUSB_SUCCESS; }

int LIBUSB_CALL libusb_hotplug_register_callback(libusb_context *, libusb_hotplug_event events, libusb_hotplug_flag,
                                                 int, int, int, libusb_hotplug_callback_fn cb_fn, void *,
                                                 libusb_hotplug_callback_handle *handle) {
    int slot = (events == LIBUSB_HOTPLUG_EVENT_DEVICE_ARRIVED) ? 0 : 1;
    hotplug_fn[slot] = cb_fn;
    hotplug_handle[slot] = *handle = ++hotplug_count;
    return LIBUSB_SUCCESS;
}

void LIBUSB_CALL libusb_hotplug_deregister_callback(libusb_context *, libusb_hotplug_callback_handle handle) {
    for(int i = 0; i < 2; ++i) if(hotplug_handle[i] == handle) { hotplug_fn[i] = 0; hotplug_handle[i] = 0; }
}

}
