unit ftRawInputInterceptor;

interface

uses
  Windows
  ,classes
  ,unRawInput
  ,Messages
  ,JvHidControllerClass
  ,JvComponentBase
  ,Registry
//commented out with related methods as it doesn't currently work, just experimenting  
//  ,JvSetupApi
  ;

const
  UM_SCANDEVICE = WM_USER + 1;
  CM_BARCODE_SCANNED = WM_USER + 2;

type
  TKbdMsg = packed record
    Msg: Cardinal;
    case Integer of
      0: (
        WParam: WPARAM;
        LParam: LPARAM;
        Result: LRESULT
        );
      1: (
        WParamLo: Word;
        WParamHi: Word;
        LParamLo: Word;
        LParamHi: Word;
        ResultLo: Word;
        ResultHi: Word
        );
      2: (
        wpSink :ShortInt;
        wpVKey :word;
        wpFlags :word;
        wpMake :word;
        lpHandle :cardinal;
        );
  end;

  TRawInputKeyBoard = class(TObject)
    Name :string; //device instance path shown in Device Manager Properties dialog - inclludes serialnum
    SerialNum :string;  //windows generated serial number for device
    VendorID :Word;
    ProductID :Word;
    MultipleInterfaceID :Byte;  //applies only to composite devices
    Revision: Word;
    IsComposite :Boolean;
    VendorName :string;
    ProductName :string;
    DeviceHandle :THANDLE;
  end;

  TftRawInputInterceptor = class(TComponent)
  private
    FRegistry :TRegistry;
    FHidCtl :TJvHidDeviceController;
    FErrors :TStrings;
    FSkipLegacy :boolean;
    FStatus :string;
    FTargetWindowHandle :HWND;
    FDevices: array of RAWINPUTDEVICELIST;
    FDevicesOfInterest :TStrings;
    FRawInputKeyBoardCount: Integer;
    FRawInputKeyBoards: TStrings;
    FBarcode :array[0..1024] of char;  //buffer used to compile barcode input
    FBarCodeIndex :integer;
    FOnKeyboardChange :TNotifyEvent;
    FDeviceToAutoReCapture :string;   //name of last captured device
    FReCaptureOnConnect :Boolean;
    function AppMsg_WMINPUT(var MsgIn: TMsg): boolean;
    procedure GetRawInputDeviceList;
    function GetKeyBoards: TStrings;
    function GetCapturedKeyBoards: TStrings;
    function IsADeviceOfInterest(DeviceHandle :THandle) :boolean;
    function GetLastErrorMsg(Errorcode: integer; const PrefixString: string): string;
    function MatchKeyboardToHIDDevice(HidDev: TJvHidDevice; const Idx: Integer): Boolean;
    procedure DeviceArrived(HidDev: TJvHidDevice);
    procedure DeviceRemoved(HidDev: TJvHidDevice);
    procedure MonitorUSBPorts(const Value: Boolean);
    function GetDeviceName(const DevicePath: string): string;
    function GetVendorID(const DevicePath: string): Word;
    function GetProductID(const DevicePath: string): Word;
    function GetMultipleInterfaceID(const DevicePath: string): Word;
    function IsCompositeDevice(const DevicePath: string): boolean;
    function GetRevision(const DevicePath: string): Word;
//    procedure GetProductDescription(KeyBoard :TRawInputKeyBoard);
    procedure GetSerialNum(Keyboard :TRawInputKeyboard);
//    function ConvertDbccNameToFriendlyName(
//      aDeviceInterfaceDbccName: string): string;
//    function TryGetDeviceFriendlyName(var aDeviceInfoHandle: HDEVINFO;
//      var aDeviceInfoData: SP_DEVINFO_DATA; out aFriendlyName: string): boolean;
  protected
    procedure DoOnKeyboardChange;
  public
    constructor Create(aOwner :TComponent); override;
    destructor Destroy; override;

    function RegisterToIntercept(ApplicationWindowHandle :HWND) :boolean;
    procedure RefreshKeyboards;
    procedure AppMsgHandler(var Msg: TMsg; var Handled: Boolean);
    procedure CaptureInputFromDevice(DeviceName :string; AutoReConnect :Boolean = false);
    procedure StopCapturingDevice(DeviceName :string);
    procedure Start;
    procedure Stop;

    property Status :string read FStatus;
    property TargetWindowHandle :HWND read FTargetWindowHandle write FTargetWindowHandle;  //window to forward messages to
    property KeyBoards :TStrings read GetKeyBoards;
    property CapturedKeyboards :TStrings read GetCapturedKeyboards;
    property Errors :TStrings read FErrors;
    property RecaptureOnConnect :boolean read FReCaptureOnConnect write FReCaptureOnConnect;
    property OnKeyboardChange :TNotifyEvent read FOnKeyboardChange write FOnKeyboardChange;
  end;

implementation

uses
  SysUtils, Dialogs, Forms, System.StrUtils, System.Masks;

const
  MIPrefix = '&MI_';
  MIPrefixLength = Length(MIPrefix);
  MILength = 2; //2 digit hex interface ID number
  VIDPrefixLength = Length('\\?\HID#VID_');   //prefix b4 4 digit hex Vendor ID
  VIDorPIDLength = 4;  //4 digit hex number to identify Vendor/Product
  PIDPrefix = '&PID_';
  PIDPrefixLength = Length(PIDPrefix);  //prefix b4 4 digit hex Product ID after Vendor ID
  RevisionPrefix = '&REV_';
  RevisionPrefixLength = Length(RevisionPrefix);
  RevisionLength = 4;  //4 digit hex revision number (has leading 0s)

var
  G_rDta :RAWINPUT;

procedure TftRawInputInterceptor.RefreshKeyboards;
//if we set the count to be 0, the next time Keyboards are accessed the list will be rebuilt
begin
  FRawInputKeyBoardCount := 0;
end;

function TftRawInputInterceptor.RegisterToIntercept(ApplicationWindowHandle: HWND): boolean;
var
  cSize: Cardinal;
  // You have to pass an array of devices to capture
  rRawDev: array[0..0] of RAWINPUTDEVICE;
begin
  { I could not find a list of which UsagePage and Usage values mean what. However
  I did find somewhere that the combination below (1, 6) is for the keyboard
  and mouse devices. There appears to be no way to separate them so you only
  get keyboard messages.}
  rRawDev[0].usUsagePage := 1;
  rRawDev[0].usUsage := 6;

  { INPUTSINK tells the system to send the messages even when the specified
  target window does NOT have the focus.
  NOLEGACY tells the system not to translate the messages into the KEYUP and
  KEYDOWN messages, so your application's OnKeyUp, OnKeyPress, OnKeyDown
  events would never be executed.}
  rRawDev[0].dwFlags := RIDEV_INPUTSINK; // RIDEV_NOLEGACY;

  { I was not able to get this working correctly using a TForm window handle
  as the target, so I used the Application window handle and wrote a procedure
  for the Application.OnMessage event.}
  rRawDev[0].hwndTarget := ApplicationWindowHandle;
  cSize	 := sizeOf(RAWINPUTDEVICE);

  if (RegisterRawInputDevices(@rRawDev, 1, cSize)) then
  begin
    FStatus := 'SuccessFully Registered';
    result := True;
  end
  else
  begin
    result := False;
    FStatus := 'RegisterRawInputDevices Failed: '#13#10 + SysErrorMessage(GetLastError());
  end;

  GetRawInputDeviceList;
end;

function TftRawInputInterceptor.GetKeyBoards :TStrings;
begin
  if (FRawInputKeyBoardCount = 0) then  //should always have at least 1 keyboard
    GetRawInputDeviceList;
  Result := FRawInputKeyBoards
end;

procedure TftRawInputInterceptor.GetRawInputDeviceList;

(*
Info from https://www.silabs.com/community/interface/knowledge-base.entry.html/2013/11/21/windows_usb_devicep-aGxD

USB Device Path Format

In most cases, Windows formats the USB device path as follows:

\?usb#vid_vvvv&pid_pppp#ssss#{gggggggg-gggg-gggg-gggg-gggggggggggg}

Where:
vvvv is the USB vendor ID represented in 4 hexadecimal characters.
pppp is the USB product ID represented in 4 hexadecimal characters.
ssss is the USB serial string represented in n characters.
gggggggg-gggg-gggg-gggg-gggggggggggg is the device interface GUID that is used to link applications to device with specific drivers loaded.

For a composite device with multiple interfaces, the device path for each interface might look something like:

\?usb#vid_vvvv&pid_pppp&mi_ii#aaaaaaaaaaaaaaaa#{gggggggg-gggg-gggg-gggg-gggggggggggg}

Where:
vvvv is the USB vendor ID represented in 4 hexadecimal characters.
pppp is the USB product ID represented in 4 hexadecimal characters.
ii is the USB interface number.
aaaaaaaaaaaaaaaa is a unique, Windows-generated string based on things such as the physical USB port address and/or interface number.
gggggggg-gggg-gggg-gggg-gggggggggggg is the device interface GUID that is used to link applications to device with specific drivers loaded.

The device path is useful for locating the USB device registry keys, where additional settings and information are stored for the device instance. USB device registry keys are stored in the following location:

[HKLMSYSTEMCurrentControlSetEnumUSBVID_vvvv&PID_ppppssss],

Where:
vvvv is the USB vendor ID.
pppp is the USB product ID.
ssss is the USB serial string or the unique, Windows-generate string.


Info from https://docs.microsoft.com/en-us/windows-hardware/drivers/install/standard-usb-identifiers

When a new USB device is plugged in, the system-supplied USB hub driver composes the following device ID by using information extracted from the device's device descriptor:

USB\VID_v(4)&PID_d(4)&REV_r(4)

Where:

    v(4) is the 4-digit vendor code that the USB committee assigns to the vendor.

    d(4) is the 4-digit product code that the vendor assigns to the device.

    r(4) is the revision code.

This information is not complete since I have the following DevicePaths (note the HID prefix):

\\?\HID#VID_0C2E&PID_0200#7&2c5909c0&0&0000#{884b96c3-56ef-11d1-bc8c-00a0c91405dd}
\\?\HID#VID_046D&PID_C52B&REV_1203&MI_02&Qid_400F&WI_02&Class_0000000A&Col01#9&fba92cf&0&0000#{884b96c3-56ef-11d1-bc8c-00a0c91405dd}
\\?\HID#VID_046D&PID_C52B&MI_00#8&296adbeb&0&0000#{884b96c3-56ef-11d1-bc8c-00a0c91405dd}

where the devices are: Metrologic Scanner, HID Keyboard Device and a Logitech K750 cordless keyboard respectively

What I have gathered is:

KBName is synonymous with the Device Instance Path in Device Manager Properties window and uses the
form '\\?\HID#VID_VVVV&PID_PPPP[&....]#SSSSSSSSSSSSSSSS#{884b96c3-56ef-11d1-bc8c-00a0c91405dd}'
where VVVV is the VendorID, PPPP is the Product ID (both in Hex)
followed by one or more other properties [&....]
then a '#' as a separator
and SSSSSSSSSSSSSSSS is the serial number Windows generates
followed by # and the class guid

*)

const
  ErrorValue = $FFFFFFFF;  //largest possible 32bit UINT

var
  I :integer;
  DeviceCount :uint;
  dwSize :cardinal;
  DevicePath: array[0..1023] of Char;
  aRawInputKeyBoard :TRawInputKeyBoard;
  BytesCopied :UINT;
  NumDevices :UINT;
begin
  dwSize := SizeOf(RAWINPUTDEVICELIST);
  DeviceCount := 0;
  //call to get the device count
  if (unRawInput.GetRawInputDeviceList(nil,DeviceCount,dwSize) <> 0) then
    raise ENotSupportedException.Create(SysErrorMessage(GetLastError()));

  if DeviceCount > 0 then
  begin
    SetLength(FDevices, DeviceCount);

    FRawInputKeyBoards.Clear;
    NumDevices := unRawInput.GetRawInputDeviceList(@FDevices[0], DeviceCount, dwSize);
    if (NumDevices <> ErrorValue) then
    begin
      for I := 0 to DeviceCount - 1 do
      begin
        if FDevices[I].dwType = RIM_TYPEKEYBOARD then
        begin
          Inc(FRawInputKeyBoardCount);
          dwSize := SizeOf(DevicePath);
          ZeroMemory(@DevicePath,dwSize);
          BytesCopied := GetRawInputDeviceInfo(FDevices[I].hDevice, RIDI_DEVICENAME, @DevicePath, dwSize);
          //only list keyboards we successfully got details for.  Not sure why
          //some "keyboards" return an error code and SysErrorMessage(getLastError())
          //returns 'Operation Completed Successfully'
          if BytesCopied <> ErrorValue then
          begin
            aRawInputKeyBoard := TRawInputKeyBoard.Create;
            aRawInputKeyBoard.Name := GetDeviceName(DevicePath);
            GetSerialNum(aRawInputKeyBoard);
            aRawInputKeyBoard.DeviceHandle := FDevices[I].hDevice;
            //extract device info so we can match it with HID device to get other attributes
            aRawInputKeyBoard.VendorID := GetVendorID(aRawInputKeyBoard.Name);
            aRawInputKeyBoard.ProductID := GetProductID(aRawInputKeyBoard.Name);
            aRawInputKeyBoard.IsComposite := IsCompositeDevice(aRawInputKeyBoard.Name);
            if aRawInputKeyBoard.IsComposite then
              aRawInputKeyBoard.MultipleInterfaceID := GetMultipleInterfaceID(aRawInputKeyBoard.Name);
            aRawInputKeyBoard.Revision := GetRevision(aRawInputKeyBoard.Name);

            FRawInputKeyBoards.AddObject(aRawInputKeyBoard.Name, aRawInputKeyBoard);
          end;
        end;
      end;

      //Enumerate all the HID devices and match them with the RawInput Keyboards
      FHidCtl.DeviceChange;  //trigger load of HID information
      FHidCtl.OnEnumerate := MatchKeyboardToHIDDevice;
      FHidCtl.Enumerate;
    end
    else
      raise ENotSupportedException.Create('GetRawInputDeviceList returned an error - RAW Input API appears not to be suppported');
  end;
end;

//procedure TftRawInputInterceptor.GetProductDescription(KeyBoard :TRawInputKeyBoard);
////this method attempts to read the product description from the registry but it
////does not always match what Device Manager reports so it is not currently used
//var
//  RegKey :string;
//  slDecode :TStringList;
//begin
//  RegKey := 'SYSTEM\CurrentControlSet\Enum\' + Copy(KeyBoard.Name.Replace('#','\',[rfReplaceAll]),5,Length(KeyBoard.Name)-5);
//  if FRegistry.OpenKeyReadOnly(RegKey) then
//  begin
//    slDecode := TStringList.Create;
//    try
//      slDecode.Delimiter := ';';
//      slDecode.StrictDelimiter := True;
//      slDecode.DelimitedText := FRegistry.ReadString('DeviceDesc');
//      KeyBoard.ProductName := slDecode[slDecode.Count -1];
//    finally
//      slDecode.Free;
//    end;
//    FRegistry.CloseKey;
//  end;
//end;


function TftRawInputInterceptor.GetVendorID(const DevicePath: string): Word;
begin
  if DevicePath.Contains('VID_') then
    Result := StrToInt('$'+(Copy(DevicePath,VIDPrefixLength+1,VIDorPIDLength)))
  else
    Result := 0;
end;

function TftRawInputInterceptor.GetRevision(const DevicePath: string): Word;
var
  Index :Integer;
begin
  Index := PosEx(RevisionPrefix,DevicePath);
  if (Index = 0) then
    Result := 0
  else
    Result := StrToInt('$'+Copy(DevicePath,Index + Length(RevisionPrefix),RevisionLength));
end;

function TftRawInputInterceptor.GetMultipleInterfaceID(const DevicePath: string): Word;
var
  Index :Integer;
begin
  Index := PosEx(MIPrefix,DevicePath);
  if (Index = 0) then
    Result := 0
  else
    Result := StrToInt('$'+Copy(DevicePath,Index + MIPrefixLength,MILength));
end;

function TftRawInputInterceptor.GetProductID(const DevicePath: string): Word;
begin
  if DevicePath.Contains(PIDPrefix) then
    Result := StrToInt('$'+Copy(DevicePath,VIDPrefixLength+VIDorPIDLength+PIDPrefixLength+1,VIDorPIDLength))
  else
    Result := 0;
end;

function TftRawInputInterceptor.GetCapturedKeyBoards: TStrings;
begin
  Result := FDevicesOfInterest;
end;

function TftRawInputInterceptor.GetDeviceName(const DevicePath :string) :string;
//returns the DevicePath up to and including the Windows Serial Number
var
  I :Integer;
begin
  //get the position of the last # character which delimits the Windows generated serial Number
  I := Pos('#',AnsiReverseString(DevicePath));
  //copy all characters up to and including last #
  Result := Copy(DevicePath,1,Length(DevicePath) - I + 1);
end;

procedure TftRawInputInterceptor.GetSerialNum(Keyboard :TRawInputKeyboard);
var
  slDecode :TStringList;
begin
  slDecode := TStringList.Create;
  try
    slDecode.Delimiter := '#';
    slDecode.StrictDelimiter := True;
    slDecode.DelimitedText := Keyboard.Name;
    KeyBoard.SerialNum := slDecode[slDecode.Count - 2];  //end '#' yields and empty last string 
  finally
    slDecode.Free;
  end;
end;

function TftRawInputInterceptor.IsADeviceOfInterest(DeviceHandle: THandle): boolean;
var
  I :integer;
begin
  Result := False;
  for I := 0 to FDevicesOfInterest.Count - 1 do
  begin
    if TRawInputKeyBoard(FDevicesOfInterest.Objects[I]).DeviceHandle = DeviceHandle then
    begin
      Result := True;
      break;
    end;
  end;
end;

function TftRawInputInterceptor.IsCompositeDevice(const DevicePath: string): boolean;
begin
  Result := DevicePath.Contains(MIPrefix);
end;

procedure TftRawInputInterceptor.AppMsgHandler (var Msg: TMsg; var Handled: Boolean);
{ This procedure will be called by the Application's window procedure for EVERY
message received. It is critical that this procedure be as tight and error
free as possible (it will be executed hundreds of times per second).
Especially since we have registered for RAW INPUT from the mouse. }
begin
  { If you set Handled to True, then the message will not be passed on to your
  application forms and controls. }
  Handled := False;

  { The WM_INPUT message is the RAW INPUT that must be interrogated in order
  to determine what key was pressed and on which device. Immediately after
  this message the application will receive a WM_KEYDOWN, WM_KEYUP and
  possibly other messages relating to the keystroke (these are referred to
  as the legacy messages). The FSkipLegacy flag is set in AppMsg_WMINPUT if
  the keystroke/device is handled.}
  if (
    (FTargetWindowHandle <> 0) {and ((oDevList.Count > 0) or (bScanning))}
  )then
  begin
    case Msg.message of
      WM_INPUT:	 Handled := AppMsg_WMINPUT(Msg);
      WM_KEYFIRST..WM_KEYLAST:	Handled := FSkipLegacy;
    end;
  end;
end;

function TftRawInputInterceptor.AppMsg_WMINPUT (var MsgIn: TMsg): boolean;
{ This function is called to handle a WM_INPUT message. It will determine if
it is a message of interest and post a message to my form if it is. The
function returns True if the message is handled, otherwise it returns false.
The function also sets this object's FSkipLegacy flag to True if the
message is handled, or false if it is not.}
var
  iRtc:	 integer;
  cSize: cardinal;
  InputChar: char;	// Message structure for application message
begin
  result := false;

  // Get the Header of the RAW INPUT
  cSize := sizeOf(RAWINPUTHEADER);
  G_rDta.header.dwSize := sizeOf(RAWINPUTHEADER);
  iRtc := GetRawInputData(HRAWINPUT(MsgIn.LParam),
  RID_HEADER, @G_rDta.header, cSize, sizeof(RAWINPUTHEADER));

  if (iRtc >= 0) then
  begin
    { Remember, we had to register for Keyboard and mouse messages. But we
    are only interested in the KEYBOARD messages. }
    if (G_rDta.header.dwType = RIM_TYPEKEYBOARD) then
    begin
      // Get the actual RAW INPUT DATA
      cSize := G_rDta.header.dwSize;
      iRtc := GetRawInputData (HRAWINPUT(MsgIn.LParam),
      RID_INPUT, @G_rDta, cSize, sizeOf(RAWINPUTHEADER));

      if (iRtc >= 0) then
      begin

        if (not IsADeviceOfInterest(G_rDta.header.hDevice)) then
        { We are not scanning for the device, so see if this message came from
        one of the devices of interest. While I currently do not have a
        need for multiple devices, the object is written to handle more than
        one (for future enhancements) }
        begin // Device is not in the device list. Call DefRawInputProc
          FSkipLegacy := false;
          DefRawInputProc (MsgIn.hwnd, MsgIn.message, MsgIn.wParam, MsgIn.lParam);
        end
        else
        begin
          { The message came from a device we are interested in. Post a message
          back to the specified form using my Message structure. Note that
          the message ID is determined by adding WM_USER to the Keyboard Message
          from the RAW INPUT DATA block. The message there will be WM_KEYDOWN
          or WM_KEYUP. This is NOT the message from the Windows Message queue }
          FSkipLegacy := true;	// We do not want the Legacy Messages

          //add the digit to the BarCode until we get CR (chr(13))
          if (G_rDta.keyboard.Flags = RI_KEY_BREAK) then //only capture key down input messages otherwise have duplicates with key up ones
          begin
            InputChar := Chr(G_rDta.keyboard.VKey);
            if InputChar = #13 then
            begin
              FBarCodeIndex := 0;
              FSkipLegacy := False;
              SendMessage(Application.ActiveFormHandle,CM_BARCODE_SCANNED,Integer(@FBarCode),0);
              ZeroMemory(@FBarCode, sizeOf(FBarCode));   //re-initialize barcode buffer
            end
            else
            begin
              FBarcode[FBarCodeIndex] := InputChar;
              Inc(FBarCodeIndex,1);
            end;
          end;
          result := True;
        end;

      { If some error occurs, we really do NOT want to show a message box from
      within the Message loop. So the error message is added to the object's
      error list. The application can read them and clear them as desired.}
      end
      else
      begin
        FErrors.Add(GetLastErrorMsg(GetLastError(),'GetRawInputData (RID_INPUT) Failed: '));
      end;
    end;
  end
  else
  begin
    FErrors.Add(GetLastErrorMsg(GetLastError(),'GetRawInputData (RID_HEADER) Failed: '));
  end;
end;

function TftRawInputInterceptor.GetLastErrorMsg(Errorcode :integer; const PrefixString :string) :string;
begin
  result := PrefixString + #13#10 + SysErrorMessage(ErrorCode);
end;

procedure TftRawInputInterceptor.Start;
begin
  MonitorUSBPorts(True);
end;

procedure TftRawInputInterceptor.Stop;
begin
  MonitorUSBPorts(False);
end;

procedure TftRawInputInterceptor.StopCapturingDevice(DeviceName: string);
//if the device specified is already in the list ignore the call, otherwise
//add it to the list of devices of interest
var
  I: Integer;
begin
  //remove device of interest if one exists
  I := FDevicesOfInterest.IndexOf(DeviceName);
  if (I <> -1) then
    FDevicesOfInterest.Delete(I);
end;

procedure TftRawInputInterceptor.CaptureInputFromDevice(DeviceName: string; AutoReConnect :Boolean = false);
//if the device specified is already in the list ignore the call, otherwise
//add it to the list of devices of interest
var
  I: Integer;
begin
  FReCaptureOnConnect := AutoReConnect;
  if AutoReConnect then
    FDeviceToAutoReCapture := DeviceName
  else
    FDeviceToAutoReCapture := EmptyStr;

  //remove previous device of interest if one exists
  I := FDevicesOfInterest.IndexOf(DeviceName);
  if (I <> -1) then
    FDevicesOfInterest.Delete(I);

  I := FRawInputKeyBoards.IndexOf(DeviceName);
  if (I <> -1) then
    FDevicesOfInterest.AddObject(TRawInputKeyBoard(FRawInputKeyBoards.Objects[I]).Name,FRawInputKeyBoards.Objects[I]);
end;

constructor TftRawInputInterceptor.Create(aOwner :TComponent);
begin
  inherited Create(aOwner);
  FRegistry := TRegistry.Create;
  FRegistry.RootKey := HKEY_LOCAL_MACHINE;
  
  FHidCtl := TJvHidDeviceController.Create(Self);
  FHidCtl.OnEnumerate := MatchKeyboardToHIDDevice;

  FRawInputKeyBoards := TStringList.Create(True);  //owns objects
  FDevicesOfInterest := TStringList.Create;
  FErrors := TStringList.Create;

  //register a window handle to receive RAW Input
  RegisterToIntercept(Application.Handle);
  //inject the interceptor's message handler
  Application.OnMessage := AppMsgHandler;
end;

procedure TftRawInputInterceptor.DeviceArrived(HidDev: TJvHidDevice);
var
  DeviceName :string;
begin
  //refresh input devices
  GetRawInputDeviceList;

  //update the device handle for the device if it was previously Captured
  DeviceName := GetDeviceName(HidDev.PnPInfo.DevicePath);

  StopCapturingDevice(DeviceName);

  if FReCaptureOnConnect and SameText(DeviceName,FDeviceToAutoReCapture) then
    CaptureInputFromDevice(DeviceName,FReCaptureOnConnect);

  DoOnKeyboardChange;
end;

procedure TftRawInputInterceptor.DeviceRemoved(HidDev: TJvHidDevice);
var
  I :Integer;
  DeviceName :string;
begin
  DeviceName := GetDeviceName(HidDev.PnPInfo.DevicePath);

  StopCapturingDevice(DeviceName);

  //remove from list of available keyboards
  I := FRawInputKeyBoards.IndexOf(DeviceName);
  if (I <> -1) then
    FRawInputKeyBoards.Delete(I);

  //update keyboard count
  FRawInputKeyBoardCount := FRawInputKeyBoards.Count;

  DoOnKeyboardChange;
end;

procedure TftRawInputInterceptor.DoOnKeyboardChange;
begin
  if Assigned(FOnKeyboardChange) then
    FOnKeyboardChange(Self);
end;

destructor TftRawInputInterceptor.Destroy;
begin
  FRawInputKeyBoards.Free;
  FDevicesOfInterest.Free;
  FErrors.Free;
  FRegistry.Free;
  inherited;
end;

function TftRawInputInterceptor.MatchKeyboardToHIDDevice(HidDev: TJvHidDevice; const Idx: Integer): Boolean;
//return False to stop enumeration of HID Devices.  Since we want to enumerate over all plugged in HID devices
//we always return True.
var
  I: Integer;
  KeyBoard :TRawInputKeyBoard;
  HidDeviceName :string;
begin
  HidDeviceName := GetDeviceName(HidDev.PnPInfo.DevicePath);
  //hid device names and those from the RAW Input API differ in alphabetic capitalization so use a case-insensitive compare
  I := FRawInputKeyBoards.IndexOf(HidDeviceName);
  //we will get numerous HID Devices reported, most of which will not match a keyboard in our list
  if (I <> -1) then
  begin
    KeyBoard := TRawInputKeyBoard(FRawInputKeyBoards.Objects[I]);
    HidDev.CheckOut;  //device must be checked out to read Vendor and Product name
    KeyBoard.VendorName := HidDev.VendorName;

    //deviceDescription seems to provide a more accurate description for Composite devices
    if (KeyBoard.IsComposite) then
      KeyBoard.ProductName := HidDev.PnPInfo.DeviceDescr
    else
      KeyBoard.ProductName := HidDev.ProductName;
  end;
  Result := True;
end;

procedure TftRawInputInterceptor.MonitorUSBPorts(const Value :Boolean);
begin
  if Value then
  begin
    FHidCtl.OnDeviceUnplug := DeviceRemoved;
    FHidCtl.OnArrival := DeviceArrived;
  end
  else
  begin
    FHidCtl.OnDeviceUnplug := nil;
    FHidCtl.OnArrival := nil;
  end
end;

//function TftRawInputInterceptor.ConvertDbccNameToFriendlyName(aDeviceInterfaceDbccName : string) : string;
//var
//  deviceInfoHandle : HDEVINFO;
//  deviceInfoData : SP_DEVINFO_DATA;
//  deviceInterfaceData : SP_DEVICE_INTERFACE_DATA;
//  memberIndex : Cardinal;
//  friendlyname :string;
//begin
//  result := '';
//
//  // Create a new empty "device info set"
//  deviceInfoHandle := SetupDiCreateDeviceInfoList(nil, 0);
//  if deviceInfoHandle <> Pointer(INVALID_HANDLE_VALUE) then
//  begin
//    try
//      // Add "aDeviceInterfaceDbccName" to the device info set
//      FillChar(deviceInterfaceData, SizeOf(deviceInterfaceData), 0);
//      deviceInterfaceData.cbSize := SizeOf(deviceInterfaceData);
//      if SetupDiOpenDeviceInterface(deviceInfoHandle, PChar(aDeviceInterfaceDbccName),     0, @deviceInterfaceData) then
//      begin
//        try
//          // iterate over the device info set
//          // (though I only expect it to contain one item)
//          memberIndex := 0;
//          while true do
//          begin
//            // get device info that corresponds to the next memberIndex
//            FillChar(deviceInfoData, SizeOf(deviceInfoData), 0);
//            deviceInfoData.cbSize := SizeOf(deviceInfoData);
//            if not SetupDiEnumDeviceInfo(deviceInfoHandle, memberIndex, deviceInfoData) then
//            begin
//              // The enumerator is exhausted when SetupDiEnumDeviceInfo returns false
//              break;
//            end
//            else
//            begin
//              Inc(memberIndex);
//            end;
//
//            // Get the friendly name for that device info
//            if TryGetDeviceFriendlyName(deviceInfoHandle, deviceInfoData, {out} friendlyName) then
//            begin
//              result := friendlyName;
//              break;
//            end;
//          end;
//        finally
//          SetupDiDeleteDeviceInterfaceData(deviceInfoHandle, deviceInterfaceData);
//        end;
//      end;
//    finally
//      SetupDiDestroyDeviceInfoList(deviceInfoHandle);
//    end;
//  end;
//end;

//function TftRawInputInterceptor.TryGetDeviceFriendlyName(
//  var aDeviceInfoHandle : HDEVINFO;
//  var aDeviceInfoData : SP_DEVINFO_DATA;
//  out aFriendlyName : string) : boolean;
//var
//  valueBuffer : array of byte;
//  regProperty : Cardinal;
//  propertyRegDataType : DWord;
//  friendlyNameByteSize : Cardinal;
//  success : boolean;
//begin
//  aFriendlyName := '';
//
//  // Get the size of the friendly device name
//  regProperty := SPDRP_FRIENDLYNAME;
//  friendlyNameByteSize := 0;
//  SetupDiGetDeviceRegistryProperty(
//    aDeviceInfoHandle,     // handle to device information set
//    aDeviceInfoData,       // pointer to SP_DEVINFO_DATA structure
//    regProperty,           // property to be retrieved
//    propertyRegDataType,   // pointer to variable that receives the data type of the property
//    nil,                   // pointer to PropertyBuffer that receives the property
//    0,                     // size, in bytes, of the PropertyBuffer buffer.
//    friendlyNameByteSize); // pointer to variable that receives the required size of PropertyBuffer
//
//  // Prepare a buffer for the friendly device name (plus space for a null terminator)
//  SetLength(valueBuffer, friendlyNameByteSize + sizeof(char));
//
//  success := SetupDiGetDeviceRegistryProperty(
//    aDeviceInfoHandle,
//    aDeviceInfoData,
//    regProperty,
//    propertyRegDataType,
//    @valueBuffer[0],
//    friendlyNameByteSize,
//    friendlyNameByteSize);
//
//  if success then
//  begin
//    // Ensure that only 'friendlyNameByteSize' bytes are used.
//    // Ensure that the string is null-terminated.
//    PChar(@valueBuffer[friendlyNameByteSize])^ := char(0);
//
//    // Get the returned value as a string
//    aFriendlyName := StrPas(PChar(@valueBuffer[0]));
//  end;
//
//  result := success;
//end;

end.

