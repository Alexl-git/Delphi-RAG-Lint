object ShortcutForm: TShortcutForm
  Left = 0
  object al: TActionList
    object actSave: TAction
      Caption = 'Save'
      ShortCut = 16467
    end
    object actSaveAll: TAction
      Caption = 'Save all'
      ShortCut = 16467
    end
    object actPrint: TAction
      Caption = 'Print'
      ShortCut = 16464
    end
    object actOff: TAction
      Caption = 'Off'
      Enabled = False
      ShortCut = 16467
    end
    object actNone: TAction
      Caption = 'None'
      ShortCut = 0
    end
  end
  object al2: TActionList
    object actOther: TAction
      Caption = 'Other'
      ShortCut = 16467
    end
  end
  object mm: TMainMenu
    object miA: TMenuItem
      Caption = 'A'
      ShortCut = 16462
      object miSub1: TMenuItem
        Caption = 'Sub1'
        ShortCut = 16463
      end
    end
    object miB: TMenuItem
      Caption = 'B'
      ShortCut = 16463
    end
    object miC: TMenuItem
      Action = actSave
      ShortCut = 16467
    end
  end
  object bm: TdxBarManager
    object bbOne: TdxBarButton
      ShortCut = 121
    end
    object bbTwo: TdxBarButton
      ShortCut = 121
    end
    object bbNever: TdxBarButton
      Visible = ivNever
      ShortCut = 121
    end
  end
end
