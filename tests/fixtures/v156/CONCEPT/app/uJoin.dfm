object frmJoin: TfrmJoin
  Left = 0
  Top = 0
  Caption = 'Join'
  object qryJoin: TFDQuery
    SQL.Strings = (
      'SELECT C.ID AS CUSTOMER_ID, NAME'
      'FROM CUSTOMERS C'
      'JOIN SUPPLIERS S ON S.ID = C.ID')
    object qryJoinNAME: TStringField
      DisplayLabel = 'Supplied by'
      FieldName = 'NAME'
      Origin = 'SUPPLIERS.NAME'
      Size = 40
    end
    object qryJoinCUSTOMER_ID: TIntegerField
      FieldName = 'CUSTOMER_ID'
    end
  end
end
