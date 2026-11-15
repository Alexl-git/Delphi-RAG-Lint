object SelfFreeForm: TSelfFreeForm
  Left = 0
  Top = 0
  ClientHeight = 100
  ClientWidth = 100
  OnKeyPress = FormKeyPress
  object btnClose: TButton
    Caption = 'Close'
    TabOrder = 0
    OnClick = btnCloseClick
  end
end
