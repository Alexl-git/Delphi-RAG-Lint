unit basic;

interface

implementation

type
  TXmlDoc = class
  public
    resolveExternals: Boolean;
    ProhibitDTD: Boolean;
    procedure setProperty(const pName: string; pValue: Boolean);
  end;

procedure TXmlDoc.setProperty(const pName: string; pValue: Boolean);
begin
end;

procedure Configure(const pDoc: TXmlDoc);
begin
  pDoc.resolveExternals := False;
  pDoc.ProhibitDTD := True;
  pDoc.setProperty('ProhibitDTD', True);
  pDoc.resolveExternals := False;
  pDoc.ProhibitDTD := True;
end;

end.