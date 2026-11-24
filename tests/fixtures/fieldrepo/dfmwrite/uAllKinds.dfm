object frmAllKinds: TfrmAllKinds
  Left = 0
  Top = 0
  Hint = 
    'A hint that is long enough for the IDE to write it on two lines,' +
    ' with an '#39'end'#39' in it'
  Caption = 'All field kinds'
  ClientHeight = 300
  ClientWidth = 500
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = [fsBold, fsItalic]
  TextHeight = 13
  object Grid: TcxGrid
    Left = 0
    Top = 0
    Width = 250
    Height = 300
    TabOrder = 0
    object GridView: TcxGridDBTableView
      DataController.DataSource = dsOrders
      DataController.Summary.DefaultGroupSummaryItems = <>
      DataController.Summary.FooterSummaryItems = <
        item
          Kind = skSum
          FieldName = 'QTY'
          Column = GridViewQTY
        end>
      DataController.Summary.SummaryGroups = <>
      object GridViewQTY: TcxGridDBColumn
        DataBinding.FieldName = 'QTY'
      end
      object GridViewSTATUS: TcxGridDBColumn
        Caption = 'Status'
        Width = 40
      end
    end
    object GridLevel: TcxGridLevel
      GridView = GridView
    end
  end
  object Tree: TcxDBTreeList
    Left = 256
    Top = 0
    Width = 240
    Height = 300
    Bands = <
      item
      end>
    DataController.DataSource = dsOrders
    DataController.ParentField = 'TOOLID'
    DataController.KeyField = 'ID'
    RootValue = -1
    TabOrder = 1
    object TreeNOTE: TcxDBTreeListColumn
      DataBinding.FieldName = 'NOTE'
      Position.ColIndex = 0
      Position.RowIndex = 0
      Position.BandIndex = 0
    end
    object TreeSTATUS: TcxDBTreeListColumn
      Caption.Text = 'Status'
      Position.ColIndex = 1
      Position.RowIndex = 0
      Position.BandIndex = 0
    end
  end
  object dsOrders: TDataSource
    DataSet = memOrders
    Left = 40
    Top = 200
  end
  object memOrders: TFDMemTable
    AggregatesActive = True
    UpdateOptions.UpdateTableName = 'ORDERS'
    Left = 40
    Top = 240
    object memOrdersID: TIntegerField
      FieldName = 'ID'
    end
    object memOrdersQTY: TIntegerField
      Alignment = taCenter
      DisplayLabel = 'Qty'
      FieldName = 'QTY'
      Visible = False
      DisplayFormat = '0'
    end
    object memOrdersNOTE: TStringField
      FieldName = 'NOTE'
      Size = 40
    end
    object memOrdersOLDCOL: TIntegerField
      FieldName = 'OLDCOL'
    end
    object memOrdersUSEDCOL: TIntegerField
      FieldName = 'USEDCOL'
    end
  end
  object memTools: TFDMemTable
    UpdateOptions.UpdateTableName = 'TOOLS'
    Left = 120
    Top = 240
    object memToolsID: TIntegerField
      FieldName = 'ID'
    end
    object memToolsNAME: TStringField
      FieldName = 'NAME'
      Size = 30
    end
  end
  object Image: TImage
    Left = 160
    Top = 200
    Width = 8
    Height = 8
    Picture.Data = {
      07544269746D617042000000424D420000000000000036000000280000000100
      00000300000001001800000000000C0000000000000000000000000000000000
      0000FFFFFF00FFFFFF00FFFFFF00}
  end
end
