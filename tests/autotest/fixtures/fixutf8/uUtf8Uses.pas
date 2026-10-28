unit uUtf8Uses;

{ Fixture for run_fixutf8_uses.ps1. The guard replaces each {{AE}} / {{UE}} marker by the
  UTF-8 bytes of a-umlaut / u-umlaut before indexing, so this checked-in source stays 7-bit ASCII. }

interface

{ the non-ASCII comment sits BEFORE the unit name on its uses line: the finding column counts characters }
uses { Z{{AE}}hler } uUtf8Helper, System.SysUtils;

function Twice(const AValue: Integer): Integer;

implementation

{ Gr{{UE}}sse: this comment must survive the fix byte for byte. }
function Twice(const AValue: Integer): Integer;
begin
  Result:= AValue * 2;
  Result:= StrToInt(IntToStr(Result));
end;

end.
