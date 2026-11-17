program P1;

{ v152 INITAPI: uses A (A -> B -> C, C implementation-uses A: a cycle), then D.
  Computed order C, B, A, D; each unit prints INIT <name> so a run of the exe proves it. }

{$APPTYPE CONSOLE}

uses
  A in 'A.pas',
  D in 'D.pas';

begin
  Writeln('MAIN');
end.
