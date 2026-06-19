object IndexesFrame: TIndexesFrame
  Left = 0
  Top = 0
  Width = 880
  Height = 520
  TabOrder = 0
  object splMain: TSplitter
    Left = 180
    Top = 0
    Width = 8
    Height = 340
    Cursor = crHSplit
    Beveled = True
  end
  object pnlLeft: TPanel
    Left = 0
    Top = 0
    Width = 180
    Height = 340
    Align = alLeft
    BevelOuter = bvNone
    TabOrder = 0
    object lbSections: TListBox
      Left = 0
      Top = 0
      Width = 180
      Height = 305
      Align = alClient
      ItemHeight = 13
      TabOrder = 0
      OnClick = lbSectionsClick
    end
    object pnlLeftBtns: TPanel
      Left = 0
      Top = 305
      Width = 180
      Height = 35
      Align = alBottom
      BevelOuter = bvNone
      TabOrder = 1
      object btnAddSection: TButton
        Left = 4
        Top = 6
        Width = 80
        Height = 24
        Caption = 'Add'
        TabOrder = 0
        OnClick = btnAddSectionClick
      end
      object btnDelSection: TButton
        Left = 90
        Top = 6
        Width = 80
        Height = 24
        Caption = 'Delete'
        TabOrder = 1
        OnClick = btnDelSectionClick
      end
    end
  end
  object pnlRight: TPanel
    Left = 186
    Top = 0
    Width = 694
    Height = 340
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 1
    object scrEditor: TScrollBox
      Left = 0
      Top = 0
      Width = 694
      Height = 340
      Align = alClient
      BorderStyle = bsNone
      TabOrder = 0
      object lblName: TLabel
        Left = 8
        Top = 8
        Width = 28
        Height = 13
        Caption = 'Name:'
      end
      object edName: TEdit
        Left = 90
        Top = 5
        Width = 200
        Height = 21
        TabOrder = 0
        OnChange = edNameChange
      end
      object lblDb: TLabel
        Left = 8
        Top = 34
        Width = 15
        Height = 13
        Caption = 'Db:'
      end
      object edDb: TEdit
        Left = 90
        Top = 31
        Width = 300
        Height = 21
        TabOrder = 1
        OnChange = edDbChange
      end
      object lblSource: TLabel
        Left = 8
        Top = 60
        Width = 40
        Height = 13
        Caption = 'Source:'
      end
      object rgSource: TRadioGroup
        Left = 90
        Top = 56
        Width = 280
        Height = 45
        Columns = 2
        Items.Strings = (
          'folders/dproj'
          'registry-libraries')
        TabOrder = 2
        OnClick = rgSourceClick
      end
      object lblPlatforms: TLabel
        Left = 8
        Top = 108
        Width = 49
        Height = 13
        Caption = 'Platforms:'
      end
      object edPlatforms: TEdit
        Left = 90
        Top = 105
        Width = 200
        Height = 21
        TabOrder = 3
        OnChange = edPlatformsChange
      end
      object lblInclude: TLabel
        Left = 8
        Top = 134
        Width = 42
        Height = 13
        Caption = 'Include:'
      end
      object lbInclude: TListBox
        Left = 90
        Top = 131
        Width = 300
        Height = 80
        ItemHeight = 13
        TabOrder = 4
        OnClick = lbIncludeClick
      end
      object pnlIncludeBtns: TPanel
        Left = 396
        Top = 131
        Width = 120
        Height = 80
        BevelOuter = bvNone
        TabOrder = 5
        object btnAddFolder: TButton
          Left = 4
          Top = 4
          Width = 112
          Height = 22
          Caption = '+Folder'
          TabOrder = 0
          OnClick = btnAddFolderClick
        end
        object btnAddDproj: TButton
          Left = 4
          Top = 30
          Width = 112
          Height = 22
          Caption = '+dproj'
          TabOrder = 1
          OnClick = btnAddDprojClick
        end
        object btnRemoveInclude: TButton
          Left = 4
          Top = 56
          Width = 112
          Height = 22
          Caption = 'Remove'
          TabOrder = 2
          OnClick = btnRemoveIncludeClick
        end
      end
      object lblExclude: TLabel
        Left = 8
        Top = 220
        Width = 46
        Height = 13
        Caption = 'Exclude:'
      end
      object edExclude: TEdit
        Left = 90
        Top = 217
        Width = 300
        Height = 21
        TabOrder = 6
        OnChange = edExcludeChange
      end
      object lblIncludeOnly: TLabel
        Left = 8
        Top = 248
        Width = 64
        Height = 13
        Caption = 'IncludeOnly:'
      end
      object edIncludeOnly: TEdit
        Left = 90
        Top = 245
        Width = 300
        Height = 21
        TabOrder = 7
        OnChange = edIncludeOnlyChange
      end
      object lblDedup: TLabel
        Left = 8
        Top = 276
        Width = 75
        Height = 13
        Caption = 'DedupAgainst:'
      end
      object edDedup: TEdit
        Left = 90
        Top = 273
        Width = 300
        Height = 21
        TabOrder = 8
        OnChange = edDedupChange
      end
      object cbUseIgnore: TCheckBox
        Left = 90
        Top = 302
        Width = 140
        Height = 17
        Caption = 'useIgnoreFiles'
        TabOrder = 9
        OnClick = cbUseIgnoreClick
      end
      object cbSqlOnlyMS: TCheckBox
        Left = 240
        Top = 302
        Width = 140
        Height = 17
        Caption = 'sqlOnlyMS'
        TabOrder = 10
        OnClick = cbSqlOnlyMSClick
      end
    end
  end
  object splBottom: TSplitter
    Left = 0
    Top = 340
    Width = 880
    Height = 8
    Cursor = crVSplit
    Align = alBottom
    Beveled = True
    MinSize = 60
  end
  object pcBottom: TPageControl
    Left = 0
    Top = 346
    Width = 880
    Height = 174
    ActivePage = tsCoverage
    Align = alBottom
    TabOrder = 2
    OnChange = pcBottomChange
    object tsCoverage: TTabSheet
      Caption = 'Coverage'
      object pnlCovTop: TPanel
        Left = 0
        Top = 0
        Width = 872
        Height = 30
        Align = alTop
        BevelOuter = bvNone
        TabOrder = 0
        object lblCovRoot: TLabel
          Left = 4
          Top = 8
          Width = 26
          Height = 13
          Caption = 'Root:'
        end
        object edCovRoot: TEdit
          Left = 36
          Top = 4
          Width = 640
          Height = 22
          TabOrder = 0
        end
        object btnCovBrowse: TButton
          Left = 682
          Top = 4
          Width = 80
          Height = 22
          Caption = 'Browse...'
          TabOrder = 1
          OnClick = btnCovBrowseClick
        end
        object btnCovRefresh: TButton
          Left = 768
          Top = 4
          Width = 80
          Height = 22
          Caption = 'Refresh'
          TabOrder = 2
          OnClick = btnCovRefreshClick
        end
      end
      object tvCoverage: TTreeView
        Left = 0
        Top = 30
        Width = 872
        Height = 114
        Align = alClient
        HideSelection = False
        PopupMenu = pmCoverage
        ReadOnly = True
        TabOrder = 1
        OnCustomDrawItem = tvCoverageCustomDrawItem
        OnExpanding = tvCoverageExpanding
      end
      object pmCoverage: TPopupMenu
        OnPopup = pmCoveragePopup
        Left = 16
        Top = 46
      end
    end
    object tsPlanPreview: TTabSheet
      Caption = 'Plan preview'
      object pnlPlanTop: TPanel
        Left = 0
        Top = 0
        Width = 872
        Height = 31
        Align = alTop
        BevelOuter = bvNone
        TabOrder = 0
        object btnRefreshPlan: TButton
          Left = 4
          Top = 4
          Width = 90
          Height = 23
          Caption = 'Refresh'
          TabOrder = 0
          OnClick = btnRefreshPlanClick
        end
      end
      object lvPlan: TListView
        Left = 0
        Top = 31
        Width = 872
        Height = 113
        Align = alClient
        Columns = <
          item
            Caption = 'Section'
            Width = 140
          end
          item
            Caption = 'Mode'
            Width = 80
          end
          item
            Caption = 'Db'
            Width = 240
          end
          item
            Caption = 'Platform'
            Width = 70
          end
          item
            Caption = 'Roots'
            Width = 50
          end
          item
            Caption = 'Dedup'
            Width = 50
          end>
        ReadOnly = True
        RowSelect = True
        TabOrder = 1
        ViewStyle = vsReport
      end
    end
    object tsBuildLog: TTabSheet
      Caption = 'Build log'
      object pnlBuildBtns: TPanel
        Left = 0
        Top = 0
        Width = 872
        Height = 30
        Align = alTop
        BevelOuter = bvNone
        TabOrder = 0
        object btnBuildAll: TButton
          Left = 4
          Top = 4
          Width = 90
          Height = 22
          Caption = 'Build All'
          TabOrder = 0
          OnClick = btnBuildAllClick
        end
        object btnBuildSelected: TButton
          Left = 100
          Top = 4
          Width = 110
          Height = 22
          Caption = 'Build Selected'
          TabOrder = 1
          OnClick = btnBuildSelectedClick
        end
        object btnDrift: TButton
          Left = 216
          Top = 4
          Width = 100
          Height = 22
          Caption = 'Library Drift'
          TabOrder = 2
          OnClick = btnDriftClick
        end
      end
      object mLog: TMemo
        Left = 0
        Top = 30
        Width = 872
        Height = 114
        Align = alClient
        ReadOnly = True
        ScrollBars = ssBoth
        TabOrder = 1
        WordWrap = False
      end
    end
  end
end
