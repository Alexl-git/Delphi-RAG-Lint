program Probe;

{ uses-recover fixture: the project. FixLibA has no source in this index. }

{$APPTYPE CONSOLE}

uses
  FixLibA;

begin
  MakeLibB.Free;
end.
