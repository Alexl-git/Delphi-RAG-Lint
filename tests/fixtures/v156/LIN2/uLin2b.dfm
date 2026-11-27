object fLin2b: TfLin2b
  Left = 0
  Top = 0
  Caption = 'fLin2b'
  ClientHeight = 200
  ClientWidth = 300
  object tblOrders: TFDQuery
    SQL.Strings = (
      'SELECT ID, CUST_ID, QTY, PRICE FROM ORDERS')
    Left = 24
    Top = 24
    object tblOrdersQTY: TFloatField
      FieldName = 'QTY'
    end
    object tblOrdersREBATE: TFloatField
      FieldName = 'REBATE'
    end
  end
  object qryCust: TFDQuery
    SQL.Strings = (
      'SELECT ID, NAME, DISCOUNT FROM CUSTOMERS')
    Left = 88
    Top = 24
    object qryCustDISCOUNT: TFloatField
      FieldName = 'DISCOUNT'
    end
  end
end
