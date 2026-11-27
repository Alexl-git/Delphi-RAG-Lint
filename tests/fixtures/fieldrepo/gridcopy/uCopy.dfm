object frmCopy: TfrmCopy
  Left = 0
  Top = 0
  Caption = 'Grid copy'
  ClientHeight = 300
  ClientWidth = 500
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  TextHeight = 15
  object cxGrid1: TcxGrid
    Left = 0
    Top = 0
    Width = 500
    Height = 300
    Align = alClient
    TabOrder = 0
    object tvMain: TcxGridDBTableView
      OnCellDblClick = tvMainCellDblClick
      OnCustomDrawCell = tvMainCustomDrawCell
      DataController.DataSource = dsMain
      DataController.Summary.DefaultGroupSummaryItems = <>
      DataController.Summary.FooterSummaryItems = <>
      DataController.Summary.SummaryGroups = <>
      DataController.OnCompare = tvMainDataControllerCompare
      OnColumnHeaderClick = tvMainColumnHeaderClick
      OnCustomization = tvMainCustomization
      Styles.OnGetContentStyle = tvMainStylesGetContentStyle
      object tvMainCODE: TcxGridDBColumn
        Caption = 'Code'
        DataBinding.FieldName = 'CODE'
        PropertiesClassName = 'TcxComboBoxProperties'
        Properties.Items.Strings = (
          'A'
          'B')
        Properties.OnChange = tvMainCODEPropertiesChange
        OnGetDisplayText = tvMainCODEGetDisplayText
        Width = 80
      end
      object tvMainNAME: TcxGridDBColumn
        DataBinding.FieldName = 'NAME'
        OnGetDisplayText = tvMainNAMEGetDisplayText
        OnHeaderClick = tvMainNAMEHeaderClick
        Width = 200
      end
      object tvMainQTY: TcxGridDBColumn
        Caption = 'Quantity'
        DataBinding.FieldName = 'QTY'
        OnCustomDrawCell = tvMainQTYCustomDrawCell
        OnGetDisplayText = tvMainCODEGetDisplayText
      end
    end
    object bvMain: TcxGridDBBandedTableView
      OnCellDblClick = tvMainCellDblClick
      DataController.DataSource = dsMain
      DataController.Summary.DefaultGroupSummaryItems = <>
      DataController.Summary.FooterSummaryItems = <>
      DataController.Summary.SummaryGroups = <>
      object bvMainNAME: TcxGridDBBandedColumn
        DataBinding.FieldName = 'Name'
        OnGetDisplayText = bvMainNAMEGetDisplayText
        Position.BandIndex = -1
        Position.ColIndex = -1
        Position.RowIndex = -1
      end
    end
    object cvMain: TcxGridDBCardView
      DataController.DataSource = dsMain
      DataController.Summary.DefaultGroupSummaryItems = <>
      DataController.Summary.FooterSummaryItems = <>
      DataController.Summary.SummaryGroups = <>
    end
    object cxGrid1Level1: TcxGridLevel
      GridView = tvMain
    end
  end
  object memMain: TFDMemTable
    FieldDefs = <>
    Left = 40
    Top = 200
    object memMainCODE: TStringField
      FieldName = 'CODE'
      Size = 4
    end
    object memMainNAME: TStringField
      FieldName = 'NAME'
      Size = 40
    end
    object memMainQTY: TIntegerField
      FieldName = 'QTY'
    end
  end
  object dsMain: TDataSource
    DataSet = memMain
    Left = 100
    Top = 200
  end
end
