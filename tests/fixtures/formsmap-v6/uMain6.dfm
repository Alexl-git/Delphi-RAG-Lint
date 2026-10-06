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
    object tsMore: TTabSheet
      Caption = 'More'
      object btnImport: TButton
        Caption = 'Import'
        OnClick = btnImportClick
      end
      object btnMdi: TButton
        Caption = 'Open MDI'
        OnClick = btnMdiClick
      end
      object btnPanel: TButton
        Caption = 'Open Panel'
        OnClick = btnPanelClick
      end
      object btnSerial: TButton
        Caption = 'Serials'
        OnClick = btnSerialClick
      end
      object btnCache: TButton
        Caption = 'Cache'
        OnClick = btnCacheClick
      end
      object btnArchive: TButton
        Caption = 'Archive'
        OnClick = btnArchiveClick
      end
      object btnAfter: TButton
        Caption = 'After'
        OnClick = btnAfterClick
      end
      object btnBoth: TButton
        Caption = 'Both'
        OnClick = btnBothClick
      end
      object btnWith: TButton
        Caption = 'With'
        OnClick = btnWithClick
      end
      object btnSelf: TButton
        Caption = 'Self'
        OnClick = btnSelfClick
      end
      object btnWithOk: TButton
        Caption = 'With OK'
        OnClick = btnWithOkClick
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