object frmFull: TfrmFull
  object memOrders: TFDMemTable
    UpdateOptions.UpdateTableName = 'ORDERS'
    object memOrdersID: TIntegerField
      FieldName = 'ID'
    end
    object memOrdersQTY: TIntegerField
      Alignment = taCenter
      DisplayLabel = 'It'#39's a quantity, '#233'!'
      FieldName = 'QTY'
      DisplayFormat = '#,##0'
      EditFormat = '0'
    end
    object memOrdersTOTAL: TFloatField
      DisplayLabel = 'Total'
      DisplayWidth = 12
      FieldKind = fkCalculated
      FieldName = 'TOTAL'
      DisplayFormat = '0.00'
      Calculated = True
    end
    object memOrdersBIG: TStringField
      FieldKind = fkInternalCalc
      FieldName = 'BIG'
      Visible = False
      Size = 3
    end
    object memOrdersTOOL: TStringField
      DisplayLabel = 'Tool'
      FieldKind = fkLookup
      FieldName = 'TOOL'
      LookupDataSet = memTools
      LookupKeyFields = 'ID'
      LookupResultField = 'NAME'
      KeyFields = 'TOOLID'
      Size = 30
      Lookup = True
    end
    object memOrdersSUMQ: TAggregateField
      FieldName = 'SUMQ'
      Visible = True
      Active = True
      DisplayName = ''
      Expression = 'SUM(QTY)'
    end
    object memOrdersSTATUS: TIntegerField
      FieldKind = fkCalculated
      FieldName = 'STATUS'
      Calculated = True
    end
  end
  object memTools: TFDMemTable
    UpdateOptions.UpdateTableName = 'TOOLS'
    object memToolsID: TIntegerField
      FieldName = 'ID'
    end
    object memToolsNAME: TStringField
      FieldName = 'NAME'
      Size = 30
    end
  end
end
