program QualGlobal;

// Plan fixture (lane cyc4): the consumer writes and reads a global of the declaring unit qualified by
// that unit. A comment and a string that look qualified stay as they are.

{$APPTYPE CONSOLE}

uses
  QgA in 'QgA.pas',
  QgB in 'QgB.pas';

begin
  QgAShow;
end.
