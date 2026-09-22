unit uUnbound;
{ Purity v2 stage fixture: unbound callees (acceptance 11, 12, 15). }
interface
function CallsTrim(const S: string): string;
function CallsSubString(const S: string): string;
implementation
function CallsTrim(const S: string): string;
begin
  Result := Trim(S);
end;
function CallsSubString(const S: string): string;
begin
  Result := S.SubString(1, 2);
end;
end.
