unit Echo.Client;

// FIXTURE for run_doc_fact_terminator.ps1. The unit NAME is load-bearing:
// 'Echo' sorts before 'Zed' by FILE, while the qualified caller name
// 'Echo.Client.Note' sorts AFTER 'declaration'. A fixture whose two orders
// agree proves nothing about canonical ordering.
//
// Gamma's hand-written doc-comment below is the ONLY prose in this fixture that
// mentions an inbound label. That is deliberate -- it is the D4 case. Do not add
// another, and do not put a comment directly above any other declaration here
// (see the banner in Zed.Types.pas for why a harvested summary masks D2).

interface

procedure Note;

/// <summary>Gamma does a thing.</summary>
/// <remarks>
/// <para>An INBOUND list (`Called from:`, `Used by:`, `Used in units:`) is prose.</para>
/// </remarks>
procedure Gamma;

procedure W1;
procedure W2;
procedure W3;
procedure W4;
procedure W5;
procedure W6;

implementation

uses
  Zed.Types;

procedure Gamma;
begin
end;

procedure W1; var V: TWide; begin V := Wide; V.Verdict := 1; end;
procedure W2; var V: TWide; begin V := Wide; V.Verdict := 2; end;
procedure W3; var V: TWide; begin V := Wide; V.Verdict := 3; end;
procedure W4; var V: TWide; begin V := Wide; V.Verdict := 4; end;
procedure W5; var V: TWide; begin V := Wide; V.Verdict := 5; end;
procedure W6; var V: TWide; begin V := Wide; V.Verdict := 6; end;

procedure Note;
var
  Rep: TRep;
  M: TMode;
  O: TOuter;
  V: TWide;
begin
  Rep := Probe(1);
  M := Mode(Rep.Verdict > 0);
  V := Wide;
  O := TOuter.Create;
  try
    O.Ping;
    if (M = mFast) and (V.Verdict = 0) then O.Pong;
  finally
    O.Free;
  end;
  Gamma;
  W1; W2; W3; W4; W5; W6;
end;

end.
