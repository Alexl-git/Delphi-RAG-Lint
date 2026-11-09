unit LdHeavy;

// Fixture of lazy-init --defer: the section's work must not run when the unit initializes, and must run exactly once,
// on the first call of a routine that touches what the section writes.

interface

function DeferCount: Integer;
procedure DeferAdd(const pText: string);
function DeferPlain: Integer;

implementation

uses
  System.Classes, System.SysUtils, System.IOUtils;

var
  GItems: TStringList;
  GRuns: Integer;

function DeferCount: Integer;
begin
  Result:= GItems.Count * 100 + GRuns;
end;

procedure DeferAdd(const pText: string);
begin
  GItems.Add(pText);
end;

function DeferPlain: Integer;
begin
  Result:= 7;
end;

initialization
  GRuns:= GRuns + 1;
  Writeln('LdHeavy init ', GRuns);
  GItems:= TStringList.Create;
  if TFile.Exists('no-such-file.txt') then
    GItems.Add('found');

finalization
  Writeln('LdHeavy final ', GItems.Count);
  GItems.Free;
end.