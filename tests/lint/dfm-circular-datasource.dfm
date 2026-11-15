object Form1: TForm1
  object tblA: TFDTable
    MasterSource = dsB
    MasterFields = 'ID'
  end
  object tblB: TFDTable
    MasterSource = dsA
    MasterFields = 'ID'
  end
  object dsA: TDataSource
    DataSet = tblA
  end
  object dsB: TDataSource
    DataSet = tblB
  end
  object tblC: TFDTable
    MasterSource = dsA
    MasterFields = 'ID'
  end
end
