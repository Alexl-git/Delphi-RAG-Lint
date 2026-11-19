object frmLoad: TfrmLoad
  Left = 0
  Top = 0
  object tblFOLDERS: TTable
    TableName = 'FOLDERS'
    object tblFOLDERSID: TIntegerField
      FieldName = 'ID'
    end
    object tblFOLDERSNAME: TStringField
      FieldName = 'NAME'
      Size = 40
    end
  end
  object qryFOLDERS: TFDQuery
    AutoCalcFields = False
    CachedUpdates = True
    SchemaAdapter = SA1
    UpdateObject = updFOLDERS
    SQL.Strings = (
      'SELECT ID, NAME'
      'FROM FOLDERS')
    Left = 32
    Top = 48
    object qryFOLDERSID: TIntegerField
      FieldName = 'ID'
    end
    object qryFOLDERSNAME: TStringField
      FieldName = 'NAME'
      Size = 40
    end
  end
  object updFOLDERS: TFDUpdateSQL
    InsertSQL.Strings = (
      'INSERT INTO FOLDERS (ID, NAME)'
      'VALUES (:NEW_ID, :NEW_NAME)')
    Left = 64
    Top = 48
  end
  object SA1: TFDSchemaAdapter
    Left = 96
    Top = 48
  end
end
