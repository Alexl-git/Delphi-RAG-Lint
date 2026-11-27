object fLinWhere: TfLinWhere
  Left = 0
  Top = 0
  Caption = 'fLinWhere'
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
    object tblOrdersX: TFloatField
      FieldName = 'X'
    end
    object tblOrdersY: TFloatField
      FieldName = 'Y'
    end
  end
end
