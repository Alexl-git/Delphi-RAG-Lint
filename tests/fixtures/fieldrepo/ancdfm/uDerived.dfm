inherited dmDerived: TdmDerived
  inherited tblOrders: TFDTable
    inherited tblOrdersQTY: TIntegerField
      DisplayLabel = 'Pieces'
    end
    object tblOrdersNOTE: TStringField
      FieldName = 'NOTE'
    end
  end
  inherited qryItems: TFDQuery
    SQL.Strings = (
      'select ID, CODE from PARTS')
  end
end
