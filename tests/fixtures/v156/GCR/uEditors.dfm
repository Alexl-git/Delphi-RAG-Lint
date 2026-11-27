object frmEditors: TfrmEditors
  Caption = 'Editors'
  object tblO: TTable
    TableName = 'Orders.DB'
    object tblOQTY: TIntegerField
      FieldName = 'Qty'
    end
    object tblOSTATUS: TStringField
      FieldName = 'Status'
      Size = 1
    end
    object tblOKIND: TStringField
      FieldName = 'Kind'
      Size = 10
    end
    object tblOPRICE: TFloatField
      FieldName = 'Price'
    end
    object tblODONE: TBooleanField
      FieldName = 'Done'
    end
    object tblONOTE: TStringField
      FieldName = 'Note'
      Size = 40
    end
  end
  object dsO: TDataSource
    DataSet = tblO
  end
  object cxGrid1: TcxGrid
    object view1: TcxGridDBTableView
      DataController.DataSource = dsO
      object colQty: TcxGridDBColumn
        DataBinding.FieldName = 'Qty'
        Width = 40
      end
      object colStatus: TcxGridDBColumn
        Caption = 'Status'
        DataBinding.FieldName = 'Status'
        PropertiesClassName = 'TcxImageComboBoxProperties'
        Properties.Alignment.Horz = taCenter
        Properties.Items = <
          item
            Description = 'Open'
            ImageIndex = 0
            Value = 'O'
          end
          item
            Description = 'It'#39's closed'
            Value = 'C'
          end>
        Properties.OnChange = colStatusPropertiesChange
        Width = 80
      end
      object colKind: TcxGridDBColumn
        DataBinding.FieldName = 'Kind'
        PropertiesClassName = 'TcxComboBoxProperties'
        Properties.DropDownListStyle = lsFixedList
        Properties.Items.Strings = (
          'One'
          'Two')
      end
      object colPrice: TcxGridDBColumn
        DataBinding.FieldName = 'Price'
        PropertiesClassName = 'TcxCurrencyEditProperties'
        Properties.DisplayFormat = 
          '#,##0.00 "a long display format that the form designer writes on' +
          ' two lines";-#,##0.00'
        Properties.Nullable = False
        Options.Editing = False
      end
      object colDone: TcxGridDBColumn
        DataBinding.FieldName = 'Done'
        PropertiesClassName = 'TcxCheckBoxProperties'
      end
      object colNote: TcxGridDBColumn
        DataBinding.FieldName = 'Note'
        Properties.ReadOnly = True
      end
    end
    object band1: TcxGridDBBandedTableView
      DataController.DataSource = dsO
      Bands = <
        item
          Caption = 'B'
        end>
      object bandQty: TcxGridDBBandedColumn
        DataBinding.FieldName = 'Qty'
        PropertiesClassName = 'TcxSpinEditProperties'
        Properties.MaxValue = 99.000000000000000000
        Position.BandIndex = 0
      end
    end
    object cxGrid1Level1: TcxGridLevel
      GridView = view1
    end
  end
end
