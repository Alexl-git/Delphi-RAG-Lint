program SolveIndirect;

{ check-init fixture solve-indirect (lane HBSOLVER): UseViaHook runs only through the procedural variable
  GHook (address taken: an escaped routine); UseDirect is called after SetBoth (the SET twin). }

uses
  sdHooks in 'sdHooks.pas';

begin
  SetBoth;
  GHook:= UseViaHook;
  GHook;
  UseDirect;
end.
