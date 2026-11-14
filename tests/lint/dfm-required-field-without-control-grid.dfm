object Form1: TForm1
  object dsA: TDataSource
    DataSet = tblA
  end
  object tblA: TFDTable
  end
  object tblACity: TStringField
    FieldName = 'City'
    Required = True
    DataSet = tblA
  end
  object grdA: TDBGrid
    DataSource = dsA
  end
end
