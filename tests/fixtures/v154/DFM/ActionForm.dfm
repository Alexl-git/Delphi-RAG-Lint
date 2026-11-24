object ActionForm: TActionForm
  Left = 0
  object actSave: TAction
    Caption = 'Save'
    OnExecute = actSaveExecute
  end
  object actOpen: TAction
    Caption = 'Open'
  end
  object btn1: TButton
    Action = actSave
    OnClick = btn1Click
    TabOrder = 0
  end
  object btn2: TButton
    Action = actSave
    OnClick = actSaveExecute
    TabOrder = 1
  end
  object btn3: TButton
    Action = actSave
    OnClick = btn3Click
    TabOrder = 2
  end
  object btn4: TButton
    Action = actOpen
    OnClick = btn4Click
    TabOrder = 3
  end
  object btn5: TButton
    Action = actOpen
    TabOrder = 4
  end
  object btn6: TButton
    OnClick = btn6Click
    TabOrder = 5
  end
end
