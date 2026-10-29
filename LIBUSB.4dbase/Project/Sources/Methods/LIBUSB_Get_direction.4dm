//%attributes = {"invisible":true}
C_LONGINT:C283($1)
C_TEXT:C284($0)

ASSERT:C1129(Count parameters:C259#0)

$endpoint:=$1

Case of 
	: (($endpoint & 0x0080)=LIBUSB_ENDPOINT_IN)
		$0:="read from "
	: (($endpoint & 0x0080)=LIBUSB_ENDPOINT_OUT)
		$0:="write to "
	Else 
		$0:=""
End case 