object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'events-global'
  ClientHeight = 120
  ClientWidth = 240
  OnCreate = FormCreate
  object btnGo: TButton
    Left = 8
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Go'
    TabOrder = 0
    OnClick = btnGoClick
  end
  object btnAgain: TButton
    Left = 8
    Top = 40
    Width = 75
    Height = 25
    Caption = 'Again'
    TabOrder = 1
    OnClick = btnGoClick
  end
end
