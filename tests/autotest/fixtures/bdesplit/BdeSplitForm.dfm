object FrmBdeSplit: TFrmBdeSplit
  Left = 0
  Top = 0
  Caption = 'FrmBdeSplit'
  ClientHeight = 300
  ClientWidth = 400
  object Session1: TSession
    Active = True
    AutoSessionName = True
    SQLHourGlass = True
    SessionName = 'Session1_1'
    Left = 8
    Top = 8
  end
  object Database1: TDatabase
    DatabaseName = 'DBDEMOS'
    HandleShared = True
    KeepConnection = False
    SessionName = 'Session1_1'
    TransIsolation = tiReadCommitted
    Left = 48
    Top = 8
  end
  object Table1: TTable
    DatabaseName = 'DBDEMOS'
    IndexName = 'ByCompany'
    TableName = 'customer.db'
    UpdateObject = UpdateSQL1
    Left = 88
    Top = 8
    object Table1CustNo: TAutoIncField
      FieldName = 'CustNo'
      Origin = 'DBDEMOS.customer.CustNo'
    end
    object Table1Company: TStringField
      FieldName = 'Company'
      Origin = 'DBDEMOS.customer.Company'
      Size = 30
    end
  end
  object Query1: TQuery
    DatabaseName = 'DBDEMOS'
    UpdateObject = UpdateSQL1
    OnUpdateRecord = Query1UpdateRecord
    SQL.Strings = (
      'select * from customer where CustNo > :MinNo and Company = :Co')
    Left = 128
    Top = 8
    ParamData = <
      item
        DataType = ftInteger
        Name = 'MinNo'
        ParamType = ptInput
      end
      item
        DataType = ftString
        Name = 'Co'
        ParamType = ptInput
        Size = 30
      end>
  end
  object StoredProc1: TStoredProc
    DatabaseName = 'DBDEMOS'
    StoredProcName = 'GetCustomer'
    Left = 168
    Top = 8
    ParamData = <
      item
        DataType = ftInteger
        Name = 'CustNo'
        ParamType = ptInput
      end>
  end
  object UpdateSQL1: TUpdateSQL
    Left = 208
    Top = 8
  end
  object BatchMove1: TBatchMove
    Destination = Table1
    Mode = batAppendUpdate
    Source = Query1
    Left = 248
    Top = 8
  end
end