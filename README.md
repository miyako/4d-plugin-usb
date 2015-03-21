# 4d-plugin-usb
Basic implementation (bulk -in/out) of LIBUSB

Example
---

**Device list**

```
ARRAY LONGINT($vendorIds;0)
ARRAY LONGINT($productIds;0)
ARRAY LONGINT($interfaceCounts;0)
ARRAY TEXT($endpointsJSONs;0)

USB DEVICE LIST ($vendorIds;$productIds;$interfaceCounts;$endpointsJSONs)

ARRAY OBJECT($endpoints;0)

For ($i;1;Size of array($endpointsJSONs))

  CLEAR VARIABLE($endpoint)
  $endpoint:=JSON Parse($endpointsJSONs{$i})
  APPEND TO ARRAY($endpoints;$endpoint)

End for 

  //libusb_get_device_list
  //http://libusb.sourceforge.net/api-1.0/group__dev.html#gac0fe4b65914c5ed036e6cbec61cb0b97

```

**Dymo (Untested)**

```
  //http://steventsnyder.com/reading-a-dymo-usb-scale-using-python/

$vendorId:=0x0922
$productId:=0x8003
$interface:=0

$usbId:=USB DEVICE Open ($vendorId;$productId;$interface)

C_BLOB($data)

If ($usbId#0)

  $endpoint:=0
  $maxLength:=6
  $timeout:=1000  //milliseconds

  $receivedLength:=USB Read data ($usbId;$endpoint;$data;$maxLength;$timeout)
    //$swrittenLength:=USB Write data ($usbId;$endpoint;$data;$timeout)

  USB DEVICE CLOSE ($usbId)

End if 

If (BLOB size($data)=6)

  $signature:=$data{0}  //always 3
  $stable:=$data{1}
  $flag:=$data{2}  //2=kg, 11=lb
  Case of 
   : (255=$data{3})
    $scalingFactor:=0.1
   : (254=$data{3})
    $scalingFactor:=0.01
   : (253=$data{3})
    $scalingFactor:=0.001
   Else 
    $scalingFactor:=1
  End case 

  $grams:=$data{4}+(256*$data{5})
  $ounces=$scalingFactor*($data{4}+(256*$data{5}))

End if 
```
