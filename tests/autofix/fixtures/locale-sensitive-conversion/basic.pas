unit basic;

interface

implementation

uses
  System.SysUtils, System.Classes, System.IniFiles;

procedure Save(Ini: TIniFile; V: Double);
begin
  Ini.WriteString('a', 'v', FloatToStr(V));
end;

procedure Load(L: TStringList; var V: Double);
begin
  V:= StrToFloat(L.Values['k']);
end;

end.
