object PolicyForm: TPolicyForm
  Left = 0
  object Conn: TFDConnection
    Connected = True
  end
  object ConnOff: TFDConnection
    Connected = False
  end
  object qryOpen: TFDQuery
    Active = True
    Connection = Conn
  end
  object qryShut: TFDQuery
    Active = False
  end
  object memData: TFDMemTable
    Active = True
    Data = {
      04000000
    }
  end
  object cdsData: TClientDataSet
    Active = True
  end
  object ViewX: TcxGridDBTableView
    Active = True
  end
end
