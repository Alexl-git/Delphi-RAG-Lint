unit pnp;
interface
procedure Go(Amount: Integer; pName: string);  // 'Amount' fires; 'pName' clean
procedure Ok(pName: string; AValue: Integer);  // clean: both accepted prefixes (p, A)
implementation
procedure Go(Amount: Integer; pName: string);
begin
end;
procedure Ok(pName: string; AValue: Integer);
begin
end;
procedure One(N: Integer; S: string);  // clean: single-letter params are exempt (owner card C, 1.52.2)
begin
end;
end.
