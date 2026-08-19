program GhostTextHarness;

{ Hosts DRagLint.Core.GhostText for run_ghost_text_endpoint_guard.ps1.

  The real host is the IDE plugin, in-process, because only the OTA knows which
  file and cursor a request is about. That makes the endpoint untestable in the
  place it actually runs -- so the transport lives in a pure unit with the
  completion source injected, and this harness supplies a KNOWN source instead
  of the OTA one. What gets verified over real HTTP is therefore the whole
  server: binding, request parsing, both response shapes, and the empty-answer
  default.

  Modes, chosen with --mode:

    empty     the provider always returns '' -- the honest default, and what
              every uncertain path in the real provider must also produce.
    candidate the provider returns a completion ONLY for a prompt ending in a
              known token, and '' for anything else. This is the shape of the
              real rule ("exactly one strong candidate in the index, or
              nothing"), so the guard can assert BOTH halves of it.

  --enabled 0 exercises the off switch: StartWhen must leave nothing listening. }

{$APPTYPE CONSOLE}

uses
    System.SysUtils
  , System.Classes
  , DRagLint.Core.GhostText in '..\..\..\..\src\core\DRagLint.Core.GhostText.pas'
  ;

const
  KNOWN_PREFIX = 'TSampleWorker.';
  KNOWN_ANSWER = 'Describe';

var
  Port    : Integer;
  Seconds : Integer;
  Mode    : string ;
  Enabled : Boolean;
  Server  : TGhostTextServer;
  Provider: TGhostCompletionFunc;
  I       : Integer;
  A       : string ;

begin
  Port   := 8765;
  Seconds:= 20;
  Mode   := 'empty';
  Enabled:= True;

  I:= 1;
  while I <= ParamCount do
  begin
    A:= ParamStr(I);
    if      (A = '--port'   ) and (I < ParamCount) then begin Inc(I); Port   := StrToIntDef(ParamStr(I), 8765); end
    else if (A = '--seconds') and (I < ParamCount) then begin Inc(I); Seconds:= StrToIntDef(ParamStr(I), 20  ); end
    else if (A = '--mode'   ) and (I < ParamCount) then begin Inc(I); Mode   := ParamStr(I); end
    else if (A = '--enabled') and (I < ParamCount) then begin Inc(I); Enabled:= ParamStr(I) <> '0'; end;
    Inc(I);
  end;

  if SameText(Mode, 'candidate') then
    Provider:=
      function(const APrompt, ASuffix: string): string
      begin
        { One strong candidate, or nothing. Never a guess: a prompt that does
          not end in something we recognise gets '' rather than a best effort. }
        if APrompt.EndsWith(KNOWN_PREFIX) then Result:= KNOWN_ANSWER
        else Result:= '';
      end
  else
    Provider:=
      function(const APrompt, ASuffix: string): string
      begin
        Result:= '';
      end;

  Server:= TGhostTextServer.StartWhen(Enabled, Port, Provider);
  try
    if Server <> nil then Writeln('LISTENING ', Server.Port)
    else Writeln('NOT LISTENING');
    Flush(Output);
    Sleep(Seconds * 1000);
  finally
    Server.Free;
  end;
end.
