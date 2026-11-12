#pragma once

#define STUB_DEVICE_COUNT 2

/* invokes the registered hotplug callback for a synthetic device; false if none is registered */
bool stub_fire_hotplug(int device, bool arrived);
int stub_device_vid(int device);
int stub_device_pid(int device);
