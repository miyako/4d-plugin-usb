//%attributes = {}
//inspection
USB GET DEVICE LIST($deviceRefs; $vendorIds; $productIds; $usb_error)
//Apple Internal Keyboard / Trackpad
$deviceHandleRef:=USB Open device with vid pid(0x05AC; 0x0264; $usb_error)
If ($usb_error=LIBUSB_SUCCESS)
	$productName:=LIBUSB_Get_product($deviceHandleRef)
	ALERT:C41("found: "+$productName)
	$configuration:=USB Get configuration($deviceHandleRef; $usb_error)
	//do NOT reset the keyboard like this!
	//you will lose control of it after quitting 4D
	//USB SET CONFIGURATION ($deviceHandleRef;1;$usb_error)
	USB CLOSE($deviceHandleRef)
End if 