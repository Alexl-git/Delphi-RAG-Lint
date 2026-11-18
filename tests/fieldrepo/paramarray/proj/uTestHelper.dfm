object frmX: TForm
  object tblFOLDERS: TTable
    object tblFOLDERSID: TIntegerField
      FieldName = 'ID'
    end
    object tblFOLDERSNAME: TStringField
      FieldName = 'NAME'
    end
    object tblFOLDERSCREATED: TDateTimeField
      FieldName = 'CREATED'
    end
    object tblFOLDERSFLAG: TStringField
      FieldName = 'FLAG'
    end
    object tblFOLDERSNOTES: TMemoField
      FieldName = 'NOTES'
    end
    object tblFOLDERSAMOUNT: TFloatField
      FieldName = 'AMOUNT'
    end
  end
  object qIns: TFDQuery
    ParamData = <
      item
        Name = 'ID'
        DataType = ftInteger
        ParamType = ptInput
      end
      item
        Name = 'FOLDER_NAME'
        DataType = ftString
      end
      item
        Name = 'CREATED'
        DataType = ftTimeStampOffset
      end
      item
        Name = 'FLAG'
        DataType = ftByte
      end
      item
        Name = 'ACTIVE'
        DataType = ftBoolean
      end
      item
        Name = 'AMOUNT'
        DataType = ftDate
      end>
  end
end