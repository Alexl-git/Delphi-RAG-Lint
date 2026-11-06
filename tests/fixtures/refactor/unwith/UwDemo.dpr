program UwDemo;

{$APPTYPE CONSOLE}

uses
  UwTypes in 'UwTypes.pas',
  UwCases in 'UwCases.pas',
  UwRefused in 'UwRefused.pas';

begin
  RunCases;
  RunRefused;
end.