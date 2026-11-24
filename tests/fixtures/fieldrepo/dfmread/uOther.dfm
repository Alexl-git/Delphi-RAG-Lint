object dmOther: TdmOther
  object tblReason: TTable
    TableName = 'Reasons.db'
    object tblReasonCode: TIntegerField
      FieldName = 'Code'
    end
  end
  object dsReason: TDataSource
    DataSet = tblReason
  end
end
