object fLinUnknown: TfLinUnknown
  Left = 0
  Top = 0
  Caption = 'fLinUnknown'
  ClientHeight = 200
  ClientWidth = 300
  object tblOrders: TFDQuery
    SQL.Strings = (
      'SELECT ID, QTY FROM ORDERS')
    Left = 24
    Top = 24
    object tblOrdersQTY: TFloatField
      FieldName = 'QTY'
    end
    object tblOrdersU1B: TFloatField
      FieldName = 'U1B'
    end
    object tblOrdersU2: TStringField
      FieldName = 'U2'
    end
    object tblOrdersU3: TFloatField
      FieldName = 'U3'
    end
  end
  object qryCust: TFDQuery
    SQL.Strings = (
      'SELECT ID, NAME FROM CUSTOMERS')
    Left = 88
    Top = 24
  end
end
