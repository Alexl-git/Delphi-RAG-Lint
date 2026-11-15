object FrmMain: TFrmMain
  Left = 0
  Top = 0
  Caption = 'FrmMain'
  ClientHeight = 200
  ClientWidth = 300
  object BtnGo: TButton
    Left = 8
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Go'
    TabOrder = 0
  end
  object Lbl: TLabel
    Left = 8
    Top = 40
    Width = 60
    Height = 15
    Caption = 'BtnGo stays'
    FocusControl = BtnGo
  end
  inline Frame1: TFrmFrame
    Left = 8
    Top = 80
    Width = 200
    Height = 60
    TabOrder = 1
    inherited BtnF: TButton
      Caption = 'Host'
    end
  end
end
