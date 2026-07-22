unit owner;

// Fixture for Auto-Document Phase 2 Task 8 (Returned-object ownership fact --
// see DRagLint.Doc.SymbolFacts.AnalyzeReturnsOwner). TFoo's methods exercise
// the analysis' documented classification + gates:
//   * MakeIt         -- Result := TFoo.Create (paren-less constructor call) --
//                       the ONE unanimous 'new' site -> 'Owns returned: new
//                       (caller owns)'.
//   * GetIt          -- Result := FFoo (FFoo, an own-class field of type
//                       TFoo) -- the ONE unanimous 'borrowed' site, object-
//                       type gate passes (TFoo resolves to a class in this
//                       same unit) -> 'Owns returned: borrowed'.
//   * Me             -- Result := Self as TFoo -- the ONE unanimous 'self'
//                       site, object-type gate passes -> 'Owns returned:
//                       self'.
//   * Amb            -- one site 'new' (TFoo.Create) + one site 'borrowed'
//                       (FFoo) on the if/else branches -- NOT unanimous ->
//                       NO 'Owns returned:' line at all (ABSENCE over a
//                       guessed verdict -- the task's governing principle).
//                       Still gets a managed block via the unrelated Reads:
//                       FFoo fact (from the else branch), so this proves the
//                       OMISSION specifically, not merely "no block at all".
//   * Count          -- Result := FCount, but the function's OWN return type
//                       is Integer (a value type, not a reference type) --
//                       the site classifies 'borrowed' (FCount IS an
//                       own-class field) but the OBJECT-TYPE GATE (task
//                       brief step 5) rejects it -> NO 'Owns returned:' line.
//                       Gets a managed block via the unrelated Reads: FCount
//                       fact.
//   * MakeViaExit    -- Exit(TFoo.Create) -- the value-form Exit(...) site
//                       kind (distinct from a Result:= assignment) ->
//                       'Owns returned: new (caller owns)'. Proves Exit()
//                       sites are collected, not just Result:= ones.
//   * DisposedResult -- Result := TFoo.Create (an otherwise-unanimous 'new'
//                       site) immediately followed by Result.Free -- the
//                       DISPOSAL check (task brief step 2) must suppress the
//                       fact entirely, even though the lone site alone would
//                       otherwise read as a clean 'new'. An unrelated
//                       'FCount := FCount + 1' statement gives this method
//                       its own Reads/Writes fact (so it still gets a
//                       managed block -- proving the OMISSION, not just
//                       absence of any block).
//
// ORDERING/BLOCK-INVARIANT NOTE: every method above ends up with SOME
// managed block once Task 8 ships (either the Owns-returned fact itself, or
// the pre-existing Reads/Writes-fields fact for Amb/Count/DisposedResult) --
// there is deliberately NO fully fact-less declaration anywhere in this
// fixture. This sidesteps a PRE-EXISTING, unrelated 'document --apply'
// merge-engine bug (see fixtures\docp2\sql.pas's own "ORDERING NOTE" for the
// full diagnosis, carried from Task 7): a declaration's managed block
// COLLAPSES to a bare empty '<summary></summary>' stub on a 2nd apply only
// when the declaration immediately AFTER it has NO block of its own
// (fact->no-fact adjacency) -- since no declaration here is ever fact-less,
// that adjacency never occurs, regardless of method order. The test harness
// additionally scopes its idempotency assertion to each method's OWN 'Owns
// returned:' segment (not a whole-file byte comparison) as a second,
// independent safeguard, per the task's own instructions -- this task does
// NOT attempt to fix that unrelated bug.

interface

type
  TFoo = class
  private
    FFoo  : TFoo;
    FCount: Integer;
  public
    function MakeIt: TFoo;
    function GetIt: TFoo;
    function Me: TFoo;
    function Amb(AFlag: Boolean): TFoo;
    function Count: Integer;
    function MakeViaExit: TFoo;
    function DisposedResult: TFoo;
  end;

implementation

function TFoo.MakeIt: TFoo;
begin
  Result := TFoo.Create;
end;

function TFoo.GetIt: TFoo;
begin
  Result := FFoo;
end;

function TFoo.Me: TFoo;
begin
  Result := Self as TFoo;
end;

function TFoo.Amb(AFlag: Boolean): TFoo;
begin
  if AFlag then
  begin
    Result := TFoo.Create;
  end
  else
  begin
    Result := FFoo;
  end;
end;

function TFoo.Count: Integer;
begin
  Result := FCount;
end;

function TFoo.MakeViaExit: TFoo;
begin
  Exit(TFoo.Create);
end;

function TFoo.DisposedResult: TFoo;
begin
  Result := TFoo.Create;
  Result.Free;
  FCount := FCount + 1;
end;

end.
