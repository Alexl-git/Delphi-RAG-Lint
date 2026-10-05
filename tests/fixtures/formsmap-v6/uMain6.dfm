object frmMain6: TfrmMain6
  Left = 0
  Top = 0
  Caption = 'Demo Six'
  ClientHeight = 300
  ClientWidth = 400
  Menu = mnuMain
  OnCreate = FormCreate
  object pgcMain: TPageControl
    Left = 0
    Top = 0
    Width = 400
    Height = 300
    ActivePage = tsData
    object tsData: TTabSheet
      Caption = '&Data'
      object btnEditItem: TButton
        Left = 8
        Top = 8
        Width = 75
        Height = 25
        Caption = '&Edit Item'
        OnClick = btnEditItemClick
      end
    end
    object tsReports: TTabSheet
      Caption = 'Reports'
      object btnRunReports: TButton
        Left = 8
        Top = 8
        Width = 75
        Height = 25
        Action = actReports
      end
    end
  end
  object mnuMain: TMainMenu
    Left = 300
    Top = 8
    object mnuSetup: TMenuItem
      Caption = '&Setup'
      object mnuGroups: TMenuItem
        Caption = '&Groups'
        object mnuAssignGroups: TMenuItem
          Caption = 'Assign &Groups'
          OnClick = mnuAssignGroupsClick
        end
      end
    end
    object mnuEdit: TMenuItem
      Caption = 'E&dit'
      object mnuEditItem: TMenuItem
        Caption = 'Edit &Item'
        OnClick = btnEditItemClick
      end
    end
  end
  object alMain: TActionList
    Left = 300
    Top = 60
    object actReports: TAction
      Caption = 'Run &Reports'
      OnExecute = actReportsExecute
    end
  end
  object tmrNag: TTimer
    Left = 300
    Top = 120
  end
end