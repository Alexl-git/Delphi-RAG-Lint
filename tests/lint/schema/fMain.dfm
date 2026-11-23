object frmMain: TfrmMain
  Left = 0
  Top = 0
  Caption = 'Schema lint fixture'
  ClientHeight = 200
  ClientWidth = 300
  object qryOrders: TFDQuery
    UpdateOptions.UpdateTableName = 'ORDERS'
    SQL.Strings = (
      'SELECT ID, NOTE FROM ORDERS')
    Left = 16
    Top = 16
    object qryOrdersNOTE: TStringField
      FieldName = 'NOTE'
      Size = 25
    end
  end
  object tblOrders: TFDTable
    TableName = 'ORDERS'
    Left = 64
    Top = 16
    object tblOrdersNOTE: TStringField
      FieldName = 'NOTE'
    end
  end
  object qryList: TFDQuery
    UpdateOptions.UpdateTableName = 'MSCLIST'
    Left = 112
    Top = 16
    object qryListDIMNAME: TStringField
      FieldName = 'DIMNAME'
    end
  end
  object qryFree: TFDQuery
    Left = 160
    Top = 16
    object qryFreeNOTE: TStringField
      FieldName = 'NOTE'
      Size = 99
    end
  end
end
