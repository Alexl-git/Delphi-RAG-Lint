unit Paths;

interface

implementation

uses
  System.Classes, System.IOUtils;

procedure P(const AFromUser: string);
var
  S : string;
  SL: TStringList;
begin
  { A path PORTION reaching a filesystem sink -- absolute and relative BOTH fire. }
  TFile.WriteAllText('C:\Temp\log.txt', 'x');
  SL := TStringList.Create;
  SL.LoadFromFile('relative\path\data.csv');
  SL.Free;
  { No sink: nothing opens it, so it is not a hardcoded path USE. }
  S := 'C:\Temp\never-opened.txt';
  Writeln(S);
  { A bare filename MAY be hardcoded -- only the path to it may not. }
  TFile.WriteAllText('report.csv', 'x');
  { Computed from outside the source -- clean however it is spelled. }
  TFile.WriteAllText(AFromUser, 'x');
end;

end.
