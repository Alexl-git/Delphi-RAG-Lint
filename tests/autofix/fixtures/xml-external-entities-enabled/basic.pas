unit basic;

interface

implementation

procedure Configure(const pDoc: TObject);
begin
  pDoc.resolveExternals := True;
  pDoc.ProhibitDTD := False;
  pDoc.setProperty('ProhibitDTD', False);
  pDoc.resolveExternals := False;
  pDoc.ProhibitDTD := True;
end;

end.