object Form1: TForm1
  Left = 0
  Top = 0
  Caption = 'Test Raw Input'
  ClientHeight = 399
  ClientWidth = 748
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  OnClose = FormClose
  OnCreate = FormCreate
  OnShow = FormShow
  DesignSize = (
    748
    399)
  PixelsPerInch = 96
  TextHeight = 13
  object laKeyboardCount: TLabel
    Left = 27
    Top = 133
    Width = 82
    Height = 13
    Caption = 'Keyboards found'
  end
  object laBarCode: TLabel
    Left = 52
    Top = 103
    Width = 57
    Height = 13
    Caption = 'laBarCode'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -11
    Font.Name = 'Tahoma'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object lblCaptured: TLabel
    Left = 33
    Top = 260
    Width = 99
    Height = 13
    Caption = 'Keyboards Captured'
  end
  object Memo1: TMemo
    Left = 27
    Top = 8
    Width = 613
    Height = 84
    Anchors = [akLeft, akTop, akRight]
    Lines.Strings = (
      
        'Focus this control and then scan a barcode.  The barcode content' +
        's should not appear here, they should only appear in the '
      
        'Label below.   If they appear here, you have not captured the sc' +
        'anner.'
      ''
      ''
      
        'To capture the scanner, Right Click in the Keyboard list below a' +
        'nd choose Capture.  To UnCapture the scanner, Right Click in '
      'the Captured scanner list and choose UnCapture.')
    TabOrder = 0
  end
  object lvKeyboards: TListView
    Left = 29
    Top = 152
    Width = 613
    Height = 93
    Anchors = [akLeft, akTop, akRight]
    Columns = <
      item
        Caption = 'Manufacturer'
        MaxWidth = 300
        MinWidth = 50
        Width = 150
      end
      item
        Caption = 'Product'
        MaxWidth = 300
        MinWidth = 50
        Width = 150
      end
      item
        AutoSize = True
        Caption = 'DevicePath'
      end>
    GridLines = True
    ReadOnly = True
    RowSelect = True
    PopupMenu = pmCapture
    TabOrder = 1
    ViewStyle = vsReport
  end
  object btnRefreshKeyBoards: TButton
    Left = 648
    Top = 152
    Width = 75
    Height = 25
    Anchors = [akTop, akRight]
    Caption = '&Refresh'
    TabOrder = 2
    OnClick = btnRefreshKeyBoardsClick
  end
  object lvCaptured: TListView
    Left = 27
    Top = 280
    Width = 613
    Height = 93
    Anchors = [akLeft, akTop, akRight]
    Columns = <
      item
        Caption = 'Manufacturer'
        MaxWidth = 300
        MinWidth = 50
        Width = 150
      end
      item
        Caption = 'Product'
        MaxWidth = 300
        MinWidth = 50
        Width = 150
      end
      item
        AutoSize = True
        Caption = 'DevicePath'
      end>
    GridLines = True
    ReadOnly = True
    RowSelect = True
    PopupMenu = pmUnCapture
    TabOrder = 3
    ViewStyle = vsReport
  end
  object btnClear: TButton
    Left = 144
    Top = 98
    Width = 75
    Height = 25
    Caption = 'Clear &Barcode'
    TabOrder = 4
    OnClick = btnClearClick
  end
  object pmCapture: TPopupMenu
    Left = 680
    Top = 200
    object mnuCapture: TMenuItem
      Caption = '&Capture'
      OnClick = mnuCaptureClick
    end
    object mnuCapturewithReconnect: TMenuItem
      Caption = 'Capture with &AutoReconnect'
      OnClick = mnuCapturewithReconnectClick
    end
  end
  object pmUnCapture: TPopupMenu
    Left = 688
    Top = 296
    object MenuItem2: TMenuItem
      Caption = '&UnCapture'
      OnClick = mnuUnCaptureClick
    end
  end
end
