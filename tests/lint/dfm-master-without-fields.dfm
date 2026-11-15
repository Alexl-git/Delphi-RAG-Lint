object Form1: TForm1
  object dsM: TDataSource
  end
  object tblDetail: TFDTable
    MasterSource = dsM
  end
  object tblOk: TFDTable
    MasterSource = dsM
    MasterFields = 'ID'
  end
  object qry: TFDQuery
    MasterSource = dsM
    SQL.Strings = (
      'select * from x where id = :id')
  end
  object tblNone: TFDTable
  end
end
