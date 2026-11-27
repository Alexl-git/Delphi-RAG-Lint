object fDer: TfDer
  object tblOrders: TFDTable
    TableName = 'ORDERS'
    object tblOrdersQTY: TFloatField
      FieldName = 'QTY'
    end
    object tblOrdersPRICE: TFloatField
      FieldName = 'PRICE'
    end
    object tblOrdersTOTAL: TFloatField
      DisplayLabel = 'Sum'
      FieldName = 'TOTAL'
    end
  end
end
