unit Locale;

interface

uses System.SysUtils;

implementation

procedure P(S: string; X: Double; FS: TFormatSettings);
begin
  X := StrToFloat(S);
  X := StrToFloat(S, FS);
end;

end.
