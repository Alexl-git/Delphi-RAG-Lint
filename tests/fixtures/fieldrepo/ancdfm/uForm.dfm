object frmMain: TfrmMain
  object tblLocal: TFDTable
    TableName = 'LOCALS'
    object tblLocalID: TIntegerField
      FieldName = 'ID'
    end
    object tblLocalCUST_ID: TIntegerField
      FieldName = 'CUST_ID'
    end
    object tblLocalCUST: TStringField
      FieldKind = fkLookup
      FieldName = 'CUST'
      LookupDataSet = dmDerived.tblCust
      LookupKeyFields = 'ID'
      LookupResultField = 'NAME'
      KeyFields = 'CUST_ID'
      Lookup = True
    end
  end
  object memOrders: TFDMemTable
    object memOrdersID: TIntegerField
      FieldName = 'ID'
    end
    object memOrdersNOTE: TStringField
      FieldName = 'NOTE'
    end
  end
  object memCust: TFDMemTable
    object memCustNAME: TStringField
      FieldName = 'NAME'
    end
  end
  object memDeep: TFDMemTable
    object memDeepQTY: TIntegerField
      FieldName = 'QTY'
    end
  end
  object memItems: TFDMemTable
    object memItemsCODE: TStringField
      FieldName = 'CODE'
    end
  end
  object memAtt: TFDMemTable
    object memAttID: TIntegerField
      FieldName = 'ID'
    end
  end
  object memAmb: TFDMemTable
    object memAmbID: TIntegerField
      FieldName = 'ID'
    end
  end
  object memNoUnit: TFDMemTable
    object memNoUnitID: TIntegerField
      FieldName = 'ID'
    end
  end
  object memOrphan: TFDMemTable
    object memOrphanID: TIntegerField
      FieldName = 'ID'
    end
  end
  object memGone: TFDMemTable
    object memGoneID: TIntegerField
      FieldName = 'ID'
    end
  end
end
