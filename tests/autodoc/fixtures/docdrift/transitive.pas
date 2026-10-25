unit transitive;

{ Fixture for run_doc_exception_transitive.ps1 -- the transitive <exception cref>
  rule (INBOX-exception-cref-transitive-raise).

  A routine whose body is a one-line delegation raises nothing ITSELF, so the
  ddExceptionNotRaised check reported its (correct) <exception cref> as drift.
  The fix walks resolved callees up to THREE hops deep and mines their raises.

  The two RED decls below must stop reporting after the fix. The four CONTROL
  decls must KEEP reporting -- they are what fails if anyone re-implements this
  as the cheap "has calls but raises nothing -> skip" carve-out, which would
  silence the rule almost everywhere. }

interface

uses
  System.SysUtils;

type
  EBoom  = class(Exception);
  ENever = class(Exception);
  EFoo   = class(Exception);

/// <summary>RED-A: singular overload; one-line delegation to the array overload.
/// The call edge is AMBIGUOUS because both overloads share a qualified name.</summary>
/// <param name="AItem">The single item to pass through.</param>
/// <exception cref="EBoom">Raised by the array overload it delegates to.</exception>
procedure Go(const AItem: string); overload;

/// <summary>RED-A: the array overload -- this one really does raise.</summary>
/// <param name="AItems">Items; empty is rejected.</param>
/// <exception cref="EBoom">Raised when AItems is empty.</exception>
procedure Go(const AItems: TArray<string>); overload;

/// <summary>RED-B: delegates to a private helper that raises. The edge is CERTAIN.</summary>
/// <exception cref="EBoom">Raised by the helper.</exception>
procedure ViaHelper;

/// <summary>CONTROL-1: documents a class that NOTHING in the chain raises.
/// Must keep reporting -- this is the assertion that fails if the rule is
/// weakened to "calls something, raises nothing itself".</summary>
/// <exception cref="ENever">Never raised anywhere in this unit.</exception>
procedure StillWrong;

/// <summary>CONTROL-2: cref names the ANCESTOR while the callee raises a
/// descendant. Exact-name matching must be preserved, so it keeps reporting.</summary>
/// <exception cref="Exception">Ancestor of what is actually raised.</exception>
procedure AncestorCref;

/// <summary>CONTROL-3: the only callee is RTL and unresolved in the scratch DB.
/// Absence of information must never suppress -- it keeps reporting.</summary>
/// <param name="AValue">Value to render.</param>
/// <returns>AValue as text.</returns>
/// <exception cref="EFoo">Nothing here raises it.</exception>
function Unresolved(AValue: Integer): string;

/// <summary>RED-C: the raise is TWO hops away. Within the three-hop bound, so it no
/// longer reports.</summary>
/// <exception cref="EBoom">Two levels down.</exception>
procedure TwoHops;

/// <summary>RED-D: the raise is THREE hops away -- exactly the bound.</summary>
/// <exception cref="EBoom">Three levels down.</exception>
procedure ThreeHops;

/// <summary>CONTROL-4: the raise is FOUR hops away, beyond the three-hop bound, so
/// this keeps reporting.</summary>
/// <exception cref="EBoom">Four levels down, beyond the bound.</exception>
procedure FourHops;

/// <summary>CONTROL-5: a call cycle in which nothing raises. The walk must terminate
/// and keep reporting.</summary>
/// <exception cref="ENever">Nothing in the cycle raises it.</exception>
procedure Ping;

implementation

procedure HelperRaise;
begin
  raise EBoom.Create('boom');
end;

procedure Go(const AItems: TArray<string>);
begin
  if Length(AItems) = 0 then
    raise EBoom.Create('empty');
end;

procedure Go(const AItem: string);
begin
  Go([AItem]);
end;

procedure ViaHelper;
begin
  HelperRaise;
end;

procedure StillWrong;
begin
  HelperRaise;
end;

procedure AncestorCref;
begin
  HelperRaise;
end;

function Unresolved(AValue: Integer): string;
begin
  Result:= IntToStr(AValue);
end;

procedure MidHop;
begin
  HelperRaise;
end;

procedure TwoHops;
begin
  MidHop;
end;

procedure Hop3;
begin
  MidHop;
end;

procedure ThreeHops;
begin
  Hop3;
end;

procedure Hop4;
begin
  Hop3;
end;

procedure FourHops;
begin
  Hop4;
end;

procedure Pong; forward;

procedure Ping;
begin
  Pong;
end;

procedure Pong;
begin
  Ping;
end;

end.
