object MainForm: TMainForm
  OnClick = FormClick
  OnDblClick = BaseClick
  OnKeyPress = MissingKey
  object Btn: TButton
    OnClick = BtnClick
    OnExit = GoneExit
  end
end
