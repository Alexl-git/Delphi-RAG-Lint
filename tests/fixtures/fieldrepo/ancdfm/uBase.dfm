object dmBase: TdmBase
  object tblOrders: TFDTable
    TableName = 'ORDERS'
    object tblOrdersID: TIntegerField
      FieldName = 'ID'
    end
    object tblOrdersQTY: TIntegerField
      FieldName = 'QTY'
    end
  end
  object tblCust: TFDTable
    TableName = 'CUSTOMERS'
    object tblCustID: TIntegerField
      FieldName = 'ID'
    end
    object tblCustNAME: TStringField
      FieldName = 'NAME'
    end
  end
  object qryItems: TFDQuery
    SQL.Strings = (
      'select ID, CODE from ITEMS')
    object qryItemsID: TIntegerField
      FieldName = 'ID'
    end
    object qryItemsCODE: TStringField
      FieldName = 'CODE'
    end
  end
end
