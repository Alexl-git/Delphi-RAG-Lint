object fLinDirect: TfLinDirect
  Left = 0
  Top = 0
  Caption = 'fLinDirect'
  ClientHeight = 200
  ClientWidth = 300
  object tblOrders: TFDQuery
    AfterOpen = tblOrdersAfterOpen
    SQL.Strings = (
      'SELECT ID, QTY, PRICE FROM ORDERS')
    Left = 24
    Top = 24
    object tblOrdersQTY: TFloatField
      FieldName = 'QTY'
    end
    object tblOrdersPRICE: TFloatField
      FieldName = 'PRICE'
    end
    object tblOrdersTOTAL: TFloatField
      FieldName = 'TOTAL'
    end
    object tblOrdersSTAMP: TDateTimeField
      FieldName = 'STAMP'
    end
    object tblOrdersIDLE: TFloatField
      FieldName = 'IDLE'
    end
  end
  object qryCust: TFDQuery
    SQL.Strings = (
      'SELECT ID, NAME, DISCOUNT FROM CUSTOMERS')
    Left = 88
    Top = 24
  end
  object tblM: TFDMemTable
    Left = 152
    Top = 24
    object tblMX: TFloatField
      FieldName = 'X'
    end
  end
  object qryQ: TFDQuery
    SQL.Strings = (
      'SELECT A, B FROM Q')
    Left = 216
    Top = 24
    object qryQA: TFloatField
      FieldName = 'A'
    end
    object qryQB: TFloatField
      FieldName = 'B'
    end
  end
end
