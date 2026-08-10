unit object_leak_refcounted;

{ Fixture for the 2026-08-10 object-leak narrowing.

  A 12-finding sample of this rule on drag-lint's own source found ZERO real
  leaks. The two dominant shapes are not "a free the analysis missed" -- they
  are constructs where a leak is IMPOSSIBLE, so no control-flow improvement
  could ever clear them and the finding was unfalsifiable:

    * a RECORD constructor (TRegEx) -- nothing is heap-allocated
    * an INTERFACE variable          -- reference-counted; a manual Free is the bug

  The CONTROL at the bottom is the load-bearing half: a plain class with no
  try-finally must STILL be reported, or this narrowing has just disabled the
  rule. }

interface

uses
  System.RegularExpressions;

type
  IThing = interface
    procedure Run;
  end;

  TThing = class(TInterfacedObject, IThing)
    procedure Run;
  end;

  TPlain = class
    procedure Go;
  end;

procedure UsesRecord;
procedure UsesInterface;
procedure ActuallyLeaks;
procedure ProperlyFreed;

implementation

procedure TThing.Run; begin end;
procedure TPlain.Go;  begin end;

{ A record constructor. There is no Free for TRegEx and never was. }
procedure UsesRecord;
var
  Rx: TRegEx;
begin
  Rx:= TRegEx.Create('\bCREATE\s+TABLE\b', [roIgnoreCase]);
  if Rx.IsMatch('create table x') then Exit;
end;

{ Reference-counted. Freeing it manually would be the defect. }
procedure UsesInterface;
var
  Thing: IThing;
begin
  Thing:= TThing.Create;
  Thing.Run;
end;

{ CONTROL -- a genuine leak: a class, created, never freed on any path.
  If this stops firing, the narrowing has gone too far and the rule is dead. }
procedure ActuallyLeaks;
var
  P: TPlain;
begin
  P:= TPlain.Create;
  P.Go;
end;

{ CONTROL -- the same class, correctly freed. Must stay silent. }
procedure ProperlyFreed;
var
  P: TPlain;
begin
  P:= TPlain.Create;
  try
    P.Go;
  finally
    P.Free;
  end;
end;

end.
