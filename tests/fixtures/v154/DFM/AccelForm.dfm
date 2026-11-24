object AccelForm: TAccelForm
  Left = 0
  Caption = '&Accel'
  object btnSave: TButton
    Caption = '&Save'
    TabOrder = 0
  end
  object btnSearch: TButton
    Caption = '&Search'
    TabOrder = 1
  end
  object btnOpen: TButton
    Caption = 'Fish && &Chips'
    TabOrder = 2
  end
  object lblC: TLabel
    Caption = '&Cancel'
  end
  object btnAnd: TButton
    Caption = 'Fish && Chips'
    TabOrder = 3
  end
  object chkHidden: TCheckBox
    Caption = '&Volume'
    TabOrder = 4
    Visible = False
  end
  object chkSound: TCheckBox
    Caption = '&Volume'
    TabOrder = 5
  end
  object pgc: TPageControl
    TabOrder = 6
    object ts1: TTabSheet
      Caption = '&General'
      object b1: TButton
        Caption = '&Go'
        TabOrder = 0
      end
    end
    object ts2: TTabSheet
      Caption = '&Options'
      object b2: TButton
        Caption = '&Go'
        TabOrder = 0
      end
    end
  end
  object mm: TMainMenu
    object miFile: TMenuItem
      Caption = '&File'
      object miNew: TMenuItem
        Caption = '&New'
      end
      object miNext: TMenuItem
        Caption = '&Next'
      end
      object miSep: TMenuItem
        Caption = '-'
      end
    end
    object miEdit: TMenuItem
      Caption = '&Edit'
    end
  end
end
