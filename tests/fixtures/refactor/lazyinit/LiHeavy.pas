unit LiHeavy;

// Fixture of lazy-init: a heavy section with an inline variable, a conditional inside it, comments and a finalization.

interface

var
  GShared: Integer;

function HeavyCount: Integer;

implementation

uses
  System.Classes, System.SysUtils, System.IOUtils;

var
  GPrivate: TStringList;

function HeavyCount: Integer;
begin
  Result:= GPrivate.Count + GShared;
end;

initialization
  // the order of these lines is the behaviour under test
  Writeln('LiHeavy init 1');
  GPrivate:= TStringList.Create;
  GShared:= 5;
  {$IFDEF MSWINDOWS}
  if TFile.Exists('no-such-file.txt') then
    GPrivate.Add('found')
  else
  begin
    var Line:= 'absent';
    GPrivate.Add(Line);
  end;
  {$ENDIF}
  Writeln('LiHeavy init 2 ', GPrivate.Count);

finalization
  GPrivate.Free;
  Writeln('LiHeavy final');
end.