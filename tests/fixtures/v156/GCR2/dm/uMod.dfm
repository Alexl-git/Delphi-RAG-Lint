object dmMod: TdmMod
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
end
