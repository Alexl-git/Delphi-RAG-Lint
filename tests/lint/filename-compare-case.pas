unit filename_compare_case;

interface

implementation

uses
  System.SysUtils, System.IOUtils;

procedure Pruefen(const Datei, Andere: string);
begin
  if ExtractFileName(Datei) = 'Config.ini' then Exit;
  if 'Config.ini' <> ExtractFileName(Datei) then Exit;
  if ExtractFileExt(Datei) = Andere then Exit;
  if TPath.GetDirectoryName(Datei) <> Andere then Exit;
end;

procedure Fein(const Datei, Andere: string);
begin
  if SameText(ExtractFileName(Datei), 'Config.ini') then Exit;
  if ExtractFileExt(Datei) = '' then Exit;
  if ExtractFileName(Datei) < Andere then Exit;
  if Datei = Andere then Exit;
end;

end.
