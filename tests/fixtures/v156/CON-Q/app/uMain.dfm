object frmMain: TfrmMain
  Left = 0
  Top = 0
  Caption = 'Customers'
  object qryCustomers: TFDQuery
    SQL.Strings = (
      'SELECT ID, NAME, CREDIT_LIMIT FROM CUSTOMERS')
    object qryCustomersNAME: TStringField
      DisplayLabel = 'Client name'
      FieldName = 'NAME'
    end
    object qrySuppliersNAME: TStringField
      FieldName = 'NAME'
      Origin = 'SUPPLIERS.NAME'
    end
    object qryCustomersPHONE: TStringField
      DisplayLabel = 'Phone number'
      FieldName = 'PHONE'
    end
  end
  object colName: TcxGridDBColumn
    Caption = 'Cust. &name'
    DataBinding.FieldName = 'NAME'
  end
  object edName: TcxDBTextEdit
    Hint = 'Type the legal name here'
    DataBinding.DataField = 'NAME'
  end
end
