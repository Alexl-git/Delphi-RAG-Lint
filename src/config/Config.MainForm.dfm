object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'drag-lint Configuration'
  ClientHeight = 600
  ClientWidth = 900
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OnShow = FormShow
  PixelsPerInch = 96
  TextHeight = 13
  object pcMain: TPageControl
    Left = 0
    Top = 0
    Width = 900
    Height = 560
    ActivePage = tsIndexes
    Align = alClient
    TabOrder = 0
    object tsIndexes: TTabSheet
      Caption = 'Indexes'
    end
    object tsSettings: TTabSheet
      Caption = 'Settings'
    end
  end
  object pnlBottom: TPanel
    Left = 0
    Top = 560
    Width = 900
    Height = 40
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 1
    object btnSave: TButton
      Left = 8
      Top = 8
      Width = 75
      Height = 25
      Caption = 'Save'
      TabOrder = 0
      OnClick = btnSaveClick
    end
    object btnReload: TButton
      Left = 88
      Top = 8
      Width = 75
      Height = 25
      Caption = 'Reload'
      TabOrder = 1
      OnClick = btnReloadClick
    end
    object btnOpen: TButton
      Left = 168
      Top = 8
      Width = 75
      Height = 25
      Caption = 'Open...'
      TabOrder = 2
      OnClick = btnOpenClick
    end
    object lblConfigPath: TLabel
      Left = 260
      Top = 13
      Width = 3
      Height = 13
    end
  end
end
