object frmGrid: TfrmGrid
  object tblO: TTable
    OnCalcFields = tblOCalcFields
    TableName = 'Orders.DB'
    object tblOQTY: TIntegerField
      FieldName = 'Qty'
      OnChange = tblOQTYChange
      OnGetText = tblOQTYGetText
      OnSetText = tblOQTYSetText
      OnValidate = tblOQTYValidate
    end
    object tblONOTE: TStringField
      FieldName = 'Note'
      Size = 10
    end
    object tblOTOTAL: TFloatField
      FieldKind = fkCalculated
      FieldName = 'Total'
      Calculated = True
    end
  end
  object dsO: TDataSource
    DataSet = tblO
  end
  object qryJoin: TQuery
    SQL.Strings = (
      'SELECT O.Qty, T.Name, O.Qty * 2 AS Dbl FROM "Orders.DB" O, "Tools.DB" T')
  end
  object dsJoin: TDataSource
    DataSet = qryJoin
  end
  object cxGrid1: TcxGrid
    object view1: TcxGridDBTableView
      DataController.DataSource = dsO
      object colTotal: TcxGridDBColumn
        DataBinding.FieldName = 'Total'
      end
      object colQty: TcxGridDBColumn
        DataBinding.FieldName = 'Qty'
        OnCustomDrawCell = colQtyCustomDrawCell
        OnGetDisplayText = colQtyGetDisplayText
      end
      object colDraw: TcxGridDBColumn
        Caption = 'Drawn'
        OnCustomDrawCell = colDrawCustomDrawCell
      end
      object colQty2: TcxGridDBColumn
        DataBinding.FieldName = 'qty'
      end
      object colGhost: TcxGridDBColumn
        DataBinding.FieldName = 'Ghost'
        OnGetDisplayText = colQtyGetDisplayText
      end
    end
    object band1: TcxGridDBBandedTableView
      DataController.DataSource = dmOther.dsReason
      Bands = <
        item
          Caption = 'B'
        end>
      object bandCode: TcxGridDBBandedColumn
        DataBinding.FieldName = 'Code'
        OnCustomDrawCell = colDrawCustomDrawCell
        Position.BandIndex = 0
      end
    end
    object viewJ: TcxGridDBTableView
      DataController.DataSource = dsJoin
      object jName: TcxGridDBColumn
        DataBinding.FieldName = 'Name'
      end
      object jDbl: TcxGridDBColumn
        DataBinding.FieldName = 'Dbl'
      end
    end
    object viewNone: TcxGridDBTableView
      DataController.DataSource = dsGone
      object nOne: TcxGridDBColumn
        DataBinding.FieldName = 'One'
      end
    end
    object card1: TcxGridDBCardView
      DataController.DataSource = dsO
      object card1QTY: TcxGridDBCardViewRow
        DataBinding.FieldName = 'Qty'
      end
    end
    object cxGrid1Level1: TcxGridLevel
      GridView = view1
    end
  end
  inline Frame1: TFrame1
    inherited viewIn: TcxGridDBTableView
      inherited inCol: TcxGridDBColumn
        Width = 20
      end
    end
  end
end
