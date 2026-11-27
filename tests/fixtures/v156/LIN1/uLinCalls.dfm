object fLinCalls: TfLinCalls
  Left = 0
  Top = 0
  Caption = 'fLinCalls'
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
    object tblOrdersRATE2: TFloatField
      FieldName = 'RATE2'
    end
    object tblOrdersR3: TFloatField
      FieldName = 'R3'
    end
    object tblOrdersP4: TFloatField
      FieldName = 'P4'
    end
  end
end
