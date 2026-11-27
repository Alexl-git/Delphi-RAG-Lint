object frmMain: TfrmMain
  Left = 0
  Top = 0
  Caption = 'Customers'
  object qryCustomers: TFDQuery
    SQL.Strings = (
      'SELECT ID, NAME, CREDIT_LIMIT'
      'FROM CUSTOMERS')
    object qryCustomersID: TIntegerField
      FieldName = 'ID'
    end
    object qryCustomersNAME: TStringField
      DisplayLabel = 'Client name'
      FieldName = 'NAME'
      Size = 40
    end
    object qryCustomersCREDIT_LIMIT: TFloatField
      DisplayLabel = 'Credit limit'
      FieldName = 'CREDIT_LIMIT'
    end
  end
  object dsCustomers: TDataSource
    DataSet = qryCustomers
  end
  object tblSuppliers: TFDTable
    TableName = 'SUPPLIERS'
    object tblSuppliersNAME: TStringField
      DisplayLabel = 'Vendor'
      FieldName = 'NAME'
      Size = 40
    end
  end
  object dsSuppliers: TDataSource
    DataSet = tblSuppliers
  end
  object grdMain: TcxGrid
    Left = 8
    Top = 8
    object tvCustomers: TcxGridDBTableView
      DataController.DataSource = dsCustomers
      object colName: TcxGridDBColumn
        Caption = 'Cust. &name'
        DataBinding.FieldName = 'NAME'
        Hint = 'Name as  printed on'#13#10'the invoice'
      end
      object colLimit: TcxGridDBColumn
        Caption = 'Limit'
        DataBinding.FieldName = 'CREDIT_LIMIT'
      end
      object colName2: TcxGridDBColumn
        Caption = 'Cust. name'
        DataBinding.FieldName = 'NAME'
      end
      object colOther: TcxGridDBColumn
        Caption = 'Vendor (grid)'
        DataBinding.FieldName = 'ALIAS_X'
      end
    end
  end
  object edtName: TcxDBTextEdit
    Left = 8
    Top = 200
    Hint = 'Type the legal name'
    DataBinding.DataField = 'NAME'
    DataBinding.DataSource = dsCustomers
  end
  object grdOld: TDBGrid
    Left = 8
    Top = 240
    DataSource = dsSuppliers
    Columns = <
      item
        FieldName = 'NAME'
        Title.Caption = 'Supplier (old grid)'
      end>
  end
end
