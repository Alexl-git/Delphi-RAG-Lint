program F2047Clause;

{$APPTYPE CONSOLE}

uses
  FaUnit in 'FaUnit.pas',
  FbUnit in 'FbUnit.pas',
  IcUnit in 'IcUnit.pas',
  IdUnit in 'IdUnit.pas';

begin
  WriteLn(FaTotal, ' ', FbTotal, ' ', IcValue, ' ', IdValue);
end.