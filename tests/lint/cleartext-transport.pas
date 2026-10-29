unit ClearTransport;

interface

implementation

procedure Fetch(const pClient: TObject);
const
  NsUri = 'http://www.w3.org/2001/XMLSchema';
begin
  pClient.Get('http://example.com/api');
  pClient.Get('http://localhost:8080/api');
  pClient.Get('https://example.com/api');
  pClient.Post('http://10.0.0.5/x', nil);
  pClient.UseTLS := utNoTLSSupport;
  pClient.UseTLS := utUseImplicitTLS;
  pClient.URL := 'http://example.com/y';
  pClient.URL := 'http://127.0.0.1/y';
end;

end.
