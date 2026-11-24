object dmMain: TdmMain
  Height = 480
  Width = 640
  object qryOrders: TFDQuery
    SQL.Strings = (
      'SELECT O.*, '
      '  COUNT(*) AS CNT'
      'FROM ORDERS O')
    Left = 16
    Top = 16
    object qryOrdersID: TLargeintField
      FieldName = 'ID'
    end
    object qryOrdersGONE: TStringField
      FieldName = 'GONE'
      Size = 20
    end
    object qryOrdersCALC: TStringField
      FieldKind = fkCalculated
      FieldName = 'CALC'
      Calculated = True
    end
    object qryOrdersLOOK: TStringField
      FieldKind = fkLookup
      FieldName = 'LOOK'
      Lookup = True
    end
    object qryOrdersCNT: TIntegerField
      FieldName = 'CNT'
    end
    object qryOrdersCREATED: TIntegerField
      FieldName = 'CREATED'
    end
    object qryOrdersNOTE: TStringField
      FieldName = 'NOTE'
      Size = 20
    end
  end
  object tblOrders: TFDTable
    TableName = 'ORDERS'
    Left = 64
    Top = 16
    object tblOrdersNOTE: TStringField
      FieldName = 'NOTE'
      Size = 20
    end
    object tblOrdersQTY: TStringField
      FieldName = 'QTY'
      Size = 20
    end
    object tblOrdersLOST: TStringField
      FieldName = 'LOST'
      Size = 20
    end
  end
  object qryJoin: TFDQuery
    SQL.Strings = (
      'SELECT * FROM ORDERS O, CUSTOMER C')
    object qryJoinWHAT: TStringField
      FieldName = 'WHAT'
    end
  end
  object qryLive: TFDQuery
    SQL.Strings = (
      'SELECT * FROM ORDERS')
    object qryLiveNOTE: TStringField
      FieldName = 'NOTE'
      Size = 20
    end
    object qryLiveLIVEX: TStringField
      FieldName = 'LIVEX'
    end
  end
  object tblLive: TFDTable
    TableName = 'ORDERS'
    object tblLiveLIVEX: TStringField
      FieldName = 'LIVEX'
    end
  end
  object qryOwn: TFDQuery
    SQL.Strings = (
      'SELECT * FROM ORDERS')
    object qryOwnLIVEX: TStringField
      FieldName = 'LIVEX'
    end
  end
  object qryOther: TFDQuery
    SQL.Strings = (
      'SELECT * FROM UNREAD')
    object qryOtherANY: TStringField
      FieldName = 'ANY'
    end
  end
  object bdeTable: TTable
    DatabaseName = 'OLD'
    TableName = 'ORDERS'
    object bdeTablePDX: TIntegerField
      FieldName = 'PDX'
    end
    object bdeTableNOTE: TIntegerField
      FieldName = 'NOTE'
    end
  end
  object bdeQuery: TQuery
    SQL.Strings = (
      'SELECT PDX FROM ORDERS')
  end
  object qryIns: TFDQuery
    SQL.Strings = (
      'INSERT INTO ORDERS (NOTE, CODE)'
      'VALUES (:NOTE, :CODE)')
  end
  object qryMacro: TFDQuery
    SQL.Strings = (
      'SELECT CUSTNAME'
      'FROM ORDERS &JOINS')
    object qryMacroCUSTNAME: TStringField
      FieldName = 'CUSTNAME'
      Size = 20
    end
  end
  object qryBad: TFDQuery
    SQL.Strings = (
      'SELECT ID,'
      '  NOCOL'
      'FROM ORDERS')
  end
end