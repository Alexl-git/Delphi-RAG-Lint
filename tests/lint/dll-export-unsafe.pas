library DllExportUnsafe;

function KundeName(Id: Integer): string;
begin
  Result := '';
end;

function KundeNr(Id: Integer): Integer; stdcall;
begin
  Result := Id;
end;

function Wert(Id: Integer): Integer; cdecl;
begin
  Result := Id;
end;

exports
  KundeName,
  KundeNr,
  Wert;

begin
end.
