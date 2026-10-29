//%attributes = {"invisible":true}
C_LONGINT:C283($1)
C_POINTER:C301($2)

ASSERT:C1129(Count parameters:C259>1)
ASSERT:C1129(Not:C34(Is nil pointer:C315($2)))
ASSERT:C1129(Type:C295($2->)=Object array:K8:28)

$deviceHandleRef:=$1
$deviceRef:=USB Get device($deviceHandleRef; $usb_error)
If ($usb_error=LIBUSB_SUCCESS)
	$configDescriptor:=USB Get config descriptor($deviceRef; USB CONFIGURATION ACTIVE; *; $usb_error)
	If ($usb_error=LIBUSB_SUCCESS)
		$config:=JSON Parse:C1218($configDescriptor)
		OB GET ARRAY:C1229($config; "interface"; $2->)
	End if 
End if 