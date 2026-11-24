object DM: TDM
  object qOne: TFDQuery
    SQL.Strings = (
      'SELECT A FROM T'
      'WHERE ID = :ID')
  end
  object qTwo: TFDQuery
    SQL.Strings = (
      'SELECT A FROM T WHERE K = :K')
  end
  object qOut: TFDQuery
    SQL.Strings = (
      'SELECT A FROM T')
  end
  object qMissing: TFDQuery
    SQL.Strings = (
      'SELECT A FROM T WHERE A = :A AND B = :B')
  end
  object qValued: TFDQuery
    SQL.Strings = (
      'SELECT A FROM T WHERE A = :A AND B = :B')
    ParamData = <
      item
        Name = 'A'
        Value = Null
      end
      item
        Name = 'B'
        Value = 5
      end>
  end
  object qNullDecl: TFDQuery
    SQL.Strings = (
      'SELECT A FROM T WHERE (:A IS NULL OR A = :A) AND B = :B')
    ParamData = <
      item
        Name = 'A'
        DataType = ftInteger
        Value = Null
      end>
  end
end