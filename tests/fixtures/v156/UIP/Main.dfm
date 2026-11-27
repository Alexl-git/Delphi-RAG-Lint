object Form1: TForm1
  object edName: TDBEdit
    DataField = 'CUSTNAME'
  end
  object colN: TcxGridDBColumn
    DataBinding.FieldName = 'CUSTNAME'
  end
  object lcb: TDBLookupComboBox
    KeyField = 'CUSTID'
    ListField = 'CUSTNAME;CITY'
  end
end
