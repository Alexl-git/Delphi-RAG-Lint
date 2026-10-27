unit basic;

interface

implementation

procedure Configure(const pDoc: TObject);
begin
  pDoc.resolveExternals := False;
  pDoc.ProhibitDTD := True;
  pDoc.setProperty('ProhibitDTD', True);
  pDoc.resolveExternals := False;
  pDoc.ProhibitDTD := True;
end;

end.