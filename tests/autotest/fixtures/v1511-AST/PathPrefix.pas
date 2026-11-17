unit PathPrefix;

interface

function KeyOf(V: Integer): string;
function IsNum(const Def: string): Boolean;
function ReadCfg: string;
function Probe: string;

implementation

uses
  System.SysUtils, System.StrUtils, System.IOUtils;

{ B15: kind prefixes, not drive paths -- no sink reached. }
function KeyOf(V: Integer): string;
begin
  Result:= 'n:' + IntToStr(V);
end;

function IsNum(const Def: string): Boolean;
begin
  Result:= StartsStr('i:', Def);
end;

{ Positive control 1: a complete path reaching a file sink. }
function ReadCfg: string;
begin
  Result:= TFile.ReadAllText('C:\data\cfg.txt');
end;

{ Positive control 2: a complete path reaching no sink still reports for review. }
function Probe: string;
begin
  Result:= 'D:\probe\here';
end;

end.