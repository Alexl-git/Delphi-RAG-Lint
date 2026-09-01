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
  { An ABSOLUTE ROOT reaching a filesystem sink is the finding. }
  TFile.WriteAllText('C:\Temp\log.txt', 'x');
  { A RELATIVE portion is allowed (owner ruling 2026-09-01) -- it names no
    location on any one machine, so it does not break on another. }
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
