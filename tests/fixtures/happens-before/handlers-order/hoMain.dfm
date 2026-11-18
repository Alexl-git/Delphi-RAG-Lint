object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'MainForm'
  ClientHeight = 200
  ClientWidth = 300
  OnCreate = FormCreate
  OnShow = DoShowWork
  object btnGo: TButton
    Left = 8
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Go'
    TabOrder = 0
    OnClick = btnGoClick
  end
  object btnOpen: TButton
    Left = 8
    Top = 40
    Width = 75
    Height = 25
    Caption = 'Open'
    TabOrder = 1
    OnClick = btnOpenClick
  end
  object btnCalled: TButton
    Left = 8
    Top = 72
    Width = 75
    Height = 25
    Caption = 'Called'
    TabOrder = 2
    OnClick = btnCalledClick
  end
end
