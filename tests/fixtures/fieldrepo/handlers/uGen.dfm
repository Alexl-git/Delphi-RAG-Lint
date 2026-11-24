object dmGen: TdmGen
  Height = 150
  Width = 215
  object memOrders: TFDMemTable
    OnCalcFields = memOrdersCalcFields
    UpdateOptions.UpdateTableName = 'ORDERS'
    Left = 40
    Top = 24
    object memOrdersID: TIntegerField
      FieldName = 'ID'
      OnGetText = SharedGetText
    end
    object memOrdersQTY: TIntegerField
      FieldName = 'QTY'
      OnChange = memOrdersQTYChange
      OnValidate = memOrdersQTYValidate
    end
    object memOrdersPRICE: TFloatField
      FieldName = 'PRICE'
      OnGetText = SharedGetText
    end
    object memOrdersNOTE: TStringField
      FieldName = 'NOTE'
      OnGetText = memOrdersNOTEGetText
      OnSetText = memOrdersNOTESetText
      Size = 40
    end
    object memOrdersVAT: TFloatField
      FieldKind = fkCalculated
      FieldName = 'VAT'
      Calculated = True
    end
    object memOrdersTOTAL: TFloatField
      FieldKind = fkCalculated
      FieldName = 'TOTAL'
      Calculated = True
    end
    object memOrdersHANDY: TIntegerField
      FieldKind = fkCalculated
      FieldName = 'HANDY'
      Calculated = True
    end
  end
end
