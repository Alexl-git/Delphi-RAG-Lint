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
      LookupDataSet = dmMod.tblCust
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
    object memOrdersQTY: TIntegerField
      FieldName = 'QTY'
    end
  end
  object memTwin: TFDMemTable
    object memTwinID: TIntegerField
      FieldName = 'ID'
    end
  end
  object memGhost: TFDMemTable
    object memGhostID: TIntegerField
      FieldName = 'ID'
    end
  end
  object memGone: TFDMemTable
    object memGoneID: TIntegerField
      FieldName = 'ID'
    end
  end
end
