object GodForm: TGodForm
  Left = 0
  object BtnA: TButton
    OnClick = Dispatch
  end
  object EdtB: TEdit
    OnChange = Dispatch
    OnExit = Dispatch
  end
  object ChkC: TCheckBox
    OnClick = Dispatch
  end
  object CmbD: TComboBox
    OnChange = Dispatch
  end
  object Row1: TButton
    OnClick = RowClick
  end
  object Row2: TButton
    OnClick = RowClick
  end
  object Row3: TButton
    OnClick = RowClick
  end
  object Row4: TButton
    OnClick = RowClick
  end
  object Row5: TButton
    OnClick = RowClick
  end
  object Row6: TButton
    OnClick = RowClick
  end
  object FewE: TEdit
    OnChange = Pair
    OnExit = Pair
  end
  object Oth1: TButton
    OnClick = Other
  end
  object Oth2: TButton
    OnClick = Other
  end
  object Oth3: TButton
    OnDblClick = Other
  end
  object Oth4: TButton
    OnDblClick = other
  end
  object Cap5: TLabel
    Caption = 'OnClick = Dispatch'
  end
end
