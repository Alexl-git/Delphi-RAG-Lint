program NoCut;

// E18 T13 fixture nocut: see NoCutA.

{$APPTYPE CONSOLE}

uses
  NoCutA in 'NoCutA.pas',
  NoCutB in 'NoCutB.pas';

begin
  TNoCutA.Create.Run;
  TNoCutB.Create.Run;
end.