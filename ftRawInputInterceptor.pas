unit ftRawInputInterceptor;

interface

uses
  Windows
  ,classes
  ,unRawInput
  ,Messages
  ,JvHidControllerClass
  ,JvComponentBase
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
    Name :string;
    VendorID :Word;
    ProductID :Word;
    VendorName :string;
    ProductName :string;
    DeviceHandle :THANDLE;
  end;

  TftRawInputInterceptor = class(TComponent)
  private
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
    function FindHIDByVIDandPID(HidDev: TJvHidDevice; const Idx: Integer): Boolean;
    procedure DeviceArrived(HidDev: TJvHidDevice);
    procedure DeviceRemoved(HidDev: TJvHidDevice);
    procedure MonitorUSBPorts(const Value: Boolean);
    function GetDeviceName(const DevicePath: string): string;
    function GetVendorID(const DevicePath: string): Word;
    function GetProductID(const DevicePath: string): Word;
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
  SysUtils, Dialogs, Forms, System.StrUtils;

const
  VIDPrefix = Length('\\?\HID#VID_');   //prefix b4 4 digit hex Vendor ID
  VIDorPIDLength = 4;

var
  G_rDta :RAWINPUT;

{ TftRawInputInterceptor }

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
//KBName is in the form '\\?\HID#VID_VVVV&PID_PPPP[&....]#SSSSSSSSSSSSSSSS#{884b96c3-56ef-11d1-bc8c-00a0c91405dd}'
//where VVVV is the VendorID, PPPP is the Product ID (both in Hex)
//followed by one or more other properties [&....]
//then a '#' as a separator
//and SSSSSSSSSSSSSSSS is the serial number Windows generates
//followed by # and the class guid
const
  VIDPrefix = Length('\\?\HID#VID_');   //prefix b4 4 digit hex Vendor ID
  PIDPrefix = Length('&PID_');  //prefix b4 4 digit hex Product ID after Vendor ID
  VIDorPIDLength = 4;

var
  I :integer;
  DeviceCount :uint;
  dwSize :cardinal;
  DevicePath: array[0..1023] of Char;
  aRawInputKeyBoard :TRawInputKeyBoard;
begin
  dwSize := SizeOf(RAWINPUTDEVICELIST);
  DeviceCount := 0;
  //call to get the device count
  unRawInput.GetRawInputDeviceList(nil,DeviceCount,dwSize);
  if DeviceCount > 0 then
  begin
    SetLength(FDevices, DeviceCount);

    FRawInputKeyBoards.Clear;
    if unRawInput.GetRawInputDeviceList(@FDevices[0], DeviceCount, dwSize) <> $FFFFFFFF then
    begin
      for I := 0 to DeviceCount - 1 do
      begin
        if FDevices[I].dwType = RIM_TYPEKEYBOARD then
        begin
          Inc(FRawInputKeyBoardCount);
          dwSize := SizeOf(DevicePath);
          GetRawInputDeviceInfo(FDevices[I].hDevice, RIDI_DEVICENAME, @DevicePath, dwSize);
          aRawInputKeyBoard := TRawInputKeyBoard.Create;
          aRawInputKeyBoard.Name := GetDeviceName(DevicePath);
          aRawInputKeyBoard.DeviceHandle := FDevices[I].hDevice;
          //get VendorID and ProductID from devicename so we can match it with HID device to get other attributes
          aRawInputKeyBoard.VendorID := GetVendorID(aRawInputKeyBoard.Name);
          aRawInputKeyBoard.ProductID := GetProductID(aRawInputKeyBoard.Name);

          FRawInputKeyBoards.AddObject(aRawInputKeyBoard.Name, aRawInputKeyBoard);
        end;
      end;

      //Enumerate all the HID devices and match them with the RawInput Keyboards
      FHidCtl.DeviceChange;  //trigger load of HID information
      FHidCtl.OnEnumerate := FindHIDByVIDandPID;
      FHidCtl.Enumerate;
    end;
  end;
end;

function TftRawInputInterceptor.GetVendorID(const DevicePath: string): Word;
begin
  if DevicePath.Contains('VID_') then
    Result := StrToInt('$'+(Copy(DevicePath,VIDPrefix+1,VIDorPIDLength)))
  else
    Result := 0;
end;

function TftRawInputInterceptor.GetProductID(const DevicePath: string): Word;
const
  PIDPrefix = Length('&PID_');  //prefix b4 4 digit hex Product ID after Vendor ID
begin
  if DevicePath.Contains('&PID_') then
    Result := StrToInt('$'+Copy(DevicePath,VIDPrefix+VIDorPIDLength+PIDPrefix+1,VIDorPIDLength))
  else
    Result := 0;
end;

function TftRawInputInterceptor.GetCapturedKeyBoards: TStrings;
begin
  Result := FDevicesOfInterest;
end;

function TftRawInputInterceptor.GetDeviceName(const DevicePath :string) :string;
//this copies the devicePath up to the class GUID which changes when a device is
//inserted, removed and re-inserted
var
  I :Integer;
begin
  //get the position of the last # character
  I := Pos('#',AnsiReverseString(DevicePath));
  //copy all characters up to and including last #
  Result := Copy(DevicePath,1,Length(DevicePath) - I + 1);
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
  FHidCtl := TJvHidDeviceController.Create(Self);
  FHidCtl.OnEnumerate := FindHIDByVIDandPID;

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
  inherited;
end;

function TftRawInputInterceptor.FindHIDByVIDandPID(HidDev: TJvHidDevice; const Idx: Integer): Boolean;
//returns False to stop enumeration when a match is found
var
  I: Integer;
begin
  for I := 0 to FRawInputKeyBoards.Count - 1 do
  begin
    if (HidDev.Attributes.VendorID = TRawInputKeyBoard(FRawInputKeyBoards.Objects[I]).VendorID)
      and (HidDev.Attributes.ProductID = TRawInputKeyBoard(FRawInputKeyBoards.Objects[I]).ProductID) then
    begin
      HidDev.CheckOut;  //device must be checked out to read Vendor and Product name
      TRawInputKeyBoard(FRawInputKeyBoards.Objects[I]).VendorName := HidDev.VendorName;
      TRawInputKeyBoard(FRawInputKeyBoards.Objects[I]).ProductName := HidDev.ProductName;
    end;
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

end.
