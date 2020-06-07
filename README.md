# 4d-plugin-usb
Basic implementation of [libusb](https://github.com/libusb/libusb) for 4D.

### Platform

| carbon | cocoa | win32 | win64 |
|:------:|:-----:|:---------:|:---------:|
||<img src="https://cloud.githubusercontent.com/assets/1725068/22371562/1b091f0a-e4db-11e6-8458-8653954a7cce.png" width="24" height="24" />|<img src="https://cloud.githubusercontent.com/assets/1725068/22371562/1b091f0a-e4db-11e6-8458-8653954a7cce.png" width="24" height="24" />|<img src="https://cloud.githubusercontent.com/assets/1725068/22371562/1b091f0a-e4db-11e6-8458-8653954a7cce.png" width="24" height="24" />|

### Version

<img width="32" height="32" src="https://user-images.githubusercontent.com/1725068/73986501-15964580-4981-11ea-9ac1-73c5cee50aae.png"> <img src="https://user-images.githubusercontent.com/1725068/73987971-db2ea780-4984-11ea-8ada-e25fb9c3cf4e.png" width="32" height="32" />

### Remarks

* Windows: vcpkg libusb ``1.0.22`` (static)

* Mac: brew libusb ``1.0.23`` (static)

Commands
---

```c
// --- USB
USB_SET_HOTPLUG_METHOD
USB_Get_hotplug_method
USB_SET_LOCALE
USB_GET_VERSION
USB_Get_error_description
USB_Get_error_name
USB_GET_DEVICE_LIST
USB_Get_device_descriptor
USB_Get_config_descriptor
USB_Open
USB_CLAIM_INTERFACE
USB_RELEASE_INTERFACE
USB_CLOSE
USB_Get_device
USB_SET_INTERFACE_ALT_SETTING
USB_SET_CONFIGURATION
USB_Get_configuration
USB_Open_device_with_vid_pid
USB_BULK_TRANSFER
USB_Get_bus_number
USB_Get_port_number
USB_Get_device_address
USB_Get_device_speed
USB_CLEAR_HALT
USB_GET_DESCRIPTOR
USB_INTERRUPT_TRANSFER
```

Examples
---

Hotplug
---
```
//On Startup
USB SET HOTPLUG METHOD ("HOTPLUG_CB";$usb_error)
$methodName:=USB Get hotplug method ($usb_error)
```

**About**

Two local processes named ```$USB``` and ```$USB_HOTPLUG``` are launched.

It will call libusb for 0.1 seconds, then sleep for 0.9 seconds. If a device is conneced or disconnected, the callback method will be executed in a new process (name:Generate UUID). The method will receive 3 parameters; type of event, vendor id and product id.

* Example callback method

```
C_LONGINT($1;$2;$3)

$vendorId:=String($2;"&x")
$productId:=String($3;"&x")

$wId:=Open window(Screen width\2-250;\
Screen height\2-25;\
Screen width\2+250;\
Screen height\2+25;Pop up window)

Case of 
: ($1=USB DEVICE ARRIVED)

MESSAGE("USB DEVICE ARRIVED\rvid:"+$vendorId+"\rpid:"+$productId)

: ($1=USB DEVICE LEFT)

MESSAGE("USB DEVICE LEFT\rvid:"+$vendorId+"\rpid:"+$productId)

End case 

DELAY PROCESS(Current process;180)

CLOSE WINDOW($wId)
```

**Note**: The method is executed in a new process, so that an abortion, TRACE or other blocking operation does not affect the hotplug monitoring process. The plugin starts two processes to handle multiple events; the monitoring process keeps to its schedule, while the other process spawns a new process to run the callback method.

To finish monitoring, pass an empty string as method name. If you forget to terminate the monitoring process, the plugin will close it anyway, but for this mechanism to work you need to have an On Exit database method (it can be empty) on v13 (the plugin checks if the closing process name is ```$xx```. Note that since v14, ```$xx``` is created even if the On Exit database method is undefined.

Transfer
---

**About**

Only bulk and interrput transfers are supported. Control and isochronous transfers are not supported. Read more about USB transfers at [USB in a NutShell](http://www.beyondlogic.org/usbnutshell/usb1.shtml).

* Example read/write method

```
USB GET DEVICE LIST ($deviceRefs;$vendorIds;$productIds;$usb_error)
For ($i;1;Size of array($deviceRefs))
$deviceRef:=$deviceRefs{$i}
$deviceHandleRef:=USB Open ($deviceRef)
$productName:=LIBUSB_Get_product ($deviceHandleRef)
ARRAY OBJECT($interfaces;0)
LIBUSB_GET_INTERFACES ($deviceHandleRef;->$interfaces)
For ($j;1;Size of array($interfaces))
ARRAY OBJECT($altsetting;0)
OB GET ARRAY($interfaces{$j};"altsetting";$altsetting)
For ($k;1;Size of array($altsetting))
$interface:=OB Get($altsetting{$k};"bInterfaceNumber")
USB CLAIM INTERFACE ($deviceHandleRef;$interface;$usb_error)
If ($usb_error=LIBUSB_SUCCESS)
ARRAY OBJECT($endpoint;0)
OB GET ARRAY($altsetting{$k};"endpoint";$endpoint)
If (Size of array($endpoint)#0)
  //you can claim the interface of the Bluetooth host controller, but it has no endpoints
For ($l;1;Size of array($endpoint))
$eEndpointAddress:=OB Get($endpoint{$l};"bEndpointAddress")
C_BLOB($data)
$timeout:=3000  //millisec
USB INTERRUPT TRANSFER ($deviceHandleRef;$eEndpointAddress;$data;$timeout;$status;$usb_error)
If ($usb_error=LIBUSB_SUCCESS)
ALERT("interrupt "+LIBUSB_Get_direction ($eEndpointAddress)+$productName+": "+USB Get error description ($status))
Else 
  //ALERT("can't read/write "+$productName+": "+USB Get error description ($usb_error))
End if 

USB BULK TRANSFER ($deviceHandleRef;$eEndpointAddress;$data;$timeout;$status;$usb_error)
If ($usb_error=LIBUSB_SUCCESS)
ALERT("bulk "+LIBUSB_Get_direction ($eEndpointAddress)+$productName+": "+USB Get error description ($status))
Else 
  //ALERT("can't read/write "+$productName+": "+USB Get error description ($usb_error))
End if 

End for 
End if 
USB RELEASE INTERFACE ($deviceHandleRef;$interface;$usb_error)

Else 
  //ALERT("can't claim "+$productName+": "+USB Get error description ($usb_error))
End if 
End for 
End for 
USB CLOSE ($deviceHandleRef)
End for 
```

**Note**: Apparently you can't claim most HID devices on Mac, unless you fiddle with kext (kernel extensions).

[https://github.com/libusb/libusb/wiki/FAQ](https://github.com/libusb/libusb/wiki/FAQ)

Perhaps one should use [HID_Utilities](https://developer.apple.com/library/mac/samplecode/HID_Utilities/Introduction/Intro.html) instead.

On my computer, I could claim the Camera interface, but it has no endpoints to work with.

I could also claim the Super Drive, but only if connected via a USB hub that does not supply power (to make it inactive, I suppose).

Feedback on real devices are welcome...

**Note**: For prerequisites on Windows see https://github.com/libusb/libusb/wiki/Windows.
