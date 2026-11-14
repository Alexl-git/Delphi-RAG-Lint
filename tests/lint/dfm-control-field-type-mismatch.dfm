object Form1: TForm1
  object dsA: TDataSource
    DataSet = tblA
  end
  object tblA: TFDTable
  end
  object tblAAktiv: TBooleanField
    FieldName = 'Aktiv'
    DataSet = tblA
  end
  object tblAName: TStringField
    FieldName = 'Name'
    DataSet = tblA
  end
  object tblAFoto: TBlobField
    FieldName = 'Foto'
    DataSet = tblA
  end
  object edAktiv: TDBEdit
    DataSource = dsA
    DataField = 'Aktiv'
  end
  object cbAktiv: TDBCheckBox
    DataSource = dsA
    DataField = 'Aktiv'
  end
  object imgName: TDBImage
    DataSource = dsA
    DataField = 'Name'
  end
  object edFoto: TDBEdit
    DataSource = dsA
    DataField = 'Foto'
  end
  object imgFoto: TDBImage
    DataSource = dsA
    DataField = 'Foto'
  end
  object edName: TDBEdit
    DataSource = dsA
    DataField = 'Name'
  end
end
