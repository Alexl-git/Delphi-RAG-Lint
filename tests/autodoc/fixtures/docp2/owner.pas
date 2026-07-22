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
// FIX WAVE (Phase 2 T8 review) -- two adversarial additions locking in the
// reviewer-identified false-'new'-receiver and skRecord-rejection fixes (see
// DRagLint.Doc.SymbolFacts' own "FIX WAVE" banner paragraph for the full
// rationale):
//   * TWidgetPool.Create   -- a PLAIN (non-constructor) method that merely
//                             returns a shared field, NOT a fresh object --
//                             deliberately named 'Create' to exploit
//                             ExprIsConstructor's own member-name-only match.
//                             Gets 'Owns returned: borrowed' itself (FShared
//                             is TWidgetPool's own field; TWidget is a real
//                             class, so the object-type gate passes) -- not
//                             asserted on directly, just self-consistent.
//   * TUser.Borrow         -- calls 'Result := APool.Create;' where APool is
//                             an EXISTING INSTANCE (a parameter), not a bare
//                             type reference -- FIX 1's exact regression.
//                             WITHOUT the receiver gate this reads back as a
//                             false 'new' (APool.Create's own body merely
//                             returns FShared, never allocates -- a caller
//                             told to Free the result would double-free/
//                             free-what-it-does-not-own). Expected: NO 'Owns
//                             returned:' line. An unrelated 'FLastPool :=
//                             APool;' statement gives this method its own
//                             Writes: FLastPool fact (so it still gets a
//                             managed block -- proving the OMISSION, not
//                             just absence of any block).
//   * TRecHolder.GetRec    -- Result := FRec, FRec an own-class field of type
//                             TMyRec (a RECORD, i.e. value type) -- FIX 2's
//                             exact regression. The site classifies
//                             'borrowed' (FRec is a real field), but WITHOUT
//                             the skRecord rejection the object-type gate's
//                             T/I-prefix heuristic wrongly accepts 'TMyRec'
//                             (starts with 'T') as if it were a reference
//                             type. Expected: NO 'Owns returned:' line
//                             (still gets a managed block via the SAME
//                             statement's own unrelated Reads: FRec fact --
//                             proving the OMISSION, not just absence of any
//                             block, exactly like Count/FCount above).
//
// FINAL REVIEW FIX WAVE -- one adversarial addition locking in the
// reviewer-identified RTL-value-record fix (see DRagLint.Doc.SymbolFacts'
// IsReferenceTypeName header comment, "FIX (Phase 2 final review)"
// paragraph, for the full rationale):
//   * TWidget.GetBounds    -- Result := FBounds, FBounds an own-class field
//                             of type TRect. UNLIKE GetRec's TMyRec (a
//                             store-resolved skRecord, tier 1), TRect is
//                             deliberately NOT declared anywhere in this
//                             fixture -- no System.Types unit is indexed by
//                             this isolated test -- so it is UNRESOLVED,
//                             exercising IsReferenceTypeName's TIER-2 T/I-
//                             prefix FALLBACK path instead. The site
//                             classifies 'borrowed' (FBounds is a real own-
//                             class field), but WITHOUT TRect in the
//                             fallback's exclusion list, the bare 'T'-prefix
//                             heuristic wrongly accepted it as a reference
//                             type ('Owns returned: borrowed' for a copy-by-
//                             value record). Expected: NO 'Owns returned:'
//                             line (still gets a managed block via the SAME
//                             statement's own unrelated Reads: FBounds fact
//                             -- proving the OMISSION, not just absence of
//                             any block, exactly like GetRec above).
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

  TWidget = class
  private
    FBounds: TRect;
  public
    function GetBounds: TRect;
  end;

  TWidgetPool = class
  private
    FShared: TWidget;
  public
    function Create: TWidget;
  end;

  TUser = class
  private
    FLastPool: TWidgetPool;
  public
    function Borrow(APool: TWidgetPool): TWidget;
  end;

  TMyRec = record
    X, Y: Integer;
  end;

  TRecHolder = class
  private
    FRec: TMyRec;
  public
    function GetRec: TMyRec;
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

function TWidget.GetBounds: TRect;
begin
  Result := FBounds;
end;

function TWidgetPool.Create: TWidget;
begin
  Result := FShared;
end;

function TUser.Borrow(APool: TWidgetPool): TWidget;
begin
  Result := APool.Create;
  FLastPool := APool;
end;

function TRecHolder.GetRec: TMyRec;
begin
  Result := FRec;
end;

end.
