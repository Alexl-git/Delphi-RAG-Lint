object SettingsFrame: TSettingsFrame
  Left = 0
  Top = 0
  Width = 600
  Height = 400
  TabOrder = 0
  object lblProjectsIndexing: TLabel
    Left = 16
    Top = 20
    Width = 96
    Height = 13
    Caption = 'Projects indexing:'
  end
  object cbProjectsIndexing: TComboBox
    Left = 160
    Top = 17
    Width = 160
    Height = 21
    Style = csDropDown
    TabOrder = 0
    OnChange = cbProjectsIndexingChange
  end
  object lblDefaultPlatform: TLabel
    Left = 16
    Top = 52
    Width = 84
    Height = 13
    Caption = 'Default platform:'
  end
  object cbDefaultPlatform: TComboBox
    Left = 160
    Top = 49
    Width = 160
    Height = 21
    Style = csDropDown
    TabOrder = 1
  end
  object lblSizeGuardMB: TLabel
    Left = 16
    Top = 84
    Width = 72
    Height = 13
    Caption = 'SizeGuard (MB):'
  end
  object edSizeGuardMB: TEdit
    Left = 160
    Top = 81
    Width = 80
    Height = 21
    TabOrder = 2
    Text = '1500'
  end
  object lblMaxJobs: TLabel
    Left = 16
    Top = 116
    Width = 53
    Height = 13
    Caption = 'Max jobs:'
  end
  object edMaxJobs: TEdit
    Left = 160
    Top = 113
    Width = 80
    Height = 21
    TabOrder = 3
    Text = '0'
  end
  object lblMaxParseFileKB: TLabel
    Left = 16
    Top = 148
    Width = 88
    Height = 13
    Caption = 'MaxParseFile (KB):'
  end
  object edMaxParseFileKB: TEdit
    Left = 160
    Top = 145
    Width = 80
    Height = 21
    TabOrder = 4
    Text = '2048'
  end
  object lblEnginePath: TLabel
    Left = 16
    Top = 180
    Width = 66
    Height = 13
    Caption = 'Engine path:'
  end
  object edEnginePath: TEdit
    Left = 160
    Top = 177
    Width = 300
    Height = 21
    TabOrder = 5
    Text = 'auto'
  end
  object btnBrowseEngine: TButton
    Left = 466
    Top = 177
    Width = 60
    Height = 21
    Caption = 'Browse...'
    TabOrder = 6
    OnClick = btnBrowseEngineClick
  end
end
