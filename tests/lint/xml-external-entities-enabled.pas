unit XmlXxe;

interface

implementation

procedure Configure(const pDoc: TObject);
begin
  pDoc.resolveExternals := True;
  pDoc.resolveExternals := False;
  pDoc.ProhibitDTD := False;
  pDoc.ProhibitDTD := True;
  pDoc.setProperty('ProhibitDTD', False);
  pDoc.setProperty('ProhibitDTD', True);
end;

end.
