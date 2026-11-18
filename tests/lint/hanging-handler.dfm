object HhForm: THhForm
  Left = 0
  Top = 0
  Caption = 'HhForm'
  ClientHeight = 200
  ClientWidth = 300
  OnCreate = FormCreate
  object btnHhBound: TButton
    Left = 8
    Top = 8
    Caption = 'Bound'
    OnClick = btnHhBoundClick
  end
  object edtHhExit: TEdit
    Left = 8
    Top = 40
    OnExit = edtHhExitExit
  end
end