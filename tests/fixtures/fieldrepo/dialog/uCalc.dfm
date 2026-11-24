object frmCalc: TfrmCalc
  object qryOrders: TFDQuery
    OnCalcFields = qryOrdersCalcFields
    SQL.Strings = (
      'SELECT * FROM ORDERS')
    object qryOrdersID: TIntegerField
      FieldName = 'ID'
    end
    object qryOrdersQTY: TIntegerField
      FieldName = 'QTY'
    end
    object qryOrdersPRICE: TFloatField
      FieldName = 'PRICE'
    end
    object qryOrdersTOTAL: TFloatField
      FieldKind = fkCalculated
      FieldName = 'TOTAL'
      Calculated = True
    end
  end
end