object fLin2: TfLin2
  Left = 0
  Top = 0
  Caption = 'fLin2'
  ClientHeight = 200
  ClientWidth = 300
  object tblOrders: TFDQuery
    AfterOpen = tblOrdersAfterOpen
    SQL.Strings = (
      'SELECT ID, CUST_ID, QTY, PRICE FROM ORDERS')
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
    object tblOrdersNET: TFloatField
      FieldName = 'NET'
    end
    object tblOrdersSUMQ: TFloatField
      FieldName = 'SUMQ'
    end
    object tblOrdersRATE2: TFloatField
      FieldName = 'RATE2'
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
  object qryLines: TFDQuery
    SQL.Strings = (
      'SELECT ID, ORDER_ID, AMOUNT, QTY FROM ORDER_LINES')
    Left = 152
    Top = 24
    object qryLinesAMOUNT: TFloatField
      FieldName = 'AMOUNT'
    end
    object qryLinesQTY: TIntegerField
      FieldName = 'QTY'
    end
  end
  object qryJoin: TFDQuery
    OnCalcFields = qryJoinCalcFields
    SQL.Strings = (
      'SELECT O.ID, O.QTY, C.DISCOUNT'
      'FROM ORDERS O'
      'JOIN CUSTOMERS C ON C.ID = O.CUST_ID')
    Left = 216
    Top = 24
    object qryJoinQTY: TFloatField
      FieldName = 'QTY'
    end
    object qryJoinDISCOUNT: TFloatField
      FieldName = 'DISCOUNT'
    end
    object qryJoinCALCD: TFloatField
      FieldKind = fkCalculated
      FieldName = 'CALCD'
      Calculated = True
    end
  end
end
