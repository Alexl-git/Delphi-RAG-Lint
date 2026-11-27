inherited dmDerived: TdmDerived
  inherited tblOrders: TFDTable
    inherited tblOrdersQTY: TIntegerField
      DisplayLabel = 'Pieces'
    end
    object tblOrdersNOTE: TStringField
      FieldName = 'NOTE'
      OnGetText = tblOrdersNOTEGetText
    end
  end
  inherited memCopy: TFDMemTable
  end
  object tblOwn: TFDTable
    TableName = 'OWNED'
    object tblOwnID: TIntegerField
      FieldName = 'ID'
    end
  end
end
