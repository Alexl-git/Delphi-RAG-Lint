unit path_concat_without_delimiter;

interface

implementation

uses
  System.SysUtils, System.IOUtils;

function Direkt(const P: string): string;
begin
  Result := ExtractFileDir(P) + 'export.csv';
end;

function Variable: string;
var
  Ordner: string;
begin
  Ordner := TPath.GetDocumentsPath;
  Result := Ordner + 'export.csv';
end;

function Gut(const P: string): string;
var
  Ordner: string;
begin
  Result := ExtractFileDir(P) + '\export.csv';
  Result := IncludeTrailingPathDelimiter(ExtractFileDir(P)) + 'export.csv';
  Result := TPath.Combine(ExtractFileDir(P), 'export.csv');
  Ordner := ExtractFilePath(P);
  Result := Ordner + 'export.csv';
end;

function GutMitInclude(const P: string): string;
var
  Ordner: string;
begin
  Ordner := ExtractFileDir(P);
  Ordner := IncludeTrailingPathDelimiter(Ordner);
  Result := Ordner + 'export.csv';
end;

end.
