inherited dmDerived: TdmDerived
  inherited tblOrders: TFDTable
    inherited tblOrdersQTY: TIntegerField
      DisplayLabel = 'Pieces'
    end
    object tblOrdersNOTE: TStringField
      FieldName = 'NOTE'
      OnGetText = tblOrdersNOTEGetText
    end
  end
  inherited qryItems: TFDQuery
    SQL.Strings = (
      'select ID, CODE from PARTS')
  end
  object tblOwn: TFDTable
    TableName = 'OWNED'
    object tblOwnID: TIntegerField
      FieldName = 'ID'
    end
  end
end
