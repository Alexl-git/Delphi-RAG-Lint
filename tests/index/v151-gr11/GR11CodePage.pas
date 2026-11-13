unit GR11CodePage;
{ v151 GR11: string types with a code page (grammar v1.4.11 node declStringCodePage).
  Indexed twice by run_v151_GR11_grammar_shapes.ps1: as is, and with GR11_ALT defined. }
interface
const
  CP_GR11 = 1253;
type
  TGr11Ansi1252 = type AnsiString(1252);
  TGr11AnsiNamed = type AnsiString(CP_GR11);
{$IFDEF GR11_ALT}
  TGr11AnsiAlt = type AnsiString(65001);
{$ELSE}
  TGr11AnsiAlt = type AnsiString(1250);
{$ENDIF}
  TGr11Plain = type AnsiString;
function Gr11Convert(const pS: TGr11Ansi1252): TGr11AnsiNamed;
implementation
function Gr11Convert(const pS: TGr11Ansi1252): TGr11AnsiNamed;
var
  lAlt: TGr11AnsiAlt;
begin
  lAlt := TGr11AnsiAlt(pS);
  Result := TGr11AnsiNamed(lAlt);
end;
end.
