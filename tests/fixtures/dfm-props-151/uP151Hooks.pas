unit uP151Hooks;
interface
type
  THelpHookProc = procedure;
var
  HelpHook : THelpHookProc;
  Help2Hook: THelpHookProc;
implementation
uses uP151Help, uP151Help2;

procedure ShowHelp;
begin
  TfrmP151Help.Create(nil).ShowModal;
end;

procedure ShowHelp2;
begin
  TfrmP151Help2.Create(nil).ShowModal;
end;

initialization
  HelpHook := ShowHelp;
  Help2Hook := ShowHelp2;
end.