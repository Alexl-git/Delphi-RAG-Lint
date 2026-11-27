object fLinLoop: TfLinLoop
  Left = 0
  Top = 0
  Caption = 'fLinLoop'
  ClientHeight = 200
  ClientWidth = 300
  object tblOrders: TFDQuery
    AfterOpen = tblOrdersAfterOpen
    SQL.Strings = (
      'SELECT ID, QTY FROM ORDERS')
    Left = 24
    Top = 24
    object tblOrdersQTY: TFloatField
      FieldName = 'QTY'
    end
    object tblOrdersTOTAL: TFloatField
      FieldName = 'TOTAL'
    end
    object tblOrdersCOUNT2: TIntegerField
      FieldName = 'COUNT2'
    end
    object tblOrdersSEQ: TFloatField
      FieldName = 'SEQ'
    end
  end
  object qryLines: TFDQuery
    SQL.Strings = (
      'SELECT ORDER_ID, AMOUNT, QTY FROM ORDER_LINES')
    Left = 88
    Top = 24
    object qryLinesAMOUNT: TFloatField
      FieldName = 'AMOUNT'
    end
    object qryLinesQTY: TIntegerField
      FieldName = 'QTY'
    end
  end
end
