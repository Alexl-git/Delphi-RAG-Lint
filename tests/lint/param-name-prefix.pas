unit pnp;
interface
procedure Go(Value: Integer; pName: string);  // 'Value' fires; 'pName' clean
procedure Ok(pName: string; AValue: Integer);  // clean: both accepted prefixes (p, A)
implementation
procedure Go(Value: Integer; pName: string);
begin
end;
procedure Ok(pName: string; AValue: Integer);
begin
end;
end.
