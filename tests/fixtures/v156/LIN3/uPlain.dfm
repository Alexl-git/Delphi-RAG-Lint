object fPlain: TfPlain
  Left = 0
  Top = 0
  Caption = 'fPlain'
  ClientHeight = 100
  ClientWidth = 100
  object qryPlain: TFDQuery
    SQL.Strings = (
      'SELECT ID, QTY FROM ORDERS')
    Left = 24
    Top = 24
  end
end
