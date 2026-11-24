object frmDlg: TfrmDlg
  object qryOrders: TFDQuery
    SQL.Strings = (
      'SELECT * FROM ORDERS')
    object qryOrdersID: TIntegerField
      FieldName = 'ID'
    end
    object qryOrdersQTY: TIntegerField
      FieldName = 'QTY'
    end
    object qryOrdersOLD: TStringField
      FieldName = 'OLD'
    end
  end
end