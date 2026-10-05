object frmGroups6: TfrmGroups6
  Left = 0
  Top = 0
  Caption = 'Groups'
  ClientHeight = 200
  ClientWidth = 300
  object btnEditGroup: TButton
    Left = 8
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Edit Group'
    OnClick = btnEditGroupClick
  end
  object lbGroups: TListBox
    Left = 8
    Top = 40
    Width = 200
    Height = 100
    OnDblClick = lbGroupsDblClick
  end
  object alGroups: TActionList
    Left = 240
    Top = 8
    object actOpenLog: TAction
      Caption = 'Open Log'
      OnExecute = actOpenLogExecute
    end
  end
end