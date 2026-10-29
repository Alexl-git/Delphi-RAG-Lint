unit ExcResp;

interface

implementation

procedure Handle(const pRes: TObject);
begin
  try
    DoWork;
  except
    on E: Exception do
    begin
      pRes.Send(E.Message);
      pRes.Content := E.StackTrace;
      Response.ContentText := E.ToString;
      ShowMessage(E.Message);
      pRes.Send('failed');
      Log(E.Message);
    end;
  end;
end;

end.
