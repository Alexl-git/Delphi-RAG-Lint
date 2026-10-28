unit transitive_caught;

{ Fixture for run_doc_exception_transitive_caught.ps1 -- a one-hop callee raise
  that the CALLER CATCHES must not become an <exception cref> on the caller
  (INBOX-2026-09-29-engine-followups-from-1.20.4 #5: the false
  <exception cref="EManifestError"> on TManifestIO.Load, whose ParseTextEx
  call sits inside `try .. except on E: Exception do NoteLoadError(..) end`).

  Every declaration is UNDOCUMENTED on purpose: the writer preserves a
  hand-written cref verbatim, so only an undocumented routine can show what
  the writer itself decides. The positive controls (CatchOther, CatchReraise,
  CallInHandler, CallOutside, FinallyOnly, Mixed) must KEEP their via tag, so
  the fix cannot pass by dropping every callee raise. }

interface

uses
  System.SysUtils;

type
  EBoom  = class(Exception);
  EOther = class(Exception);

procedure Raiser;

{ catch-all `on E: Exception` that swallows -> no cref }
procedure CatchAll;
{ bare `except` block that swallows -> no cref }
procedure CatchBare;
{ `on EBoom` -- the exact class -> no cref }
procedure CatchExact;
{ the call is in an inner try-finally inside a swallowing try-except -> no cref }
procedure CatchNested;
{ `else` arm catches everything -> no cref }
procedure CatchElse;

{ POSITIVE: the handler catches another class -> cref EBoom }
procedure CatchOther;
{ POSITIVE: the handler re-raises -> cref EBoom }
procedure CatchReraise;
{ POSITIVE: the call is IN the handler, not in the protected part -> cref EBoom }
procedure CallInHandler;
{ POSITIVE: the call is after the try block -> cref EBoom }
procedure CallOutside;
{ POSITIVE: try-finally protects nothing -> cref EBoom }
procedure FinallyOnly;
{ POSITIVE: one guarded call and one unguarded -> cref EBoom }
procedure Mixed;

implementation

procedure Log(const S: string);
begin
  if S = '' then Exit;
end;

procedure Raiser;
begin
  raise EBoom.Create('boom');
end;

procedure CatchAll;
begin
  try
    Raiser;
  except
    on E: Exception do Log(E.Message);
  end;
end;

procedure CatchBare;
begin
  try
    Raiser;
  except
    Log('x');
  end;
end;

procedure CatchExact;
begin
  try
    Raiser;
  except
    on EBoom do Log('boom');
  end;
end;

procedure CatchNested;
begin
  try
    try
      Raiser;
    finally
      Log('f');
    end;
  except
    on E: Exception do Log(E.Message);
  end;
end;

procedure CatchElse;
begin
  try
    Raiser;
  except
    on E: EOther do Log(E.Message);
  else
    Log('else');
  end;
end;

procedure CatchOther;
begin
  try
    Raiser;
  except
    on E: EOther do Log(E.Message);
  end;
end;

procedure CatchReraise;
begin
  try
    Raiser;
  except
    on E: Exception do
    begin
      Log(E.Message);
      raise;
    end;
  end;
end;

procedure CallInHandler;
begin
  try
    Log('x');
  except
    on E: Exception do Raiser;
  end;
end;

procedure CallOutside;
begin
  try
    Log('x');
  except
    on E: Exception do Log(E.Message);
  end;
  Raiser;
end;

procedure FinallyOnly;
begin
  try
    Raiser;
  finally
    Log('f');
  end;
end;

procedure Mixed;
begin
  try
    Raiser;
  except
    on E: Exception do Log(E.Message);
  end;
  Raiser;
end;

end.
