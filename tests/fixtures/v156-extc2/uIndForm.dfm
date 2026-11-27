object IndForm: TIndForm
  Left = 0
  Top = 0
  Caption = 'IndForm'
  ClientHeight = 200
  ClientWidth = 300
  OnCreate = FormCreate
  TextHeight = 15
  object Button1: TButton
    Left = 8
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Button1'
    TabOrder = 0
    OnClick = Button1Click
  end
  object Button2: TButton
    Left = 8
    Top = 40
    Width = 75
    Height = 25
    Caption = 'Button2'
    TabOrder = 1
  end
  object Panel1: TIndPanel
    OnPing = PanelPing
    Left = 8
    Top = 72
  end
end
