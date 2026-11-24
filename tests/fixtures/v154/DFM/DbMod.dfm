object DbMod: TDbMod
  Height = 100
  object Conn: TFDConnection
  end
  object qryA: TFDQuery
    Connection = Conn
  end
end
