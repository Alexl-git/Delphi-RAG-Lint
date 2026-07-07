unit DRagLint.Lint.DocRules;

{ Report-only lint rules over the DocInsight doc-comment layer (ADF milestone).
  Both rules read the whole symbol/doc graph via ISymbolStore rather than a
  single file's AST -- the store-backed complement to the per-file `lint`
  command, run only where a store is open (`lint-all` / `lint-project`).

  missing-doc (Task 7, ships ON by default) flags a public/published
  declaration with NO doc-comment at all. doc-drift (Task 8, also ON by default)
  owns the complementary "your doc is stale" case -- a declaration that already
  HAS a doc-comment (including a drag-lint managed TODO stub) is "documented" for
  missing-doc's purposes and is never double-reported here; doc-drift instead
  diffs that existing doc against the live signature/body facts.

  doc-drift is ALSO --fix-capable, but only for its mechanically-safe subset
  (the FIXABLE signals of TDocDrift.Analyze: ddParamMissing / ddValueButNoReturns
  / ddFactsBlockStale). The fix is produced by TDocumenter.BuildFor, whose merge
  refreshes the managed facts block AND adds missing <param>/<returns> stubs while
  PRESERVING all hand-written prose (a renamed <param> is kept + flagged, never
  deleted). Report-only signals (renamed/removed param, spurious <returns>,
  never-raised <exception>, ...) emit NO edit -- a human decides. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Refactor.TextEdit
  ;

type
  /// <summary>Doc-comment-aware lint rules (missing-doc + doc-drift).</summary>
  /// <remarks>Stateless; reads the supplied open store. Never raises.</remarks>
  TDocLintRules = class
  public
    /// <summary>Flags every public/published declaration in AStore that has
    /// no doc-comment of any kind.</summary>
    /// <param name="AStore">An open, migrated symbol store; nil yields no findings.</param>
    /// <returns>'missing-doc' findings, one per undocumented public/published
    /// declaration; empty if none.</returns>
    /// <remarks>Backed by ISymbolStore.FindUndocumented(kind, PublicOnly:=True),
    /// which already excludes private/protected members (public-surface-only,
    /// per the CDD scope rule) AND excludes any declaration that has a
    /// symbol_docs row -- including a drag-lint managed "TODO: describe." stub,
    /// which counts as "documented" here (doc-drift owns stale-stub reporting,
    /// so the two rules never double-report the same declaration). Restricted
    /// to the kinds CDD requires doc-comments on: types (class/interface/
    /// record/enum), routines (procedure/function/method/constructor/
    /// destructor), and properties. Never raises.</remarks>
    class function RunMissingDoc(const AStore: ISymbolStore): TArray<TLintFinding>;

    /// <summary>Reports deterministic doc-vs-code drift for every DOCUMENTED
    /// public/published declaration in AStore -- one 'doc-drift' finding per
    /// TDocDrift signal (renamed/removed param, missing param, spurious/absent
    /// &lt;returns&gt;, never-raised &lt;exception&gt;, stale facts block, ...).</summary>
    /// <param name="AStore">An open, migrated symbol store; nil yields no findings.</param>
    /// <returns>'doc-drift' findings, in stable per-symbol/per-signal order; empty
    /// if every documented decl is structurally current.</returns>
    /// <remarks>Store-backed (needs the symbol/doc graph + Raises facts), so it
    /// runs only on the store-backed lint-all/lint-project path -- never the bare
    /// per-file `lint`. Each finding's Message is the signal's Detail; its severity
    /// is 'warning'. The fixable subset is applied via FixEditsForDocDrift, NOT by
    /// re-parsing the message: a finding is merely a report here. Never raises;
    /// per-symbol failures are swallowed so one bad decl cannot abort the sweep.</remarks>
    class function RunDocDrift(const AStore: ISymbolStore): TArray<TLintFinding>;

    /// <summary>Builds the MergeComment-based text edits that repair the
    /// mechanically-safe subset of doc-drift on AStore's documented public decls.
    /// For each such decl that carries at least one FIXABLE drift signal, delegates
    /// to TDocumenter.BuildFor to regenerate the managed facts block and add any
    /// missing &lt;param&gt;/&lt;returns&gt; stubs -- ONCE per declaration, no
    /// matter how many fixable signals it has.</summary>
    /// <param name="AStore">An open, migrated symbol store; nil yields no edits.</param>
    /// <returns>The repair edits (a delete+insert pair per repaired doc span);
    /// empty when nothing fixable drifted.</returns>
    /// <remarks>NEVER rewrites hand-written prose: BuildFor's MergeComment preserves
    /// Summary/Remarks prose and hand-typed param descriptions, adds managed
    /// param/returns stubs, and merely FLAGS a hand-typed param no longer in the
    /// signature (keeps its prose + appends a "param no longer exists" comment).
    /// Report-only signals contribute no edit. Idempotent: on an already-repaired
    /// doc BuildFor returns daUnchanged (no edits), so a second --fix is a no-op.
    /// Never raises; per-symbol failures are swallowed.</remarks>
    class function FixEditsForDocDrift(const AStore: ISymbolStore): TArray<TTextEdit>;

    /// <summary>Builds the DocInsight comment insert edits for a set of TARGETED
    /// missing-doc findings -- the SINGLE-FIX "Fix it" on an undocumented public
    /// decl. For each finding, resolves the symbol by (file, start-line) and
    /// delegates to TDocumenter.BuildFor to generate the exact comment
    /// `document --qname` produces (summary/param/returns skeleton + managed facts
    /// block), then aggregates every finding's Edits.</summary>
    /// <param name="AStore">An open, migrated symbol store; nil yields no edits.</param>
    /// <param name="ATargeted">The already-narrowed missing-doc findings to fix
    /// (each carries FilePath + StartLine; a non-missing-doc finding is ignored).</param>
    /// <returns>The insert edits (one span per resolved decl); empty when nothing
    /// resolves.</returns>
    /// <remarks>SINGLE-FIX-ONLY: the caller (FinalizeAndOutput) invokes this only
    /// on a targeted single-fix (--fix-line/--fix-rule), NEVER the blanket batch --
    /// batch-documenting a whole project is `document --project`'s job. missing-doc
    /// findings carry no qname, so the symbol is re-resolved here via
    /// AStore.FindSymbolsByFile matched on StartLine. Idempotent: a decl that
    /// already has a doc yields daUnchanged (no edits) -- but such a decl no longer
    /// produces a missing-doc finding either. Never raises; per-finding failures are
    /// swallowed so one bad decl cannot abort the fix.</remarks>
    class function FixEditsForMissingDoc(const AStore: ISymbolStore; const ATargeted: TArray<TLintFinding>): TArray<TTextEdit>;
  end;

implementation

uses
  DRagLint.Doc.Drift, DRagLint.Doc.Document;

{ Kinds CDD/DocInsight applies to: public/published types + routines +
  properties. Excludes containers (unit/program/package), fields (CDD scopes
  doc-comments to the public API surface -- a field is usually documented via
  its owning property or class remarks), locals/params, and the SQL/DFM/init
  markers that FindUndocumented would otherwise also return under kind=''. }
const
  DOCUMENTABLE_KINDS: array[0..10] of TSymbolKind = (
    skClass, skInterface, skRecord, skEnum,
    skProcedure, skFunction, skMethod, skConstructor, skDestructor,
    skProperty, skTypeAlias
  );

function IsDocumentableKind(AKind: TSymbolKind): Boolean;
var
  K: TSymbolKind;
begin
  Result:= False;
  for K in DOCUMENTABLE_KINDS do
    if K = AKind then Exit(True);
end;

{ Public-surface test mirroring FindUndocumented's publicOnly SQL: a symbol is
  public when its modifiers carry neither 'private' nor 'protected'. Keeps
  doc-drift scoped to the same public API surface as missing-doc (CDD rule). }
function IsPublicSymbol(const ASym: TSymbol): Boolean;
var
  M: string;
begin
  M:= LowerCase(ASym.Modifiers);
  Result:= (Pos('private', M) = 0) and (Pos('protected', M) = 0);
end;

class function TDocLintRules.RunMissingDoc(const AStore: ISymbolStore): TArray<TLintFinding>;
var
  Findings: TList<TLintFinding>;
  Syms    : TArray<TSymbol>    ;
  Sym     : TSymbol            ;
  F       : TLintFinding        ;
begin
  Result:= nil;
  if AStore = nil then Exit;
  Findings:= TList<TLintFinding>.Create;
  try
    { kind='' -> every kind; filter down to the documentable subset below so we
      don't ask CDD questions of fields/locals/units/SQL-DDL symbols. }
    Syms:= AStore.FindUndocumented('', True);
    for Sym in Syms do
    begin
      if not IsDocumentableKind(Sym.Kind) then Continue;
      F:= Default(TLintFinding);
      F.RuleId  := 'missing-doc';
      F.Severity:= 'warning';
      F.Message := Format('Public declaration ''%s'' has no DocInsight doc-comment', [Sym.Name]);
      F.FilePath:= AStore.GetFilePath(Sym.FileId);
      F.StartLine:= Sym.StartLine;
      F.StartCol := Sym.StartCol;
      F.EndLine  := Sym.StartLine;
      F.EndCol   := Sym.StartCol + Length(Sym.Name);
      Findings.Add(F);
    end;
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end;

{ The documented public documentable decls doc-drift operates on: every symbol
  the index has a doc for (symbol_docs.summary), narrowed to the public API
  surface and the CDD-documentable kinds. Shared by RunDocDrift (report) and
  FixEditsForDocDrift (repair) so both iterate exactly the same population. }
function DocumentedPublicDecls(const AStore: ISymbolStore): TArray<TSymbol>;
var
  Acc: TList<TSymbol>;
  Sym: TSymbol       ;
begin
  Acc:= TList<TSymbol>.Create;
  try
    for Sym in AStore.ListDocumentedSymbols(MaxInt) do
      if IsDocumentableKind(Sym.Kind) and IsPublicSymbol(Sym) then Acc.Add(Sym);
    Result:= Acc.ToArray;
  finally
    Acc.Free;
  end;
end;

class function TDocLintRules.RunDocDrift(const AStore: ISymbolStore): TArray<TLintFinding>;
var
  Findings: TList<TLintFinding> ;
  Sym     : TSymbol             ;
  Live    : TParsedDoc          ;
  ResSym  : TSymbol             ;
  Found   : Boolean             ;
  HasDoc  : Boolean             ;
  Drifts  : TArray<TDocDriftFinding>;
  D       : TDocDriftFinding    ;
  F       : TLintFinding         ;
begin
  Result:= nil;
  if AStore = nil then Exit;
  Findings:= TList<TLintFinding>.Create;
  try
    for Sym in DocumentedPublicDecls(AStore) do
    begin
      try
        { Re-scan the on-disk doc (the live comment above the decl, not the
          indexed snapshot) so drift is diffed against the actual source. Skip
          decls whose live comment cannot be re-anchored -- there is nothing to
          diff there. }
        Live:= TDocumenter.ExistingDocFor(AStore, Sym.QualifiedName, ResSym, Found, HasDoc);
        if (not Found) or (not HasDoc) then Continue;

        Drifts:= TDocDrift.Analyze(AStore, ResSym, Live);
        for D in Drifts do
        begin
          F:= Default(TLintFinding);
          F.RuleId  := 'doc-drift';
          F.Severity:= 'warning';
          F.Message := D.Detail;
          F.FilePath:= AStore.GetFilePath(ResSym.FileId);
          F.StartLine:= D.Line;
          F.StartCol := ResSym.StartCol;
          F.EndLine  := D.Line;
          F.EndCol   := ResSym.StartCol + Length(ResSym.Name);
          Findings.Add(F);
        end;
      except
        { A single malformed decl must not abort the whole sweep. }
      end;
    end;
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end;

class function TDocLintRules.FixEditsForDocDrift(const AStore: ISymbolStore): TArray<TTextEdit>;
var
  Edits   : TList<TTextEdit>    ;
  Sym     : TSymbol             ;
  Live    : TParsedDoc          ;
  ResSym  : TSymbol             ;
  Found   : Boolean             ;
  HasDoc  : Boolean             ;
  Drifts  : TArray<TDocDriftFinding>;
  D       : TDocDriftFinding    ;
  AnyFix  : Boolean             ;
  DocRes  : TDocumentResult     ;
  E       : TTextEdit           ;
begin
  Result:= nil;
  if AStore = nil then Exit;
  Edits:= TList<TTextEdit>.Create;
  try
    for Sym in DocumentedPublicDecls(AStore) do
    begin
      try
        Live:= TDocumenter.ExistingDocFor(AStore, Sym.QualifiedName, ResSym, Found, HasDoc);
        if (not Found) or (not HasDoc) then Continue;

        { Only repair a decl that actually carries a FIXABLE drift signal --
          report-only drift (renamed param, spurious <returns>, never-raised
          <exception>, ...) produces NO edit; a human decides on those. }
        Drifts:= TDocDrift.Analyze(AStore, ResSym, Live);
        AnyFix:= False;
        for D in Drifts do
          if D.Fixable then begin AnyFix:= True; Break; end;
        if not AnyFix then Continue;

        { One BuildFor per decl regenerates the WHOLE managed comment via
          MergeComment (refresh facts block + add missing <param>/<returns>
          stubs, hand prose preserved), so multiple fixable signals on the same
          decl collapse into a single delete+insert edit pair -- no overlapping
          edits over one doc span. daUnchanged (already current) yields no edits,
          which is what makes a second --fix a no-op. }
        DocRes:= TDocumenter.BuildFor(AStore, ResSym.QualifiedName);
        for E in DocRes.Edits do Edits.Add(E);
      except
        { A single malformed decl must not abort the whole fix sweep. }
      end;
    end;
    Result:= Edits.ToArray;
  finally
    Edits.Free;
  end;
end;

class function TDocLintRules.FixEditsForMissingDoc(const AStore: ISymbolStore; const ATargeted: TArray<TLintFinding>): TArray<TTextEdit>;
var
  Edits : TList<TTextEdit>;
  F     : TLintFinding    ;
  Syms  : TArray<TSymbol> ;
  Sym   : TSymbol         ;
  QName : string          ;
  DocRes: TDocumentResult ;
  E     : TTextEdit       ;
  Seen  : TDictionary<string, Boolean>;
begin
  Result:= nil;
  if AStore = nil then Exit;
  Edits:= TList<TTextEdit>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for F in ATargeted do
    begin
      if not SameText(F.RuleId, 'missing-doc') then Continue;
      try
        { missing-doc findings carry no qname -- re-resolve the symbol from the
          store by (file, start-line): FindSymbolsByFile returns every symbol
          declared in the file; pick the one whose StartLine matches the finding
          (the decl RunMissingDoc anchored to), then use its QualifiedName. }
        QName:= '';
        Syms := AStore.FindSymbolsByFile(F.FilePath);
        for Sym in Syms do
          if Sym.StartLine = F.StartLine then begin QName:= Sym.QualifiedName; Break; end;
        if QName = '' then Continue;
        { Two findings could resolve to the same decl (defensive) -- BuildFor once
          per decl so we never emit overlapping insert edits for one span. }
        if Seen.ContainsKey(LowerCase(QName)) then Continue;
        Seen.Add(LowerCase(QName), True);

        DocRes:= TDocumenter.BuildFor(AStore, QName);
        for E in DocRes.Edits do Edits.Add(E);
      except
        { A single malformed decl must not abort the whole fix sweep. }
      end;
    end;
    Result:= Edits.ToArray;
  finally
    Seen.Free;
    Edits.Free;
  end;
end;

end.
