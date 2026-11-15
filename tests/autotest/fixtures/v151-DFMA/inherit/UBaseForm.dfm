object BaseForm: TBaseForm
  Left = 0
  Top = 0
  ClientHeight = 200
  ClientWidth = 300
  OnShow = FormShow
  object btnSave: TButton
    Caption = 'Save'
    TabOrder = 0
    OnClick = btnSaveClick
  end
  object btnHelp: TButton
    Caption = 'Help'
    TabOrder = 1
    OnClick = btnHelpClick
  end
end
