object frmJoin: TfrmJoin
  Left = 0
  Top = 0
  Caption = 'Join'
  object qryJ: TFDQuery
    OnCalcFields = qryJCalcFields
    SQL.Strings = (
      'SELECT O.ID, O.Qty AS OQ, T.Name, "Tools.DB".Price, O.ToolID,'
      '  (O.Qty * 2) AS Dbl, T.ID AS TNo, Part'
      'FROM "Orders.DB" O'
      'JOIN "Tools.DB" T ON T.ID = O.ToolID')
    object qryJID: TIntegerField
      FieldName = 'ID'
    end
    object qryJOQ: TIntegerField
      FieldName = 'OQ'
      OnGetText = qryJOQGetText
    end
    object qryJName: TStringField
      FieldName = 'Name'
      OnGetText = qryJNameGetText
      Size = 20
    end
    object qryJPrice: TFloatField
      FieldName = 'Price'
    end
    object qryJToolID: TIntegerField
      FieldName = 'ToolID'
    end
    object qryJDbl: TIntegerField
      FieldName = 'Dbl'
    end
    object qryJTNo: TIntegerField
      FieldName = 'TNo'
      Origin = '"Orders.DB".ID'
    end
    object qryJPart: TStringField
      FieldName = 'Part'
      Size = 10
    end
    object qryJTwice: TFloatField
      FieldKind = fkCalculated
      FieldName = 'Twice'
      Calculated = True
    end
    object qryJTotal: TFloatField
      FieldKind = fkCalculated
      FieldName = 'Total'
      Calculated = True
    end
    object qryJLabel: TStringField
      FieldKind = fkCalculated
      FieldName = 'Label'
      Size = 40
      Calculated = True
    end
    object qryJMixed: TStringField
      FieldKind = fkCalculated
      FieldName = 'Mixed'
      Size = 40
      Calculated = True
    end
    object qryJComp: TIntegerField
      FieldKind = fkCalculated
      FieldName = 'Comp'
      Calculated = True
    end
    object qryJNoCode: TIntegerField
      FieldKind = fkCalculated
      FieldName = 'NoCode'
      Calculated = True
    end
    object qryJConst: TIntegerField
      FieldKind = fkCalculated
      FieldName = 'Const'
      Calculated = True
    end
    object qryJLoop1: TIntegerField
      FieldKind = fkCalculated
      FieldName = 'Loop1'
      Calculated = True
    end
    object qryJLoop2: TIntegerField
      FieldKind = fkCalculated
      FieldName = 'Loop2'
      Calculated = True
    end
    object qryJCyc1: TIntegerField
      FieldKind = fkCalculated
      FieldName = 'Cyc1'
      Calculated = True
    end
    object qryJCyc2: TIntegerField
      FieldKind = fkCalculated
      FieldName = 'Cyc2'
      Calculated = True
    end
    object qryJSlice: TIntegerField
      FieldKind = fkCalculated
      FieldName = 'Slice'
      Calculated = True
    end
    object qryJOther: TIntegerField
      FieldKind = fkCalculated
      FieldName = 'Other'
      Calculated = True
    end
    object qryJToolTxt: TStringField
      FieldKind = fkLookup
      FieldName = 'ToolTxt'
      LookupDataSet = tblTools
      LookupKeyFields = 'ID'
      LookupResultField = 'Name'
      KeyFields = 'ToolID'
      Size = 20
      Lookup = True
    end
    object qryJBoth: TStringField
      FieldKind = fkLookup
      FieldName = 'Both'
      LookupDataSet = tblTools
      LookupKeyFields = 'ID;Name'
      LookupResultField = 'Name'
      KeyFields = 'ToolID;Name'
      Size = 20
      Lookup = True
    end
  end
  object qryStar: TQuery
    SQL.Strings = (
      'SELECT * FROM "Orders.DB" O, "Tools.DB" T')
    object qryStarQty: TIntegerField
      FieldName = 'Qty'
      Origin = '"Orders.DB".Qty'
    end
    object qryStarName: TStringField
      FieldName = 'Name'
      Origin = 'T."Tools.DB".Name'
      Size = 20
    end
    object qryStarNote: TStringField
      FieldName = 'Note'
      Origin = 'Orders.DB.Note'
      Size = 80
    end
    object qryStarCode: TStringField
      FieldName = 'Code'
      Origin = 'Code'
      Size = 10
    end
    object qryStarID: TIntegerField
      FieldName = 'ID'
    end
    object qryStarPart: TStringField
      FieldName = 'Part'
      Size = 10
    end
  end
  object qryOne: TQuery
    SQL.Strings = (
      'SELECT T.ID, T.Name FROM "Tools.DB" T')
    object qryOneName: TStringField
      FieldName = 'Name'
      Origin = '"Tools.DB".Title'
      Size = 20
    end
  end
  object qryDup: TQuery
    SQL.Strings = (
      'SELECT O.ID, T.ID FROM "Orders.DB" O, "Tools.DB" T')
    object qryDupID: TIntegerField
      FieldName = 'ID'
    end
    object qryDupID_1: TIntegerField
      FieldName = 'ID_1'
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
end
