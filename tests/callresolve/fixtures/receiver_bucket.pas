unit receiver_bucket;

{ v20 fixture: the RECEIVER decides who a same-named call belongs to.

  TOnlyOnce.Create is constructed in EXACTLY TWO places (MakeOne, MakeQualified).
  The three Noise routines each call `Create` on a type this DB does NOT declare
  -- the ordinary case for RTL / DevExpress / Spring construction, where the
  receiver's type lives in the library index or is not indexed at all. Those refs
  cannot resolve, so they fall into the leaf-name bucket keyed on 'Create'.

  WHY THIS REPRODUCES THE FABRICATION even though the leaf name is UNIQUE here:
  the bucket's ambiguity gate has a deliberate escape -- `Distinct.Count > 0`,
  meaning "at least one caller resolved, so the list is MIXED and the ' ?' marker
  will warn the reader". The real callers supply that resolved edge, the escape
  opens, and all three unrelated sites are added. That is precisely how
  TQueryRule.Create -- constructed in one place -- came to be documented with 77
  callers on this repo.

  With refs.receiver_text the bucket can see that `TUnknownA.Create` was not
  written against TOnlyOnce and drop it outright: not capped, not marked
  uncertain, just correctly absent.

  EVERY CALL HERE IS PARENTHESISED, and that is load-bearing rather than
  stylistic. A paren-less `TFoo.Create;` is indexed as kind 'member-access', not
  'call', so it never enters ResolveCallTargets (which filters on
  CallSiteRefKindSql = kind 'call') and never reaches this bucket at all. An
  earlier draft used paren-less calls and produced nothing to test -- see
  docs/INBOX-parenless-constructor-call-is-member-access.md.

  ALSO PINNED, because it is a receiver shape the filter must not get wrong:
  MakeQualified writes receiver_bucket.TOnlyOnce.Create(...), a FULL DOTTED
  CHAIN. The filter must match it on its LAST SEGMENT and let it SURVIVE;
  comparing the whole receiver string would wrongly reject a real caller. }

interface

type
  TOnlyOnce = class
  public
    constructor Create(AValue: Integer);
    procedure Touch;
  end;

function MakeOne: TOnlyOnce;
function MakeQualified: TOnlyOnce;
procedure NoiseA;
procedure NoiseB;
procedure NoiseC;

implementation

constructor TOnlyOnce.Create(AValue: Integer);
begin
  inherited Create;
end;

procedure TOnlyOnce.Touch;
begin
end;

{ THE REAL CALLERS -- one plain, one fully qualified. }
function MakeOne: TOnlyOnce;
begin
  Result := TOnlyOnce.Create(1);
end;

function MakeQualified: TOnlyOnce;
begin
  Result := receiver_bucket.TOnlyOnce.Create(2);
end;

{ Noise: the SAME leaf name 'Create', written against types this DB does not
  declare, so each ref is unresolvable and lands in the leaf-name bucket. }
procedure NoiseA;
begin
  TUnknownA.Create(3);
end;

procedure NoiseB;
begin
  TUnknownB.Create(4);
end;

procedure NoiseC;
begin
  TUnknownC.Create(5);
end;

end.
