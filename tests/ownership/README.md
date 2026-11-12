# Ownership harness

An ASan/UBSan harness for 4D string, variable and picture ownership. It runs on macOS only.

```sh
tests/ownership/run.sh . fixed
git archive a83f00107beeb492af7588dec8d310c4ef992af0 | (mkdir -p /tmp/usb-baseline && tar -x -C /tmp/usb-baseline)
tests/ownership/run.sh /tmp/usb-baseline baseline
```

The harness compiles these sources, all taken from the tree under test:

- the real `4DPlugin.cpp`;
- every file in `4D Plugin API/Classes`;
- the unmodified `4D Plugin API/4DPluginAPI.c`.

Only two pieces are replaced:

- **`gCall4D`** is replaced by a synthetic engine (`engine_harness.mm`). It tracks every engine string, handle and picture, so it detects:
  - leaks, exactly;
  - double frees and foreign frees.
- **libusb** is replaced by `libusb_stub.cpp`. It provides two synthetic devices and records the hotplug callbacks. It performs no IOKit/SetupAPI enumeration and no USB I/O, and `a/libusb-1.0.a` is not linked.

Each test runs in its own process.

## Defect tests

These must fail on the baseline:

| Test | Contract | Code path |
|---|---|---|
| `defect_hotplug_method_result_leak` | The `PA_ExecuteMethodByID` result is owned, so it is cleared, gated on `PA_GetLastError` | `listenerLoopExecuteMethod` |
| `defect_hotplug_execute_method_owner_leak` | `PA_CreateVariable(eVK_Unistring)` followed by a shallow `PA_SetStringVariable` orphans the empty string | `listenerLoopExecuteMethod` (EXECUTE METHOD fallback) |
| `defect_picture_*` | `C_PICTURE` ownership | Built, but no LIBUSB command calls it (dormant) |

Both hotplug tests exercise the same path, `USB SET HOTPLUG METHOD` → `listenerLoopStart` → `hotplug_callback` → `listenerLoop`. They drive it with synthetic arrival and removal events.

## Controls

These must pass on both trees:

| Test | What it checks |
|---|---|
| `control_hotplug_method_error_not_cleared` | When the method call fails, the result slot holds foreign memory. A clear that is not gated on the error would free it. |
| `control_hotplug_method_no_result` | A method call that returns nothing. |
| `control_device_list_and_text_returns` | `USB GET DEVICE LIST`, `USB Get device descriptor` and `USB Get error name`. |
| `control_array_text_transfer` | A successful `PA_SetStringInArray` transfers ownership. |
| `control_picture_param_return` | A picture parameter and return value stay balanced. |
