object HintForm: THintForm
  Left = 0
  object Edit1: TEdit
    Hint = 'Name'
    ParentShowHint = False
    ShowHint = False
    TabOrder = 0
  end
  object Edit2: TEdit
    Hint = 'On'
    ParentShowHint = False
    ShowHint = True
    TabOrder = 1
  end
  object Edit3: TEdit
    Hint = 'Inherited'
    TabOrder = 2
  end
  object Panel1: TPanel
    ParentShowHint = False
    TabOrder = 3
    object Edit4: TEdit
      Hint = 'Under a panel'
      TabOrder = 0
    end
  end
  object Edit5: TEdit
    Hint = ''
    ParentShowHint = False
    TabOrder = 4
  end
  object miX: TMenuItem
    Hint = 'menu'
    ParentShowHint = False
  end
end
