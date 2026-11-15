object Form1: TForm1
  object dsA: TDataSource
    DataSet = tblA
  end
  object tblA: TFDTable
  end
  object tblAName: TStringField
    FieldName = 'Name'
    Required = True
    DataSet = tblA
  end
  object tblACity: TStringField
    FieldName = 'City'
    Required = True
    DataSet = tblA
  end
  object tblAZip: TStringField
    FieldName = 'Zip'
    Required = True
    DataSet = tblA
  end
  object tblACode: TAutoIncField
    FieldName = 'Code'
    Required = True
    DataSet = tblA
  end
  object tblAOpt: TStringField
    FieldName = 'Opt'
    DataSet = tblA
  end
  object edName: TDBEdit
    DataSource = dsA
    DataField = 'Name'
  end
  object edZip: TDBEdit
    DataSource = dsA
    DataField = 'Zip'
    Visible = False
  end
end
