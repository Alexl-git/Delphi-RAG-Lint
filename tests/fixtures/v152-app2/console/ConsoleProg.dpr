program ConsoleProg;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, UDialogs, UQuiet;

begin
  Hello;
  ShowDone;
  WrapDone('x');
  UDialogs.ShowDone;
end.
