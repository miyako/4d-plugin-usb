//%attributes = {}
USB GET DEVICE LIST($deviceRefs; $vendorIds; $productIds; $usb_error)
For ($i; 1; Size of array:C274($deviceRefs))
	$deviceRef:=$deviceRefs{$i}
	$deviceHandleRef:=USB Open($deviceRef)
	$productName:=LIBUSB_Get_product($deviceHandleRef)
	ARRAY OBJECT:C1221($interfaces; 0)
	LIBUSB_GET_INTERFACES($deviceHandleRef; ->$interfaces)
	For ($j; 1; Size of array:C274($interfaces))
		ARRAY OBJECT:C1221($altsetting; 0)
		OB GET ARRAY:C1229($interfaces{$j}; "altsetting"; $altsetting)
		For ($k; 1; Size of array:C274($altsetting))
			$interface:=OB Get:C1224($altsetting{$k}; "bInterfaceNumber")
			USB CLAIM INTERFACE($deviceHandleRef; $interface; $usb_error)
			If ($usb_error=LIBUSB_SUCCESS)
				ARRAY OBJECT:C1221($endpoint; 0)
				OB GET ARRAY:C1229($altsetting{$k}; "endpoint"; $endpoint)
				If (Size of array:C274($endpoint)#0)
					//you can claim the interface of the Bluetooth host controller, but it has no endpoints
					For ($l; 1; Size of array:C274($endpoint))
						$eEndpointAddress:=OB Get:C1224($endpoint{$l}; "bEndpointAddress")
						C_BLOB:C604($data)
						$timeout:=3000  //millisec
						USB INTERRUPT TRANSFER($deviceHandleRef; $eEndpointAddress; $data; $timeout; $status; $usb_error)
						If ($usb_error=LIBUSB_SUCCESS)
							ALERT:C41("interrupt "+LIBUSB_Get_direction($eEndpointAddress)+$productName+": "+USB Get error description($status))
						Else 
							//ALERT("can't read/write "+$productName+": "+USB Get error description ($usb_error))
						End if 
						
						USB BULK TRANSFER($deviceHandleRef; $eEndpointAddress; $data; $timeout; $status; $usb_error)
						If ($usb_error=LIBUSB_SUCCESS)
							ALERT:C41("bulk "+LIBUSB_Get_direction($eEndpointAddress)+$productName+": "+USB Get error description($status))
						Else 
							//ALERT("can't read/write "+$productName+": "+USB Get error description ($usb_error))
						End if 
						
					End for 
				End if 
				USB RELEASE INTERFACE($deviceHandleRef; $interface; $usb_error)
				
			Else 
				//ALERT("can't claim "+$productName+": "+USB Get error description ($usb_error))
			End if 
		End for 
	End for 
	USB CLOSE($deviceHandleRef)
End for 