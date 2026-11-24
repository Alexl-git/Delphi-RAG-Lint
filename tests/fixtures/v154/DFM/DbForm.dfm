object DbForm: TDbForm
  Left = 0
  object Conn: TFDConnection
    Left = 8
  end
  object qryA: TFDQuery
    Connection = Conn
  end
  object dsA: TDataSource
    DataSet = qryA
  end
  object memA: TFDMemTable
  end
  object cdsA: TClientDataSet
  end
  object Grid: TDBGrid
    DataSource = dsA
  end
end
