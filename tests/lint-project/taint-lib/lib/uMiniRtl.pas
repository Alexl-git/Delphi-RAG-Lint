unit uMiniRtl;

interface

function MyTrim(const S: string): string;
function MyQuote(const S: string): string;
procedure GetLine(out S: string);

implementation

function MyTrim(const S: string): string;
begin
  Result := S;
end;

function MyQuote(const S: string): string;
begin
  Result := '''' + S + '''';
end;

procedure GetLine(out S: string);
begin
  S := ParamStr(1);
end;

end.
