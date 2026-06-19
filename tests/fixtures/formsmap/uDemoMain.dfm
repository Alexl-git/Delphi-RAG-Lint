object frmMain: TfrmMain
  Left = 0
  Top = 0
  Caption = 'Main'
  ClientHeight = 200
  ClientWidth = 300
  object btnLists: TButton
    Left = 8
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Lists'
    OnClick = btnListsClick
  end
  object ActionList1: TActionList
    object actReports: TAction
      Caption = 'Reports'
      OnExecute = actReportsExecute
    end
  end
  object btnReports: TButton
    Left = 90
    Top = 8
    Width = 75
    Height = 25
    Action = actReports
  end
end
