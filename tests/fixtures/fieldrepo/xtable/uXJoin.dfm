object frmXJoin: TfrmXJoin
  Left = 0
  Top = 0
  Caption = 'XJoin'
  object qryChart: TFDQuery
    OnCalcFields = qryChartCalcFields
    SQL.Strings = (
      'SELECT C.CHID, C.RVAL, M.NOTATION, M.DECIMALS'
      'FROM IPCHART C'
      'JOIN INSPRSLT I ON I.INSPID = C.INSPID'
      'LEFT JOIN MSCLIST M ON (M.MSCID = I.MSCID)')
    object qryChartCHID: TIntegerField
      FieldName = 'CHID'
    end
    object qryChartRVAL: TFloatField
      FieldName = 'RVAL'
    end
    object qryChartNOTATION: TIntegerField
      FieldName = 'NOTATION'
    end
    object qryChartDECIMALS: TIntegerField
      FieldName = 'DECIMALS'
    end
    object qryChartFTRNAME: TStringField
      FieldKind = fkCalculated
      FieldName = 'FTRNAME'
      Size = 40
      Calculated = True
    end
    object qryChartDOUBLED: TFloatField
      FieldKind = fkCalculated
      FieldName = 'DOUBLED'
      Calculated = True
    end
    object qryChartLABELX: TStringField
      FieldKind = fkCalculated
      FieldName = 'LABELX'
      Size = 60
      Calculated = True
    end
  end
  object qryWhere: TFDQuery
    OnCalcFields = qryWhereCalcFields
    SQL.Strings = (
      'SELECT C.CHID, C.RVAL, M.DECIMALS'
      'FROM IPCHART C, IINSP I, MSCLIST M'
      'WHERE C.IID = I.IID AND I.MSCID = M.MSCID AND C.RVAL > 0'
      'ORDER BY C.CHID')
    object qryWhereCHID: TIntegerField
      FieldName = 'CHID'
    end
    object qryWhereRVAL: TFloatField
      FieldName = 'RVAL'
    end
    object qryWhereDECIMALS: TIntegerField
      FieldName = 'DECIMALS'
    end
    object qryWhereALTNAME: TStringField
      FieldKind = fkCalculated
      FieldName = 'ALTNAME'
      Size = 40
      Calculated = True
    end
  end
  object qryOr: TFDQuery
    OnCalcFields = qryOrCalcFields
    SQL.Strings = (
      'SELECT C.CHID, C.RVAL, M.DECIMALS'
      'FROM IPCHART C, IINSP I, MSCLIST M'
      'WHERE C.IID = I.IID AND I.MSCID = M.MSCID OR C.RVAL > 0')
    object qryOrCHID: TIntegerField
      FieldName = 'CHID'
    end
    object qryOrRVAL: TFloatField
      FieldName = 'RVAL'
    end
    object qryOrDECIMALS: TIntegerField
      FieldName = 'DECIMALS'
    end
    object qryOrORNAME: TStringField
      FieldKind = fkCalculated
      FieldName = 'ORNAME'
      Size = 40
      Calculated = True
    end
  end
  object qryGroup: TFDQuery
    OnCalcFields = qryGroupCalcFields
    SQL.Strings = (
      'SELECT C.CHID, C.RVAL, G.GRNAME, N.NKNAME'
      'FROM IPCHART C'
      'JOIN TOOLGR G ON G.GRID = C.GRID'
      'LEFT OUTER JOIN NOKEY N ON N.NK = C.NK')
    object qryGroupCHID: TIntegerField
      FieldName = 'CHID'
    end
    object qryGroupRVAL: TFloatField
      FieldName = 'RVAL'
    end
    object qryGroupGRNAME: TStringField
      FieldName = 'GRNAME'
      Size = 20
    end
    object qryGroupNKNAME: TStringField
      FieldName = 'NKNAME'
      Size = 20
    end
    object qryGroupGRTXT: TStringField
      FieldKind = fkCalculated
      FieldName = 'GRTXT'
      Size = 40
      Calculated = True
    end
    object qryGroupNKTXT: TStringField
      FieldKind = fkCalculated
      FieldName = 'NKTXT'
      Size = 40
      Calculated = True
    end
  end
  object qryPair: TFDQuery
    OnCalcFields = qryPairCalcFields
    SQL.Strings = (
      'SELECT A.PID, A.ANAME, B.BNAME'
      'FROM PAIRA A JOIN PAIRB B ON B.PID = A.PID')
    object qryPairPID: TIntegerField
      FieldName = 'PID'
    end
    object qryPairANAME: TStringField
      FieldName = 'ANAME'
      Size = 20
    end
    object qryPairBNAME: TStringField
      FieldName = 'BNAME'
      Size = 20
    end
    object qryPairPAIRTXT: TStringField
      FieldKind = fkCalculated
      FieldName = 'PAIRTXT'
      Size = 40
      Calculated = True
    end
  end
  object qryTwice: TFDQuery
    OnCalcFields = qryTwiceCalcFields
    SQL.Strings = (
      'SELECT C.CHID, C.RVAL, M1.DECIMALS, M2.NOTATION'
      'FROM IPCHART C'
      'JOIN INSPRSLT I ON I.INSPID = C.INSPID'
      'JOIN MSCLIST M1 ON M1.MSCID = I.MSCID'
      'JOIN IINSP J ON J.IID = C.IID'
      'JOIN MSCLIST M2 ON M2.MSCID = J.MSCID')
    object qryTwiceCHID: TIntegerField
      FieldName = 'CHID'
    end
    object qryTwiceRVAL: TFloatField
      FieldName = 'RVAL'
    end
    object qryTwiceDECIMALS: TIntegerField
      FieldName = 'DECIMALS'
    end
    object qryTwiceNOTATION: TIntegerField
      FieldName = 'NOTATION'
    end
    object qryTwiceTWOMSC: TStringField
      FieldKind = fkCalculated
      FieldName = 'TWOMSC'
      Size = 40
      Calculated = True
    end
  end
end
