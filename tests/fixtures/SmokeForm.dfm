object SmokeForm: TSmokeForm
  Left = 0
  Top = 0
  Caption = 'Smoke Form'
  ClientHeight = 240
  ClientWidth = 320
  OnShow = FormShow
  object btnOK: TButton
    Left = 100
    Top = 200
    Width = 75
    Height = 25
    Caption = 'OK'
    OnClick = btnOKClick
  end
  object cxGrid1: TcxGrid
    Left = 8
    Top = 8
    Width = 304
    Height = 180
    object cxGrid1Level1: TcxGridLevel
      Caption = 'Level1'
    end
  end
end
