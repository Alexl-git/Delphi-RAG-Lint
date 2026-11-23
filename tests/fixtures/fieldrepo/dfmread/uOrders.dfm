object frmOrders: TfrmOrders
  Left = 0
  Top = 0
  Caption = 'Orders'
  object tblOrders: TTable
    OnCalcFields = tblOrdersCalcFields
    DatabaseName = 'MIC'
    TableName = 'Orders.DB'
    object tblOrdersID: TAutoIncField
      FieldName = 'ID'
      ReadOnly = True
    end
    object tblOrdersQTY: TIntegerField
      DisplayLabel = 'Qty'
      FieldName = 'Qty'
      DisplayFormat = '#,##0'
      Alignment = taCenter
      OnGetText = tblOrdersQTYGetText
      OnValidate = tblOrdersQTYValidate
    end
    object tblOrdersPRICE: TFloatField
      FieldName = 'Price'
      DisplayFormat = '0.00'
      Visible = False
    end
    object tblOrdersTOOLID: TIntegerField
      FieldName = 'ToolID'
    end
    object tblOrdersNOTE: TStringField
      DisplayLabel = 'It''s '#233' a note'
      DisplayWidth = 40
      FieldName = 'Note'
      DisplayFormat = 'a display format that is too long'
      Size = 80
    end
    object tblOrdersTOTAL: TFloatField
      FieldKind = fkCalculated
      FieldName = 'Total'
      Calculated = True
    end
    object tblOrdersBIG: TStringField
      FieldKind = fkInternalCalc
      FieldName = 'Big'
      Size = 3
    end
    object tblOrdersLATE: TBooleanField
      FieldKind = fkCalculated
      FieldName = 'Late'
      Calculated = True
    end
    object tblOrdersORPHAN: TBooleanField
      FieldKind = fkCalculated
      FieldName = 'Orphan'
      Calculated = True
    end
    object tblOrdersTOOL: TStringField
      FieldKind = fkLookup
      FieldName = 'Tool'
      LookupDataSet = tblTools
      LookupKeyFields = 'ID'
      LookupResultField = 'Name'
      KeyFields = 'ToolID'
      Size = 20
      Lookup = True
    end
    object tblOrdersREASON: TStringField
      FieldKind = fkLookup
      FieldName = 'Reason'
      LookupDataSet = dmOther.tblReason
      LookupKeyFields = 'Code'
      LookupResultField = 'Text'
      KeyFields = 'ToolID'
      Size = 20
      Lookup = True
    end
    object tblOrdersGONE: TStringField
      FieldKind = fkLookup
      FieldName = 'Gone'
      LookupDataSet = dmNowhere.tblX
      LookupKeyFields = 'A;B'
      LookupResultField = 'Text'
      KeyFields = 'A;B'
      Size = 20
      Lookup = True
    end
    object tblOrdersSUMQ: TAggregateField
      FieldName = 'SumQ'
      Expression = 'SUM(Qty)'
    end
  end
  object tblTools: TTable
    TableName = 'Tools.DB'
    object tblToolsID: TIntegerField
      FieldName = 'ID'
    end
    object tblToolsName: TStringField
      FieldName = 'Name'
      Size = 20
    end
  end
  object qryTools2: TFDQuery
    SQL.Strings = (
      'SELECT T.ID, T.Name, COUNT(*) AS Cnt'
      'FROM Tools T')
    object qryTools2ID: TIntegerField
      FieldName = 'ID'
      DisplayLabel = 'Tool no'
    end
    object qryTools2Name: TStringField
      DisplayLabel = 'Tool name'
      FieldName = 'Name'
      Size = 20
    end
    object qryTools2Cnt: TIntegerField
      FieldName = 'Cnt'
    end
  end
  object qryTools3: TQuery
    SQL.Strings = (
      'SELECT * FROM "Tools.DB"')
    object qryTools3Name: TStringField
      DisplayLabel = 'Other name'
      FieldName = 'Name'
      Size = 20
    end
  end
  object qryJoin: TQuery
    SQL.Strings = (
      'SELECT O.Qty, T.Name'
      'FROM "Orders.DB" O, "Tools.DB" T')
    object qryJoinQty: TIntegerField
      FieldName = 'Qty'
    end
    object qryJoinCalc: TIntegerField
      FieldKind = fkCalculated
      FieldName = 'Calc'
    end
  end
  object memX: TFDMemTable
    object memXA: TIntegerField
      FieldName = 'A'
    end
  end
end
