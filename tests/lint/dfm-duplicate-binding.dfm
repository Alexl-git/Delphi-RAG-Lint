object Form1: TForm1
  object dsA: TDataSource
    DataSet = tblA
  end
  object tblA: TFDTable
  end
  object edName: TDBEdit
    DataSource = dsA
    DataField = 'Name'
  end
  object edName2: TDBEdit
    DataSource = dsA
    DataField = 'name'
  end
  object txtName: TDBText
    DataSource = dsA
    DataField = 'Name'
  end
  object edRO: TDBEdit
    DataSource = dsA
    DataField = 'Name'
    ReadOnly = True
  end
  object cxName: TcxDBTextEdit
    DataBinding.DataSource = dsA
    DataBinding.DataField = 'Name'
  end
  object edOther: TDBEdit
    DataSource = dsA
    DataField = 'City'
  end
end
