object DM2: TDM2
  object qEvt: TFDQuery
    BeforeOpen = qEvtBeforeOpen
    SQL.Strings = (
      'SELECT A FROM T WHERE A = :A AND B = :B')
  end
end
