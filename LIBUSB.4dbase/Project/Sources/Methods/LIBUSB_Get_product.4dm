//%attributes = {"invisible":true}
C_LONGINT:C283($1)
C_TEXT:C284($0; $productName)

ASSERT:C1129(Count parameters:C259#0)

$deviceHandleRef:=$1
$deviceRef:=USB Get device($deviceHandleRef; $usb_error)
If ($usb_error=LIBUSB_SUCCESS)
	$deviceDescriptor:=USB Get device descriptor($deviceRef; $usb_error)
	If ($usb_error=LIBUSB_SUCCESS)
		$device:=JSON Parse:C1218($deviceDescriptor)
		$index:=OB Get:C1224($device; "iProduct")
		If ($index#0)  //0x00 is the language list
			USB GET DESCRIPTOR($deviceHandleRef; LIBUSB_DT_STRING; $index; $data; $usb_error)
			If ($usb_error=LIBUSB_SUCCESS)
				DELETE FROM BLOB:C560($data; 0; 2)
				$productName:=Convert to text:C1012($data; "utf-16le")
			End if 
		End if 
	End if 
End if 

$0:=$productName