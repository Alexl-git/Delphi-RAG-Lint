unit ClearCred;

interface

implementation

procedure Save(const pIni: TObject; const pPass: string);
begin
  pIni.WriteString('Server', 'Password', pPass);
  pIni.WriteString('Server', 'Password', Encrypt(pPass));
  pIni.WriteString('Server', 'Host', pPass);
  pIni.WriteString('Server', 'ApiToken', 'abc');
  pIni.WriteString('Server', 'Secret', EncodeBase(pPass));
end;

end.
