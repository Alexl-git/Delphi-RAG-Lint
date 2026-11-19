object PtwForm: TPtwForm
  Left = 0
  Top = 0
  Caption = 'PtwForm'
  ClientHeight = 120
  ClientWidth = 240
  object Btn: TButton
    Left = 8
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Btn'
    TabOrder = 0
    OnClick = BtnLeaf
    OnEnter = PubBound
  end
end
