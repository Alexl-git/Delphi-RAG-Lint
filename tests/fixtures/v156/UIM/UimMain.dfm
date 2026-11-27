object frmMain: TfrmMain
  Left = 0
  Top = 0
  Caption = 'Main'
  ClientHeight = 100
  ClientWidth = 200
  object qCust: TFDQuery
    object qCustCUSTNAME: TStringField
      FieldName = 'CUSTNAME'
    end
  end
  object edName: TDBEdit
    Left = 8
    Top = 8
    Width = 121
    Height = 21
    DataField = 'CUSTNAME'
    TabOrder = 0
  end
  object edCity: TDBEdit
    Left = 8
    Top = 40
    Width = 121
    Height = 21
    DataField = 'CITY'
    TabOrder = 1
  end
  object colName: TcxGridDBColumn
    DataBinding.FieldName = 'CUSTNAME'
  end
  object lcbCust: TDBLookupComboBox
    KeyField = 'CUSTID'
    ListField = 'CUSTNAME;CITY'
  end
end
