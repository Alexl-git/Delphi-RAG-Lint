program IncBranch;

// INC lane fixture: include files are indexed only when an ACTIVE branch of the
// build's define profile includes them, and parsed in the includer's context.

{$APPTYPE CONSOLE}

uses
  UMain in 'UMain.pas';

{$I DprInc.inc}

begin
  Writeln(DprMarker);
end.