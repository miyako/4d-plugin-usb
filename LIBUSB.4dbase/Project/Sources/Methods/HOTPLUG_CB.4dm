//%attributes = {"invisible":true}
C_LONGINT:C283($1; $2; $3)

$vendorId:=String:C10($2; "&x")
$productId:=String:C10($3; "&x")

$wId:=Open window:C153(Screen width:C187\2-250; \
Screen height:C188\2-25; \
Screen width:C187\2+250; \
Screen height:C188\2+25; Pop up window:K34:14)

Case of 
	: ($1=USB DEVICE ARRIVED)
		
		MESSAGE:C88("USB DEVICE ARRIVED\rvid:"+$vendorId+"\rpid:"+$productId)
		
	: ($1=USB DEVICE LEFT)
		
		MESSAGE:C88("USB DEVICE LEFT\rvid:"+$vendorId+"\rpid:"+$productId)
		
End case 

DELAY PROCESS:C323(Current process:C322; 180)

CLOSE WINDOW:C154($wId)