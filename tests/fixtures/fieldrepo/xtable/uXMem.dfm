object frmXMem: TfrmXMem
  Left = 0
  Top = 0
  Caption = 'XMem'
  object tblChart: TFDTable
    TableName = 'IPCHART'
    object tblChartCHID: TIntegerField
      FieldName = 'CHID'
    end
    object tblChartRVAL: TFloatField
      FieldName = 'RVAL'
    end
  end
  object qryJ: TFDQuery
    SQL.Strings = (
      'SELECT C.CHID, M.DECIMALS FROM IPCHART C'
      'JOIN INSPRSLT I ON I.INSPID = C.INSPID JOIN MSCLIST M ON M.MSCID = I.MSCID')
    object qryJCHID: TIntegerField
      FieldName = 'CHID'
    end
    object qryJDECIMALS: TIntegerField
      FieldName = 'DECIMALS'
    end
  end
  object memA: TkbmMemTable
    AttachedTo = tblChart
    OnCalcFields = memACalcFields
    object memACHID: TIntegerField
      FieldName = 'CHID'
    end
    object memARVAL: TFloatField
      FieldName = 'RVAL'
    end
    object memAHALF: TFloatField
      FieldKind = fkCalculated
      FieldName = 'HALF'
      Calculated = True
    end
  end
  object memB: TkbmMemTable
    AttachedTo = memA
    object memBRVAL: TFloatField
      FieldName = 'RVAL'
    end
  end
  object memC1: TkbmMemTable
    AttachedTo = memC2
    object memC1RVAL: TFloatField
      FieldName = 'RVAL'
    end
  end
  object memC2: TkbmMemTable
    AttachedTo = memC1
    object memC2RVAL: TFloatField
      FieldName = 'RVAL'
    end
  end
  object memD: TkbmMemTable
    object memDRVAL: TFloatField
      FieldName = 'RVAL'
    end
  end
  object memE: TkbmMemTable
    object memERVAL: TFloatField
      FieldName = 'RVAL'
    end
  end
  object memF: TFDMemTable
    object memFCHID: TIntegerField
      FieldName = 'CHID'
    end
    object memFRVAL: TFloatField
      FieldName = 'RVAL'
    end
  end
  object memG: TFDMemTable
    object memGCHID: TIntegerField
      FieldName = 'CHID'
    end
    object memGDECIMALS: TIntegerField
      FieldName = 'DECIMALS'
    end
  end
  object memH: TFDMemTable
    object memHRVAL: TFloatField
      FieldName = 'RVAL'
    end
  end
  object memI: TFDMemTable
    object memIRVAL: TFloatField
      FieldName = 'RVAL'
    end
  end
  object memJ: TFDMemTable
    object memJRVAL: TFloatField
      FieldName = 'RVAL'
    end
  end
  object memK: TFDMemTable
    object memKRVAL: TFloatField
      FieldName = 'RVAL'
    end
  end
  object memL: TFDMemTable
    object memLRVAL: TFloatField
      FieldName = 'RVAL'
    end
  end
  object tblCalc: TFDTable
    TableName = 'IPCHART'
    OnCalcFields = tblCalcCalcFields
    object tblCalcCHID: TIntegerField
      FieldName = 'CHID'
    end
    object tblCalcRVAL: TFloatField
      FieldName = 'RVAL'
    end
    object tblCalcFTRNAME: TStringField
      FieldKind = fkCalculated
      FieldName = 'FTRNAME'
      Size = 40
      Calculated = True
    end
  end
end