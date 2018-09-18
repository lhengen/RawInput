unit fmMain;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, ftRawInputInterceptor, SetupAPI, Vcl.ComCtrls, Vcl.Menus;

type
  TForm1 = class(TForm)
    Memo1: TMemo;
    lvKeyboards: TListView;
    laKeyboardCount: TLabel;
    btnRefreshKeyBoards: TButton;
    laBarCode: TLabel;
    lvCaptured: TListView;
    lblCaptured: TLabel;
    pmCapture: TPopupMenu;
    mnuCapture: TMenuItem;
    pmUnCapture: TPopupMenu;
    MenuItem2: TMenuItem;
    btnClear: TButton;
    mnuCapturewithReconnect: TMenuItem;
    procedure btnClearClick(Sender: TObject);
    procedure btnRefreshKeyBoardsClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure CMBarcodeScanned(var Message :TMessage); message CM_BARCODE_SCANNED;
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormShow(Sender: TObject);
    procedure mnuCaptureClick(Sender: TObject);
    procedure mnuCapturewithReconnectClick(Sender: TObject);
    procedure mnuUnCaptureClick(Sender: TObject);
  private
    FInputInterceptor: TftRawInputInterceptor;
    procedure DisplayKeyBoardList;
    procedure KeyboardChange(Sender: TObject);
    procedure DisplayCapturedKeyBoardList;
  public
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

procedure TForm1.btnClearClick(Sender: TObject);
begin
  laBarCode.Caption := '';
end;

procedure TForm1.DisplayKeyBoardList;
var
  I :integer;
  lvItem :TListItem;
begin
  lvKeyboards.Clear;
  for I := 0 to FInputInterceptor.KeyBoards.Count - 1 do
  begin
    lvItem := lvKeyboards.Items.Add;
    lvItem.Caption :=  TRawInputKeyBoard(FInputInterceptor.KeyBoards.Objects[I]).VendorName;
    lvItem.SubItems.Add(TRawInputKeyBoard(FInputInterceptor.KeyBoards.Objects[I]).ProductName);
    lvItem.SubItems.Add(FInputInterceptor.KeyBoards[I]);
  end;
  laKeyboardCount.Caption := Format('Keyboards found: %d',[FInputInterceptor.KeyBoards.Count]);
end;

procedure TForm1.DisplayCapturedKeyBoardList;
var
  I :integer;
  lvItem :TListItem;
begin
  lvCaptured.Clear;
  for I := 0 to FInputInterceptor.CapturedKeyboards.Count - 1 do
  begin
    lvItem := lvCaptured.Items.Add;
    lvItem.Caption :=  TRawInputKeyBoard(FInputInterceptor.CapturedKeyBoards.Objects[I]).VendorName;
    lvItem.SubItems.Add(TRawInputKeyBoard(FInputInterceptor.CapturedKeyBoards.Objects[I]).ProductName);
    lvItem.SubItems.Add(FInputInterceptor.CapturedKeyBoards[I]);
  end;
end;

procedure TForm1.CMBarcodeScanned(var Message: TMessage);
var
  sMessage :string;
begin
  sMessage := string(Pointer(Message.WParam));
  laBarCode.Caption := sMessage;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  FInputInterceptor := TftRawInputInterceptor.Create(Self);
  //tell the interceptor who to send the barcode message to
  FInputInterceptor.TargetWindowHandle := Self.Handle;
  //ask to be informed when the list of raw input keyboards changes so we can refresh the display
  FInputInterceptor.OnKeyboardChange := KeyboardChange;
end;

procedure TForm1.KeyboardChange(Sender :TObject);
begin
  DisplayKeyBoardList;
  DisplayCapturedKeyBoardList;
end;

procedure TForm1.btnRefreshKeyBoardsClick(Sender: TObject);
begin
  DisplayKeyBoardList;
end;

procedure TForm1.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  FInputInterceptor.Stop;
end;

procedure TForm1.FormShow(Sender: TObject);
begin
  btnClear.Click;
  DisplayKeyBoardList;
  FInputInterceptor.Start;
end;

procedure TForm1.mnuCaptureClick(Sender: TObject);
var
  I: Integer;
  ListItem :TListItem;
begin
  //we only allow 1 item to be selected at a time
  if (lvKeyboards.SelCount = 1) then
  begin
    for I := 0 to lvKeyboards.Items.Count - 1 do
      if lvKeyboards.Items[I].Selected then
      begin
        //tell the interceptor to ignore input on the device
        FInputInterceptor.CaptureInputFromDevice(lvKeyboards.Items[I].SubItems[1]);
        //add it to the listview
        ListItem := lvCaptured.Items.Add;
        ListItem.Assign(lvKeyboards.Items[I]);
        Break;
      end;
  end;
end;

procedure TForm1.mnuCapturewithReconnectClick(Sender: TObject);
var
  I: Integer;
  ListItem :TListItem;
begin
  //we only allow 1 item to be selected at a time
  if (lvKeyboards.SelCount = 1) then
  begin
    for I := 0 to lvKeyboards.Items.Count - 1 do
      if lvKeyboards.Items[I].Selected then
      begin
        //tell the interceptor to ignore input on the device
        FInputInterceptor.CaptureInputFromDevice(lvKeyboards.Items[I].SubItems[1],True);
        //add it to the listview
        ListItem := lvCaptured.Items.Add;
        ListItem.Assign(lvKeyboards.Items[I]);
        Break;
      end;
  end;
end;

procedure TForm1.mnuUnCaptureClick(Sender: TObject);
var
  I: Integer;
begin
  //we only allow 1 item to be selected at a time
  if (lvCaptured.SelCount = 1) then
  begin
    for I := 0 to lvCaptured.Items.Count - 1 do
      if lvCaptured.Items[I].Selected then
      begin
        //tell the interceptor to ignore input on the device
        FInputInterceptor.StopCapturingDevice(lvCaptured.Items[I].SubItems[1]);
        //remove it from the listview
        lvCaptured.Items.Delete(I);
        Break;
      end;
  end;
end;




end.

