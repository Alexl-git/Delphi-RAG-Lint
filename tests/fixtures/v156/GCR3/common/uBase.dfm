object dmBase: TdmBase
  object tblOrders: TFDTable
    TableName = 'ORDERS'
    OnCalcFields = tblOrdersCalcFields
    object tblOrdersID: TIntegerField
      FieldName = 'ID'
    end
    object tblOrdersQTY: TIntegerField
      FieldName = 'QTY'
      OnGetText = tblOrdersQTYGetText
    end
    object tblOrdersPRICE: TFloatField
      FieldName = 'PRICE'
    end
    object tblOrdersTOTAL: TFloatField
      FieldKind = fkCalculated
      FieldName = 'TOTAL'
      Calculated = True
    end
  end
  object tblCust: TFDTable
    TableName = 'CUSTOMERS'
    object tblCustID: TIntegerField
      FieldName = 'ID'
    end
  end
  object memCopy: TFDMemTable
    object memCopyID: TIntegerField
      FieldName = 'ID'
    end
  end
end
