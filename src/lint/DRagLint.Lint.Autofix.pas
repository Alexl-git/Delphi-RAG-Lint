unit DRagLint.Lint.Autofix;

{ The autofix registry: which lint rules carry a fix, which of those fixes are
  opt-in, risky or single-fix-only, and the builder that turns findings into
  TTextEdit records. Moved verbatim out of DRagLint.CLI (autofix wave lane A0,
  2026-10-27) so a lane that adds a fix never edits CLI.pas: the CLI keeps only
  the call sites. }

interface

uses
  System.Classes
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Refactor.TextEdit
  ;

const
  /// <summary>Why a fix was declined whole (lane IATOM): `--fix --json`
  /// decline_reason and the text summary's "N declined (...)".</summary>
  DECLINE_STALE_REASON = 'an edit of the fix no longer matches the file';

type
  /// <summary>A per-FINDING fixer: the edits that fix AFinding.</summary>
  /// <remarks>ALines is the finding's file as the builder read it (shared,
  /// cached per file -- never free or modify it). Return no edits to decline
  /// (the finding then counts as not fixed). Set ExpectText on every edit so a
  /// file that changed under the finding is skipped, not corrupted.</remarks>
  TFindingFixer = reference to function(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;

  /// <summary>A per-FILE fixer: the edits for every finding of its rule in APath
  /// (the unused-local shape -- several findings share one edit).</summary>
  /// <remarks>AFindings is the whole batch; the fixer picks its own rule's rows
  /// in APath. AFixed returns how many findings the edits fix.</remarks>
  TFileFixer = reference to function(const APath: string; const AFindings: TArray<TLintFinding>; out AFixed: Integer): TArray<TTextEdit>;

/// <summary>Is ARuleId a rule with a registered autofix?</summary>
/// <param name="ARuleId">A lint rule id; compared case-insensitively.</param>
/// <returns>True for every id in FIXABLE_RULE_IDS.</returns>
/// <remarks>The single source of truth for `rules --json`.fixable, the
/// `--fix --json` row's `fixable` and what the fix verbs attempt.</remarks>
function IsFixableRule(const ARuleId: string): Boolean;

/// <summary>Is ARuleId a fixable rule whose fix applies only when opted in?</summary>
/// <param name="ARuleId">A lint rule id; compared case-insensitively.</param>
/// <returns>True for the naming fixes in OPT_IN_FIX_RULE_IDS.</returns>
function IsOptInFixRule(const ARuleId: string): Boolean;


/// <summary>True iff the rule's registered fix is behaviour-CHANGING (not merely
/// a redundant-code cleanup).</summary>
/// <param name="ARuleId">A lint rule id; compared case-insensitively.</param>
/// <returns>True for the ids in RISKY_FIX_RULE_IDS.</returns>
/// <remarks>Such fixes are still applied, but callers surface a 'risky' flag so
/// a human/AI reviews before trusting a batch apply.</remarks>
function IsRiskyFixRule(const ARuleId: string): Boolean;

/// <summary>True iff the rule's registered fix is SINGLE-FIX-ONLY: applied for a
/// single targeted finding but excluded from the blanket batch.</summary>
/// <param name="ARuleId">A lint rule id; compared case-insensitively.</param>
/// <returns>True for the ids in SINGLE_FIX_ONLY_RULE_IDS (today missing-doc).</returns>
function IsSingleFixOnlyRule(const ARuleId: string): Boolean;

/// <summary>Builds the pure-text quick-fix edits for the subset of AFindings whose
/// rule has a registered autofix.</summary>
/// <param name="AFindings">The findings to fix; rules without a fix are skipped.</param>
/// <param name="AFixableCount">Out: how many findings produced a fix.</param>
/// <returns>The edits, unordered; TTextEditApplier orders and applies them.</returns>
/// <remarks>Store-backed fixes (doc-drift, missing-doc, the naming renames,
/// raise-bare-exception) are NOT built here -- see the implementation comment.</remarks>
function BuildAutofixEdits(const AFindings: TArray<TLintFinding>; out AFixableCount: Integer): TArray<TTextEdit>;

/// <summary>Drops every finding's edits that overlap an edit of an EARLIER
/// finding in the same file, so one --fix pass never writes mixed bytes.</summary>
/// <param name="AEdits">The pass's edits, in finding order (BuildAutofixEdits
/// order); owned edits carry TTextEdit.Owner.</param>
/// <param name="ADeferredOwners">Out: the FixOwnerKey of each finding whose edits
/// were withheld -- the next --fix pass, which re-lints, applies them.</param>
/// <returns>AEdits minus the deferred findings' edits, order kept.</returns>
/// <remarks>A finding is kept or deferred WHOLE -- with every finding a
/// TTextEdit.AtomGroup ties it to (EditAtomKey). Unowned, ungrouped edits (the store-backed
/// builders) are always kept and win any conflict. Overlap: two line ranges
/// (delete / replace-lines) sharing a line; an in-line replace on a line a range
/// covers; two in-line replaces on one line whose column spans intersect; an
/// insert strictly inside a range. Edits of the SAME finding never conflict here.
/// Pure; never raises.</remarks>
function DeferConflictingFixes(const AEdits: TArray<TTextEdit>; out ADeferredOwners: TArray<string>): TArray<TTextEdit>;
/// <summary>The key that ties an edit to the finding that produced it.</summary>
/// <param name="AFinding">The finding.</param>
/// <returns>Lower-cased `file|StartLine|rule`; BuildAutofixEdits stores it in
/// TTextEdit.Owner of every edit the finding's fixer returned.</returns>
/// <remarks>The `--fix --json` row of a finding is applied/preview when ANY edit
/// carries its key, wherever that edit sits in the file.</remarks>
function FixOwnerKey(const AFinding: TLintFinding): string;

/// <summary>Registers a per-finding fixer for ARuleId (autofix wave A0).</summary>
/// <param name="ARuleId">The rule id; compared case-insensitively.</param>
/// <param name="AFixer">Builds the edits for one finding; see TFindingFixer.</param>
/// <param name="ARisky">True for a behaviour-CHANGING fix (tagged risky, still applied).</param>
/// <remarks>Makes IsFixableRule (and so `rules --json`.fixable) true for the id.
/// An id the legacy FIXABLE_RULE_IDS chain already fixes is never handed to a
/// registered fixer. Call it from a fixer unit's RegisterFixers, which this
/// unit's initialization runs; not thread-safe after start-up.</remarks>
procedure RegisterFixer(const ARuleId: string; const AFixer: TFindingFixer; ARisky: Boolean = False);

/// <summary>Registers a per-file fixer for ARuleId (autofix wave A0).</summary>
/// <param name="ARuleId">The rule id; compared case-insensitively.</param>
/// <param name="AFixer">Builds the edits for every finding of the rule in one file.</param>
/// <param name="ARisky">True for a behaviour-CHANGING fix.</param>
/// <remarks>Same contract as RegisterFixer; called once per file that has a
/// finding of the rule.</remarks>
procedure RegisterFileFixer(const ARuleId: string; const AFixer: TFileFixer; ARisky: Boolean = False);

/// <summary>Installs THE generic sidecar fixer: the builder for every finding
/// whose rule's .json carries a "fix" key (TLintFinding.FixKind).</summary>
/// <param name="AFixer">The builder; DRagLint.Fix.Templates installs its own
/// from its initialization.</param>
/// <remarks>A hook rather than a uses: the fixer units use this unit, never
/// the reverse, so no unit cycle forms (circular-uses).</remarks>
procedure RegisterSidecarFixer(const AFixer: TFindingFixer);

/// <summary>Hands the store this --fix run's findings came from to the registered fixers.</summary>
/// <param name="AStore">The open store, or nil to clear it (a run without --db).</param>
/// <remarks>The CLI sets it around BuildAutofixEdits. A store-backed fixer reads it through
/// AutofixStore and declines when it is nil. The unit holds the reference only between the
/// two calls; not thread-safe -- one fix run at a time.</remarks>
procedure SetAutofixStore(const AStore: ISymbolStore);

/// <summary>The store SetAutofixStore handed over, or nil when none is open.</summary>
/// <returns>The current fix run's store; nil outside a --db run.</returns>
function AutofixStore: ISymbolStore;
/// <summary>Builds the ONE edit that wraps lines AFirstLine..ALastLine in
/// try / finally / end.</summary>
/// <param name="APath">The file the edit targets.</param>
/// <param name="ALines">The file's current lines.</param>
/// <param name="AFirstLine">1-based first line of the protected statements.</param>
/// <param name="ALastLine">1-based last line of the protected statements.</param>
/// <param name="AFinallyText">The finally body (may hold line breaks), unindented.</param>
/// <param name="AIndent">The indent of the try/finally/end keywords.</param>
/// <param name="AEdit">Out: a tekReplaceLines edit, guarded on line AFirstLine.</param>
/// <returns>False when the range is outside the file.</returns>
/// <remarks>The protected lines are re-indented by two spaces; the finally
/// body is written at AIndent + two spaces, one line per input line.</remarks>
function WrapInTryFinally(const APath: string; ALines: TStrings; AFirstLine, ALastLine: Integer;
  const AFinallyText, AIndent: string; out AEdit: TTextEdit): Boolean;

/// <summary>Builds the edit that deletes the statement AFinding spans: the
/// span, the ';' after it, and the whole line when nothing else is left.</summary>
/// <param name="AFinding">The finding; its span is the statement.</param>
/// <param name="ALines">The finding's file.</param>
/// <param name="AEdit">Out: a tekDeleteLines or guarded tekReplaceInLine edit.</param>
/// <returns>False when the span is not a whole statement this helper can
/// remove safely (a multi-line span that shares a line with other code).</returns>
function DeleteStatement(const AFinding: TLintFinding; ALines: TStrings; out AEdit: TTextEdit): Boolean;

/// <summary>Builds the edit that inserts AUnit into the implementation uses
/// clause (the interface one when the unit has no implementation uses).</summary>
/// <param name="APath">The file the edit targets.</param>
/// <param name="AUnit">The unit name to add.</param>
/// <param name="ALines">The file's current lines.</param>
/// <param name="AEdit">Out: the insert edit.</param>
/// <returns>False when no uses clause exists. Does NOT check whether AUnit is
/// already listed -- EnsureImplUses does.</returns>
/// <remarks>Lifted verbatim from DRagLint.CLI's raise-bare-exception rewrite
/// (BuildUsesEdit), which still calls it.</remarks>
function BuildImplUsesEdit(const APath, AUnit: string; ALines: TStrings; out AEdit: TTextEdit): Boolean;

/// <summary>Like BuildImplUsesEdit, but returns False (no edit) when AUnit is
/// already named in any uses clause of the file.</summary>
/// <param name="APath">The file the edit targets.</param>
/// <param name="ALines">The file's current lines.</param>
/// <param name="AUnit">The unit name to add (RTL units only without a --db).</param>
/// <param name="AEdit">Out: the insert edit.</param>
/// <returns>True when an edit was built.</returns>
function EnsureImplUses(const APath: string; ALines: TStrings; const AUnit: string; out AEdit: TTextEdit): Boolean;

/// <summary>The declared type of AName as seen from line ALine of APath: a
/// same-routine local, parameter or inline var, or a unit-level var.</summary>
/// <param name="APath">The source file (parsed through TAstParseCache).</param>
/// <param name="ALine">1-based line inside the routine that uses AName.</param>
/// <param name="AName">The identifier; case-insensitive.</param>
/// <returns>The type text with whitespace removed, or '' when the source does
/// not show one (a field, a with-member, an untyped inline var, a missing file).</returns>
/// <remarks>The same scope walk as the .scm predicate #declared-type?, so a code
/// fixer and a rule agree on what a local is.</remarks>
function DeclTypeOf(const APath: string; ALine: Integer; const AName: string): string;

implementation

uses
  System.SysUtils
  , System.IOUtils
  , System.StrUtils
  , System.Math
  , System.RegularExpressions
  , System.Generics.Collections
  , System.Generics.Defaults
  , DRagLint.Diagnostics.AstChecks
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Lint.QueryRules     { DeclaredTypeAt -- DeclTypeOf }
  , DRagLint.Lint.RuleCatalog    { IsSidecarFixRule -- a sidecar "fix" key makes a rule fixable }
  ;

type
  TRegisteredFixer = record
    Finding: TFindingFixer;
    PerFile: TFileFixer   ;
    Risky  : Boolean      ;
  end;

var
  { rule id -> fixer; case-insensitive. Filled at start-up from the fixer
    units' initialization sections, read-only after. }
  GFixers: TDictionary<string, TRegisteredFixer>;
  { the generic sidecar fixer (DRagLint.Fix.Templates installs it) }
  GSidecarFixer: TFindingFixer;
  { the open store of the current --fix run (SetAutofixStore); nil without --db }
  GFixStore: ISymbolStore;

{ The line span an edit occupies, for DeferConflictingFixes. In-line replaces
  and inserts occupy one line; an insert after line L sits between L and L+1. }
function EditSpanFirst(const E: TTextEdit): Integer;
begin
  Result:= E.Line;
end;

function EditSpanLast(const E: TTextEdit): Integer;
begin
  Result:= if (E.Kind in [tekDeleteLines, tekReplaceLines]) and (E.EndLine > E.Line) then E.EndLine else E.Line;
end;

function EditsConflict(const A, B: TTextEdit): Boolean;
const
  RANGE_KINDS = [tekDeleteLines, tekReplaceLines];
begin
  if not SameText(A.FilePath, B.FilePath) then Exit(False);
  if (A.Kind = tekInsertLines) and (B.Kind = tekInsertLines) then Exit(False);
  if A.Kind = tekInsertLines then
    Exit((B.Kind in RANGE_KINDS) and (EditSpanFirst(B) <= A.Line) and (A.Line < EditSpanLast(B)));
  if B.Kind = tekInsertLines then
    Exit((A.Kind in RANGE_KINDS) and (EditSpanFirst(A) <= B.Line) and (B.Line < EditSpanLast(A)));
  if (A.Kind = tekReplaceInLine) and (B.Kind = tekReplaceInLine) then
    Exit((A.Line = B.Line) and (A.Col < B.EndCol) and (B.Col < A.EndCol));
  Result:= (EditSpanFirst(A) <= EditSpanLast(B)) and (EditSpanFirst(B) <= EditSpanLast(A));
end;

function DeferConflictingFixes(const AEdits: TArray<TTextEdit>; out ADeferredOwners: TArray<string>): TArray<TTextEdit>;
var
  Kept    : TObjectDictionary<string, TList<TTextEdit>>;  { file -> edits kept so far }
  Order   : TStringList;                                    { owners, first-appearance order }
  Deferred: TDictionary<string, Boolean>;                   { owner -> deferred? (every owner is a key) }

  function KeptFor(const APath: string): TList<TTextEdit>;
  begin
    if not Kept.TryGetValue(APath, Result) then
    begin
      Result:= TList<TTextEdit>.Create;
      Kept.Add(APath, Result);
    end;
  end;

begin
  ADeferredOwners:= nil;
  Kept    := TObjectDictionary<string, TList<TTextEdit>>.Create([doOwnsValues], TIStringComparer.Ordinal);
  Order   := TStringList.Create(dupIgnore, False, False);
  Deferred:= TDictionary<string, Boolean>.Create;
  try
    { lane IATOM: the unit kept or deferred is the ATOM (EditAtomKey: the
      finding, or the group a per-file fixer tied several findings into). }
    for var E: TTextEdit in AEdits do
      if EditAtomKey(E) = '' then KeptFor(E.FilePath).Add(E)
      else if not Deferred.ContainsKey(EditAtomKey(E)) then
      begin
        Deferred.Add(EditAtomKey(E), False);   { seen; True below = deferred }
        Order.Add(EditAtomKey(E));
      end;
    for var Own: string in Order do
    begin
      var Clash: Boolean:= False;
      for var E: TTextEdit in AEdits do
      begin
        if EditAtomKey(E) <> Own then Continue;
        for var K: TTextEdit in KeptFor(E.FilePath) do
          if (EditAtomKey(K) <> Own) and EditsConflict(E, K) then
          begin
            Clash:= True;
            Break;
          end;
        if Clash then Break;
      end;
      if Clash then Deferred[Own]:= True
      else
        for var E: TTextEdit in AEdits do
          if EditAtomKey(E) = Own then KeptFor(E.FilePath).Add(E);
    end;
    Result:= nil;
    for var E: TTextEdit in AEdits do
      if (EditAtomKey(E) = '') or not Deferred[EditAtomKey(E)] then Result:= Result + [E]
      else if (E.Owner <> '') and (IndexText(E.Owner, ADeferredOwners) < 0) then ADeferredOwners:= ADeferredOwners + [E.Owner];
  finally
    Kept.Free;
    Order.Free;
    Deferred.Free;
  end;
end;
function FixOwnerKey(const AFinding: TLintFinding): string;
begin
  Result:= LowerCase(AFinding.FilePath + '|' + IntToStr(AFinding.StartLine) + '|' + AFinding.RuleId);
end;

procedure RegisterSidecarFixer(const AFixer: TFindingFixer);
begin
  GSidecarFixer:= AFixer;
end;

procedure SetAutofixStore(const AStore: ISymbolStore);
begin
  GFixStore:= AStore;
end;

function AutofixStore: ISymbolStore;
begin
  Result:= GFixStore;
end;

function Fixers: TDictionary<string, TRegisteredFixer>;
begin
  if GFixers = nil then GFixers:= TDictionary<string, TRegisteredFixer>.Create(TIStringComparer.Ordinal);
  Result:= GFixers;
end;

procedure RegisterFixer(const ARuleId: string; const AFixer: TFindingFixer; ARisky: Boolean);
var
  R: TRegisteredFixer;
begin
  R:= Default(TRegisteredFixer);
  R.Finding:= AFixer;
  R.Risky  := ARisky;
  Fixers.AddOrSetValue(ARuleId, R);
end;

procedure RegisterFileFixer(const ARuleId: string; const AFixer: TFileFixer; ARisky: Boolean);
var
  R: TRegisteredFixer;
begin
  R:= Default(TRegisteredFixer);
  R.PerFile:= AFixer;
  R.Risky  := ARisky;
  Fixers.AddOrSetValue(ARuleId, R);
end;
{ The set of rule-ids that have a registered, mechanical, side-effect-free
  quick-fix. Single source of truth for both the rules-catalog 'fixable' flag
  and the fix verbs. Widening AutoFix = add an id here AND a branch in
  BuildAutofixEdits (kept in lockstep; a guard test asserts they agree).
  EXCEPTION: store-backed fixes (doc-drift, missing-doc, method-pascalcase,
  local-var-casing, const-casing, field-name-prefix, param-name-prefix,
  type-name-prefix, raise-bare-exception) are fixable but have NO
  BuildAutofixEdits branch --
  doc-drift/missing-doc edits come from TDocumenter.BuildFor and the naming
  re-casing/prefix-adding edits come from DRagLint.Refactor.NamingFix.Build-
  NamingFixEdits (the rename engine), both via a store-backed append in
  FinalizeAndOutput, not from the pure-text edit builder.
  raise-bare-exception joins them: its replacement class NAME is read out of
  the exceptions unit's managed block, so a pure-text builder could not know
  it -- BuildExceptionRewriteEdits supplies those edits the same way. }
const
  FIXABLE_RULE_IDS: array[0..23] of string = (
    'self-assignment', 'redundant-parentheses', 'redundant-cast', 'redundant-not-not', 'redundant-as-tobject', 'boolean-comparison-true', 'reserved-word-casing',
    'redundant-assigned-free', 'off-by-one-count', 'doc-drift', 'missing-doc',
    'method-pascalcase', 'local-var-casing', 'const-casing',
    'field-name-prefix', 'param-name-prefix', 'type-name-prefix',
    'nil-comparison', 'uppercase-compare', 'uppercase-compare-always-false', 'unused-local',
    { local-field-prefix: strips an F prefix off a LOCAL. Safest rename in the
      family -- single-routine scope, so no call site can be affected. }
    'local-field-prefix',
    { raise-bare-exception: `raise Exception.Create('x')` -> the generated
      class for that message, plus the uses entry. Gated on exceptions-sync
      having run, and it SKIPS any file that tests the class exactly. }
    'raise-bare-exception',
    { property-accessor-name (lane A5B): the accessor is renamed to F<Prop> /
      Get<Prop> / Set<Prop> by the NamingFix rename engine -- opt-in below. }
    'property-accessor-name');

{ The LEGACY set: the ids the FIXABLE_RULE_IDS list (and the if-chain in
  BuildAutofixEdits / the store-backed appends in the CLI) owns. }
function IsLegacyFixRule(const ARuleId: string): Boolean;
var
  S: string;
begin
  for S in FIXABLE_RULE_IDS do
    if SameText(S, ARuleId) then Exit(True);
  Result:= False;
end;

{ autofix wave A0: legacy list OR a registered fixer OR a sidecar "fix" key. }
function IsFixableRule(const ARuleId: string): Boolean;
var
  Risky: Boolean;
begin
  Result:= IsLegacyFixRule(ARuleId) or Fixers.ContainsKey(ARuleId) or IsSidecarFixRule(ARuleId, Risky);
end;

{ The NAMING fixes. Each rewrites a declaration and every use the index knows
  about -- project-wide -- so `lint --fix` applies one only when the config
  opts it in ("autofix": [...] in drag-lint-lint.json) AND a store is open.
  One list, read by the fixer AND by `rules --json` (`fix_opt_in`): the IDE
  counted these as fixable, offered "Fix all in unit (78)" on ORM3's
  BASICS.PAS, and the run then reported "no fixable findings" (2026-10-13). }
const
  OPT_IN_FIX_RULE_IDS: array[0..7] of string = (
    'method-pascalcase', 'local-var-casing', 'const-casing', 'field-name-prefix',
    'param-name-prefix', 'type-name-prefix', 'local-field-prefix', 'property-accessor-name');

/// <summary>Is ARuleId a fixable rule whose fix applies only when opted in?</summary>
/// <param name="ARuleId">A lint rule id; compared case-insensitively.</param>
/// <returns>True for the naming fixes in OPT_IN_FIX_RULE_IDS.</returns>
function IsOptInFixRule(const ARuleId: string): Boolean;
var
  S: string;
begin
  for S in OPT_IN_FIX_RULE_IDS do
    if SameText(S, ARuleId) then Exit(True);
  Result:= False;
end;


{ Behaviour-CHANGING fixes: still applied by Fix-it/Fix-all, but tagged so a
  human/AI orchestrator is warned. off-by-one-count appends ' - 1' to a loop
  bound, which breaks an intentionally-inclusive loop.
  uppercase-compare-always-false recases the literal so a comparison that could
  NEVER be true becomes capable of being true -- that is the whole point of the
  fix, but it means a previously-dead branch starts executing, so a human has to
  confirm the branch was meant to run. }
const
  RISKY_FIX_RULE_IDS: array[0..1] of string = ('off-by-one-count', 'uppercase-compare-always-false');

  /// <summary>True iff the rule's registered fix is behaviour-CHANGING (not merely
  /// a redundant-code cleanup). Such fixes are still applied, but callers surface a
  /// 'risky' flag so a human/AI reviews before trusting a batch apply.</summary>
function IsRiskyFixRule(const ARuleId: string): Boolean;
var
  S: string;
  R: TRegisteredFixer;
  B: Boolean;
begin
  for S in RISKY_FIX_RULE_IDS do
    if SameText(S, ARuleId) then Exit(True);
  { autofix wave A0: a registered or sidecar fix declares its own risk }
  if Fixers.TryGetValue(ARuleId, R) and R.Risky then Exit(True);
  Result:= IsSidecarFixRule(ARuleId, B) and B;
end;

{ Fixable rules whose fix is offered ONLY for a single targeted finding (the IDE
  "Fix it" on one decl, or `lint-all --fix --fix-line/--fix-rule`), and DELIBERATELY
  EXCLUDED from the blanket batch (`lint-all --fix` / "Fix all"). Currently only
  missing-doc: batch-documenting every undocumented decl project-wide is what
  `document --project` is for (facts-only default + --stubs control); folding it
  into the blanket batch would inject TODO stubs across a whole project. }
const
  SINGLE_FIX_ONLY_RULE_IDS: array[0..0] of string = ('missing-doc');

  /// <summary>True iff the rule's registered fix is SINGLE-FIX-ONLY: applied for a
  /// single targeted finding (IDE "Fix it" / --fix-line + --fix-rule) but excluded
  /// from the blanket `lint-all --fix` batch so it does not mass-inject edits.</summary>
function IsSingleFixOnlyRule(const ARuleId: string): Boolean;
var
  S: string;
begin
  for S in SINGLE_FIX_ONLY_RULE_IDS do
    if SameText(S, ARuleId) then Exit(True);
  Result:= False;
end;

/// <summary>True iff S (trimmed) needs NO extra parentheses to be the operand of
/// a unary 'not'. That holds when S is either (a) a lone primary term -- an
/// identifier or dotted chain, optionally followed only by balanced call '(...)'
/// / index '[...]' groups and '.ident' segments, with NO top-level operator and
/// NO top-level whitespace -- OR (b) already a single fully-enclosing '(...)'
/// group (the opening paren balances exactly at the last character).
/// Errs toward False (compound): over-wrapping 'not (X)' is harmless, but
/// under-wrapping 'not a and b' silently changes meaning.</summary>
function IsSingleTokenAtom(const S: string): Boolean;
var
  T    : string                           ;
  i    : Integer                          ;
  Depth: Integer                          ;
  C    : Char                             ;
  function IsIdentStart(Ch: Char): Boolean;
  begin Result:= CharInSet(Ch, ['A'..'Z','a'..'z','_']); end;
  function IsIdentChar(Ch: Char): Boolean;
  begin Result:= CharInSet(Ch, ['A'..'Z','a'..'z','_','0'..'9']); end;
begin
  T:= Trim(S);
  if T = '' then Exit(False);

  { (b) already a single fully-enclosing '(...)' group: the leading '(' must
    balance to depth 0 only at the very last character (so '(a) and (b)' does
    NOT qualify -- its first '(' closes mid-string). }
  if T[1] = '(' then
  begin
    Depth:= 0;
    for i:= 1 to Length(T) do
    begin
      if T[i]      = '(' then Inc(Depth)
      else if T[i] = ')' then
      begin
        Dec(Depth);
        if (Depth = 0) then Exit(i = Length(T)); { balanced only at the end => atomic }
      end;
    end;
    Exit(False); { unbalanced }
  end;

  { (a) lone primary term. }
  if not IsIdentStart(T[1]) then Exit(False);
  Depth:= 0;
  i    := 1;
  while i <= Length(T) do
  begin
    C:= T[i];
    if (C = '(') or (C = '[') then Inc(Depth)
    else if (C = ')') or (C = ']') then begin
      Dec(Depth);
      if Depth < 0 then Exit(False);
    end
    else if Depth = 0 then
    begin
      { at top level, only identifier chars and a '.' between segments are allowed;
        anything else (whitespace, operator char, ',', ':', etc.) => compound. }
      if not (IsIdentChar(C) or (C = '.')) then Exit(False);
    end;
    Inc(i);
  end;
  Result:= (Depth = 0);
end; // begin

/// <summary>Builds the quick-fix text edits for the subset of AFindings whose
/// rule has a registered autofix (the FIXABLE_RULE_IDS set). Mechanical, no
/// type info:
///   self-assignment       -> delete the offending statement line(s);
///   redundant-parentheses -> strip the outer '(' ')' of the flagged span;
///   redundant-cast        -> strip a 'TFoo(x)' cast where x is one identifier;
///   redundant-not-not     -> strip the two leading 'not' keywords;
///   redundant-as-tobject  -> strip the ' as TObject' suffix;
///   boolean-comparison-true -> X=True/X&lt;&gt;False->X; X=False/X&lt;&gt;True->not X;
///   reserved-word-casing  -> lowercase the keyword token;
///   redundant-assigned-free -> drop the 'if Assigned(X) then' guard;
///   off-by-one-count      -> append ' - 1' to the loop bound (RISKY);
///   unused-local          -> remove the dead declaration (AST-driven, grouped
///                            per file -- see below).
/// AFixableCount returns how many findings produced a fix. Rules without a fix
/// are silently skipped.</summary>
/// <remarks>Deliberately conservative: only rules whose fix is an exact,
/// side-effect-free text edit are wired. redundant-parentheses is fixed only
/// when the flagged span is single-line and literally starts with '(' and ends
/// with ')'. Best for non-overlapping findings; same-line multi-fixes are not
/// column-reconciled (the applier orders by line).
/// unused-local is the ONE rule here that is NOT per-finding: it is delegated,
/// once per file, to TAstChecker.BuildUnusedLocalFixEdits. Several dead names can
/// share one declaration, so whether that declaration may be deleted outright or
/// must have its name list spliced depends on every finding against it -- and the
/// emptied-'var'-block collapse depends on the whole section. Per-finding edits
/// here would delete still-used variables and stack overlapping deletes on one
/// line, so that grouping is load-bearing, not a tidiness choice.</remarks>
function BuildAutofixEdits(const AFindings: TArray<TLintFinding>; out AFixableCount: Integer): TArray<TTextEdit>;
var
  F    : TLintFinding                    ;
  E    : TTextEdit                       ;
  EndL : Integer                         ;
  Cache: TDictionary<string, TStringList>;
  SL   : TStringList                     ;
  Ln   : string                          ;
  Span : string                          ;
  Repl : string                          ;
  { autofix wave A0: (file=unit) pairs a sidecar fix needs in the uses clause }
  UsesWanted: TStringList                ;
  UsesDone  : TStringList                ;

  { Records one in-line replacement of F's span [F.StartCol, AEndCol) with AText and counts it as fixable.
    The eleven single-line fixes below all ended in this same ten-line block (duplicate-code). }
  procedure AddReplaceEdit(const AF: TLintFinding; AEndCol: Integer; const AText: string);
  var
    Ed: TTextEdit;
  begin
    Ed:= Default(TTextEdit);
    Ed.FilePath:= AF.FilePath;
    Ed.Kind    := tekReplaceInLine;
    Ed.Line    := AF.StartLine;
    Ed.Col     := AF.StartCol;
    Ed.EndCol  := AEndCol;
    Ed.Text    := AText;
    Result:= Result + [Ed];
    Inc(AFixableCount);
  end; // procedure

  function LinesFor(const APath: string): TStringList;
  begin
    if not Cache.TryGetValue(APath, Result) then
    begin
      Result:= TStringList.Create;
      if TFile.Exists(APath) then Result.Text:= TEncoding.ANSI.GetString(TFile.ReadAllBytes(APath));
      Cache.Add(APath, Result);
    end;
  end;
begin
  Result:= nil;
  AFixableCount:= 0;
  Cache:= TDictionary<string, TStringList>.Create;
  UsesWanted:= TStringList.Create;
  UsesDone  := TStringList.Create;
  try
    for F in AFindings do
    begin
      var OwnFrom: Integer:= Length(Result);   { this finding's edits start here -- stamped below }
      if SameText(F.RuleId, 'self-assignment') then
      begin
        EndL:= F.EndLine;
        if EndL < F.StartLine then EndL:= F.StartLine;
        E:= Default(TTextEdit);
        E.FilePath:= F.FilePath;
        E.Kind:= tekDeleteLines;
        E.Line:= F.StartLine;
        E.EndLine:= EndL;
        Result:= Result + [E];
        Inc(AFixableCount);
      end
      else if SameText(F.RuleId, 'redundant-parentheses') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          if (Length(Span) >= 2) and (Span[1] = '(') and (Span[Length(Span)] = ')') then
          begin
            Repl:= Copy(Span, 2, Length(Span) - 2); { strip the outer parens }
            AddReplaceEdit(F, F.EndCol, Repl);
          end;
        end; // if
      end // if
      { v(autofix-compare): `X = nil` -> `not Assigned(X)`, `X <> nil` -> `Assigned(X)`.
        The rule pins @warn to the whole exprBinary, so the span is the complete
        comparison. Note the polarity inversion: `= nil` means NOT assigned. }
      else if SameText(F.RuleId, 'nil-comparison') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          var NcOpAt : Integer:= Pos('<>', Span);
          var NcOpLen: Integer:= 2;
          var NcNeg  : Boolean:= False;   { True -> the fix needs a leading `not` }
          if NcOpAt <= 0 then
          begin
            NcOpAt := Pos('=', Span);
            NcOpLen:= 1;
            NcNeg  := True;               { `X = nil` is "not assigned" }
          end;
          if NcOpAt > 1 then
          begin
            var NcLhs: string:= Trim(Copy(Span, 1, NcOpAt - 1));
            var NcRhs: string:= Trim(Copy(Span, NcOpAt + NcOpLen, MaxInt));
            if SameText(NcRhs, 'nil') and (NcLhs <> '') then
            begin
              Repl:= 'Assigned(' + NcLhs + ')';
              if NcNeg then Repl:= 'not ' + Repl;
              AddReplaceEdit(F, F.EndCol, Repl);
            end;
          end;
        end; // if
      end
      { v(autofix-compare): `UpperCase(X) = 'ABC'` -> `SameText(X, 'ABC')` (and
        `<>` -> `not SameText(...)`). Only the STYLE variant of the rule reaches
        here -- the always-false variant is a separate rule id below, because
        rewriting THAT one to SameText would silently turn a never-matching test
        into a sometimes-matching one.
        The operator is located in the text BEFORE the first quote, so a literal
        containing '=' or '<>' ('a<>b') cannot be mistaken for the operator. }
      else if SameText(F.RuleId, 'uppercase-compare') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          var UcOpen: Integer:= Pos('(', Span);
          var UcClose: Integer:= 0;
          if UcOpen > 0 then
          begin
            var UcDepth: Integer:= 0;
            for var UcQ: Integer:= UcOpen to Length(Span) do
            begin
              if Span[UcQ] = '(' then Inc(UcDepth)
              else if Span[UcQ] = ')' then
              begin
                Dec(UcDepth);
                if UcDepth = 0 then
                begin
                  UcClose:= UcQ;
                  Break;
                end;
              end;
            end;
          end;
          if UcClose > UcOpen then
          begin
            var UcInner: string := Trim(Copy(Span, UcOpen + 1, UcClose - UcOpen - 1));
            var UcRest : string := Copy(Span, UcClose + 1, MaxInt);
            var UcQuote: Integer:= Pos('''', UcRest);
            if (UcInner <> '') and (UcQuote > 1) then
            begin
              var UcNeg: Boolean:= Pos('<>', Copy(UcRest, 1, UcQuote - 1)) > 0;
              var UcLit: string := Trim(Copy(UcRest, UcQuote, MaxInt));
              if UcLit <> '' then
              begin
                Repl:= 'SameText(' + UcInner + ', ' + UcLit + ')';
                if UcNeg then Repl:= 'not ' + Repl;
                AddReplaceEdit(F, F.EndCol, Repl);
              end;
            end;
          end; // if
        end; // if
      end
      { v(autofix-compare): the always-false variant. The fix RECASES THE LITERAL
        to agree with the conversion (`UpperCase(X) = 'abc'` -> `... = 'ABC'`),
        which preserves the author's evident intent and makes the comparison
        capable of being true. Deliberately NOT a SameText rewrite: that also
        works, but it changes case-sensitivity as well as fixing the dead branch,
        and one behaviour change at a time is enough. Registered RISKY -- a test
        that could never pass can now pass, which is the point, but a human must
        confirm that was the intent. }
      else if SameText(F.RuleId, 'uppercase-compare-always-false') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          var AfOpen: Integer:= Pos('(', Span);
          if AfOpen > 1 then
          begin
            var AfFn   : string := Trim(Copy(Span, 1, AfOpen - 1));
            var AfClose: Integer:= 0;
            var AfDepth: Integer:= 0;
            for var AfQ: Integer:= AfOpen to Length(Span) do
            begin
              if Span[AfQ] = '(' then Inc(AfDepth)
              else if Span[AfQ] = ')' then
              begin
                Dec(AfDepth);
                if AfDepth = 0 then
                begin
                  AfClose:= AfQ;
                  Break;
                end;
              end;
            end;
            if AfClose > AfOpen then
            begin
              var AfRest : string := Copy(Span, AfClose + 1, MaxInt);
              var AfQuote: Integer:= Pos('''', AfRest);
              if AfQuote > 0 then
              begin
                var AfLit: string:= Trim(Copy(AfRest, AfQuote, MaxInt));
                var AfNew: string;
                { Recase toward the conversion the code already performs. }
                AfNew:= if ContainsText(AfFn, 'upper') then UpperCase(AfLit) else LowerCase(AfLit);
                if (AfLit <> '') and (AfNew <> AfLit) then
                begin
                  AddReplaceEdit(F, F.EndCol, Copy(Span, 1, AfClose + AfQuote - 1) + AfNew);
                end;
              end;
            end;
          end; // if
        end; // if
      end
      else if SameText(F.RuleId, 'redundant-cast') and (F.StartLine = F.EndLine) then
      begin
        { redundant-cast fires only on 'TFoo(x)' with x a SINGLE identifier (the
          rule's precondition), so there is no nested paren: the ')' is the first
          one after the '('. The finding span [StartCol, EndCol) covers the entity
          name 'TFoo'; scan on to '(' then to ')' and replace 'TFoo(x)' with 'x'. }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          var OpenP: Integer:= F.EndCol; { 1-based; '(' expected at/after the name }
          while (OpenP <= Length(Ln)) and (Ln[OpenP] <> '(') do Inc(OpenP);
          if (OpenP <= Length(Ln)) and (Ln[OpenP] = '(') then
          begin
            var CloseP: Integer:= OpenP + 1;
            while (CloseP <= Length(Ln)) and (Ln[CloseP] <> ')') do Inc(CloseP);
            if (CloseP <= Length(Ln)) and (Ln[CloseP] = ')') then
            begin
              var Inner: string:= Trim(Copy(Ln, OpenP + 1, CloseP - OpenP - 1));
              if Inner <> '' then
              begin
                AddReplaceEdit(F, CloseP + 1, Inner); { exclusive end -- one past the ')' }
              end;
            end;
          end; // if
        end; // if
      end // if
      else if SameText(F.RuleId, 'redundant-not-not') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        { span covers 'not not X' (the outer exprUnary). Strip the two leading
          'not' keywords + their trailing whitespace; the remainder is X. }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          var Rest: string:= Span;
          var Ok: Boolean:= True ;
          { consume 'not' then >=1 whitespace, twice }
          for var Pass: Integer:= 1 to 2 do
          begin
            var LR: string:= TrimLeft(Rest);
            if (Length(LR) >= 3) and SameText(Copy(LR, 1, 3), 'not') and ((Length(LR) = 3) or (LR[4] <= ' ')) then Rest:= TrimLeft(Copy(LR, 4, MaxInt))  // dl:ok magic-literal@1139 -- REVIEWED 2026-10-28: Pascal keyword length (not) and its 1-based follow index
            else
            begin
              Ok:= False;
              Break;
            end;
          end;
          if Ok and (Rest <> '') then
          begin
            AddReplaceEdit(F, F.EndCol, Rest);
          end;
        end; // if
      end // if
      else if SameText(F.RuleId, 'redundant-as-tobject') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        { span covers 'X as TObject' (the exprBinary). Find the depth-0 whole-word
          'as' keyword; the lhs before it is X. }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          { scan for ' as ' at bracket depth 0 (whole word, case-insensitive) }
          var Depth: Integer:= 0;
          var AsPos: Integer:= 0;
          for var K: Integer:= 2 to Length(Span) - 2 do
          begin
            var Ch: Char:= Span[K];
            if (Ch = '(') or (Ch = '[') then Inc(Depth)
            else if (Ch = ')') or (Ch = ']') then Dec(Depth)
            else if (Depth = 0) and (Span[K - 1] <= ' ') and SameText(Copy(Span, K, 2), 'as') and ((K + 2 > Length(Span)) or (Span[K + 2] <= ' ')) then
            begin
              AsPos:= K;
              Break;
            end;
          end;
          if AsPos > 1 then
          begin
            Repl:= TrimRight(Copy(Span, 1, AsPos - 1));
            { only a bare identifier whose declared type is known and is not interface-looking (I + capital):
              IFoo as TObject is the only way from an interface to its instance, never redundant. }
            if (Repl <> '') and TRegEx.IsMatch(Repl, '^[A-Za-z_]\w*$') and (DeclTypeOf(F.FilePath, F.StartLine, Repl) <> '') and
               not TRegEx.IsMatch(DeclTypeOf(F.FilePath, F.StartLine, Repl), '^I[A-Z]') then
            begin
              AddReplaceEdit(F, F.EndCol, Repl);
            end;
          end;
        end; // if
      end // if
      else if SameText(F.RuleId, 'boolean-comparison-true') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        { span covers 'X op bool', op is '=' or '<>', bool is True or False.
          Scan for the LAST depth-0 '=' or '<>' operator; split into lhs/op/rhs.
          positive (= True / <> False) -> lhs; negative (= False / <> True) ->
          'not ' + (lhs, parenthesized when not a single-token atom). }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          var Depth: Integer:= 0;
          var OpPos: Integer:= 0;
          var OpLen: Integer:= 0;
          for var K: Integer:= 1 to Length(Span) do
          begin
            var Ch: Char:= Span[K];
            if (Ch = '(') or (Ch = '[') then Inc(Depth)
            else if (Ch = ')') or (Ch = ']') then Dec(Depth)
            else if Depth = 0 then
            begin
              if (K < Length(Span)) and (Ch = '<') and (Span[K + 1] = '>') then
              begin
                OpPos:= K;
                OpLen:= 2;
              end
              else if Ch = '=' then
              begin
                OpPos:= K;
                OpLen:= 1;
              end;
            end;
          end;
          if OpPos > 1 then
          begin
            var LhsText: string:= Trim(Copy(Span, 1, OpPos - 1))         ;
            var OpText : string:= Copy(Span, OpPos, OpLen)               ;
            var RhsText: string:= Trim(Copy(Span, OpPos + OpLen, MaxInt));
            var IsTrue : Boolean:= SameText(RhsText, 'True' );
            var IsFalse: Boolean:= SameText(RhsText, 'False');
            var Positive: Boolean                                        ;
            if (LhsText <> '') and (IsTrue or IsFalse) then
            begin
              { (= True) or (<> False) => positive; (= False) or (<> True) => negative }
              Positive:= if OpText = '=' then IsTrue else IsFalse;
              if Positive then Repl:= LhsText
              else if IsSingleTokenAtom(LhsText) then Repl:= 'not ' + LhsText
              else Repl:= 'not (' + LhsText + ')';
              AddReplaceEdit(F, F.EndCol, Repl);
            end; // if
          end; // if
        end; // if
      end // if
      else if SameText(F.RuleId, 'reserved-word-casing') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        { span covers the keyword token; keywords are case-insensitive and have no
          reference sites, so lowercasing the span is a safe local edit. }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          if (Span <> '') and (Span <> LowerCase(Span)) then
          begin
            AddReplaceEdit(F, F.EndCol, LowerCase(Span));
          end;
        end; // if
      end // if
      else if SameText(F.RuleId, 'redundant-assigned-free') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        { span covers 'if Assigned(X) then <stmt>;'. Take the text after the
          delimited 'then' keyword (whole word, not a substring of an identifier)
          to end of span. The Assigned guard is redundant -- Free is nil-safe. }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          var Depth  : Integer:= 0;
          var ThenEnd: Integer:= 0; { 1-based index one past the 'then' }
          var LS: string:= LowerCase(Span);
          for var K: Integer:= 1 to Length(Span) - 3 do  // dl:ok magic-literal@c578 -- REVIEWED 2026-10-28: length of keyword then, minus one
          begin
            var Ch: Char:= Span[K];
            if (Ch = '(') or (Ch = '[') then Inc(Depth)
            else if (Ch = ')') or (Ch = ']') then Dec(Depth)
            else if (Depth = 0) and (Copy(LS, K, 4) = 'then') and ((K = 1) or (Span[K - 1] <= ' ') or (Span[K - 1] = ')')) and ((K + 4 > Length(Span)) or (Span[K + 4] <= ' ')) then  // dl:ok magic-literal@66b2 -- REVIEWED 2026-10-28: Pascal keyword length (then); lexer-local scan
            begin
              ThenEnd:= K + 4;  // dl:ok magic-literal@5223 -- REVIEWED 2026-10-28: length of keyword then
              Break;
            end;
          end;
          if ThenEnd > 0 then
          begin
            Repl:= TrimLeft(Copy(Span, ThenEnd, MaxInt));
            if Repl <> '' then
            begin
              AddReplaceEdit(F, F.EndCol, Repl);
            end;
          end;
        end; // if
      end // if
      else if SameText(F.RuleId, 'off-by-one-count') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        { span covers the loop end-bound (X.Count / Length(X)). Append ' - 1'.
          BEHAVIOUR-CHANGING (tagged risky via IsRiskyFixRule). The bound is
          isolated by 'to .. do', so no precedence hazard. }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          if Trim(Span) <> '' then
          begin
            AddReplaceEdit(F, F.EndCol, Span + ' - 1');
          end;
        end; // if
      end; // if

      { autofix wave A0: a REGISTERED per-finding fixer, else a SIDECAR fix, for
        an id the legacy chain above does not own -- a registered id never
        doubles a legacy one. A sidecar "uses" unit is collected per file and
        added once, after the loop. }
      if not IsLegacyFixRule(F.RuleId) then
      begin
        var RegFx: TRegisteredFixer;
        var RegEdits: TArray<TTextEdit>:= nil;
        if Fixers.TryGetValue(F.RuleId, RegFx) and Assigned(RegFx.Finding) then
          RegEdits:= RegFx.Finding(F, LinesFor(F.FilePath))
        else if (F.FixKind <> lfkNone) and Assigned(GSidecarFixer) then
          RegEdits:= GSidecarFixer(F, LinesFor(F.FilePath));
        if Length(RegEdits) > 0 then
        begin
          Insert(RegEdits, Result, Length(Result));   { append }
          Inc(AFixableCount);
          if (F.FixKind <> lfkNone) and (F.FixUses <> '') then UsesWanted.AddPair(F.FilePath, F.FixUses);
        end;
      end;
      { ATTRIBUTION: every edit this finding produced -- on its line or not (a uses
        entry, a FreeAndNil in the destructor, the doc lines above) -- names it. }
      for var OwnI: Integer:= OwnFrom to High(Result) do
        if Result[OwnI].Owner = '' then Result[OwnI].Owner:= FixOwnerKey(F);
    end; // for

    { unused-local is handled per FILE, not per finding: several dead names can
      share one declaration, and whether a declaration may be deleted outright
      (vs. having its name list spliced) depends on ALL the findings against it.
      Emitting one edit per finding -- the obvious shape -- deletes live
      variables and stacks overlapping deletes on the same line. Grouping also
      keeps at most one edit per declaration, so the applier never sees an
      overlap. Driven off the AST in TAstChecker, next to the check itself. }
    var ULFiles: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
    try
      for F in AFindings do
        if SameText(F.RuleId, 'unused-local') and (F.FilePath <> '') then
          ULFiles.AddOrSetValue(F.FilePath, True);
      for var ULPath: string in ULFiles.Keys do
      begin
        var ULFixed: Integer:= 0;
        var ULEdits: TArray<TTextEdit>:=
          DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits(ULPath, AFindings, ULFixed);
        if Length(ULEdits) > 0 then
        begin
          Result:= Result + ULEdits;
          Inc(AFixableCount, ULFixed);
        end;
      end;
    finally
      ULFiles.Free;
    end;

    { autofix wave A0: registered PER-FILE fixers, once per file that has a
      finding of the rule (the unused-local shape above, generalised). }
    for var FxPair: TPair<string, TRegisteredFixer> in Fixers do
    begin
      if (not Assigned(FxPair.Value.PerFile)) or IsLegacyFixRule(FxPair.Key) then Continue;
      var FxFiles: TStringList:= TStringList.Create(dupIgnore, True, False);
      try
        for F in AFindings do
          if SameText(F.RuleId, FxPair.Key) and (F.FilePath <> '') then FxFiles.Add(F.FilePath);
        for var FxPath: string in FxFiles do
        begin
          var FxFixed: Integer:= 0;
          var FxEdits: TArray<TTextEdit>:= FxPair.Value.PerFile(FxPath, AFindings, FxFixed);
          if Length(FxEdits) > 0 then
          begin
            Insert(FxEdits, Result, Length(Result));    { append }
            Inc(AFixableCount, FxFixed);
          end;
        end;
      finally
        FxFiles.Free;
      end;
    end;

    { the "uses" units sidecar fixes asked for, once per (file, unit) }
    for var UI: Integer:= 0 to UsesWanted.Count - 1 do
    begin
      var UE: TTextEdit;
      var UKey: string:= LowerCase(UsesWanted.Names[UI] + '|' + UsesWanted.ValueFromIndex[UI]);
      if UsesDone.IndexOf(UKey) >= 0 then Continue;
      UsesDone.Add(UKey);
      if EnsureImplUses(UsesWanted.Names[UI], LinesFor(UsesWanted.Names[UI]), UsesWanted.ValueFromIndex[UI], UE) then
        Result:= Result + [UE];
    end;
  finally
    for SL in Cache.Values do SL.Free;
    Cache.Free;
    UsesWanted.Free;
    UsesDone.Free;
  end; // try
end; // begin

function WrapInTryFinally(const APath: string; ALines: TStrings; AFirstLine, ALastLine: Integer;
  const AFinallyText, AIndent: string; out AEdit: TTextEdit): Boolean;
const
  STEP = '  ';
var
  SB: TStringBuilder;
  L : Integer       ;
begin
  AEdit:= Default(TTextEdit);
  Result:= (AFirstLine >= 1) and (ALastLine >= AFirstLine) and (ALastLine <= ALines.Count);
  if not Result then Exit;
  SB:= TStringBuilder.Create;
  try
    SB.Append(AIndent + 'try');
    for L:= AFirstLine to ALastLine do
      if Trim(ALines[L - 1]) = '' then SB.Append(sLineBreak)
      else SB.Append(sLineBreak + STEP + ALines[L - 1]);
    SB.Append(sLineBreak + AIndent + 'finally');
    for var FL: string in AFinallyText.Replace(#13#10, #10).Split([#10]) do
      SB.Append(sLineBreak + AIndent + STEP + FL);
    SB.Append(sLineBreak + AIndent + 'end;');
    AEdit.FilePath  := APath;
    AEdit.Kind      := tekReplaceLines;
    AEdit.Line      := AFirstLine;
    AEdit.EndLine   := ALastLine;
    AEdit.Text      := SB.ToString;
    AEdit.ExpectText:= ALines[AFirstLine - 1];
  finally
    SB.Free;
  end;
end;

function DeleteStatement(const AFinding: TLintFinding; ALines: TStrings; out AEdit: TTextEdit): Boolean;
var
  First, Last: string ;
  Tail       : Integer;
  Before     : string ;
  After      : string ;
  Lead       : Integer;
begin
  AEdit:= Default(TTextEdit);
  Result:= False;
  if (AFinding.StartLine < 1) or (AFinding.EndLine < AFinding.StartLine) or (AFinding.EndLine > ALines.Count) then Exit;
  First:= ALines[AFinding.StartLine - 1];
  Last := ALines[AFinding.EndLine - 1];
  if (AFinding.StartCol < 1) or (AFinding.StartCol > Length(First) + 1) or (AFinding.EndCol < 1) or (AFinding.EndCol > Length(Last) + 1) then Exit;
  { the span, then blanks, then one optional ';' }
  Tail:= AFinding.EndCol;
  while (Tail <= Length(Last)) and CharInSet(Last[Tail], [' ', #9]) do Inc(Tail);
  if (Tail <= Length(Last)) and (Last[Tail] = ';') then Inc(Tail) else Tail:= AFinding.EndCol;
  Before:= Copy(First, 1, AFinding.StartCol - 1);
  After := Copy(Last, Tail, MaxInt);
  AEdit.FilePath:= AFinding.FilePath;
  if (Trim(Before) = '') and (Trim(After) = '') then
  begin
    { nothing else on the line(s): drop them whole }
    AEdit.Kind      := tekDeleteLines;
    AEdit.Line      := AFinding.StartLine;
    AEdit.EndLine   := AFinding.EndLine;
    Exit(True);
  end;
  if AFinding.StartLine <> AFinding.EndLine then Exit;   { shares a line with other code: decline }
  { a statement that ENDS its line takes the blanks before it along, so
    `X := 1; Foo;` becomes `X := 1;`, not `X := 1; ` }
  Lead:= AFinding.StartCol;
  if Trim(After) = '' then
    while (Lead > 1) and CharInSet(First[Lead - 1], [' ', #9]) do Dec(Lead);
  AEdit.Kind      := tekReplaceInLine;
  AEdit.Line      := AFinding.StartLine;
  AEdit.Col       := Lead;
  AEdit.EndCol    := Tail;
  AEdit.Text      := '';
  AEdit.ExpectText:= Copy(First, Lead, Tail - Lead);
  { an empty guard would make the edit unguarded }
  Result:= AEdit.ExpectText <> '';
end;

{ Lifted VERBATIM from DRagLint.CLI.BuildExceptionRewriteEdits.BuildUsesEdit
  (autofix wave A0). Insert AUnit into the implementation uses clause, as ONE
  edit. Returns False when no uses clause can be found. }
function BuildImplUsesEdit(const APath, AUnit: string; ALines: TStrings; out AEdit: TTextEdit): Boolean;
var
  M, ImplAt, UsesAt: Integer;
  T                : string ;
const
  USES_KW = 'uses';
begin
  Result:= False;
  AEdit:= Default(TTextEdit);
  ImplAt:= -1;
  for M:= 0 to ALines.Count - 1 do
    if SameText(Trim(ALines[M]), 'implementation') then
    begin
      ImplAt:= M;
      Break;
    end;
  { the raises are in the implementation, so that is the clause to extend; a
    unit with no implementation section falls back to the interface one }
  UsesAt:= -1;
  for M:= Max(ImplAt, 0) to ALines.Count - 1 do
  begin
    T:= LowerCase(Trim(ALines[M]));
    if (T = USES_KW) or T.StartsWith(USES_KW + ' ') then
    begin
      UsesAt:= M;
      Break;
    end;
  end;
  if (UsesAt < 0) and (ImplAt >= 0) then
    for M:= 0 to ALines.Count - 1 do
    begin
      T:= LowerCase(Trim(ALines[M]));
      if (T = USES_KW) or T.StartsWith(USES_KW + ' ') then
      begin
        UsesAt:= M;
        Break;
      end;
    end;
  if UsesAt < 0 then Exit;
  AEdit.FilePath:= APath;
  if SameText(Trim(ALines[UsesAt]), 'uses') then
  begin
    AEdit.Kind   := tekInsertLines;
    AEdit.Line   := UsesAt + 1;          { 1-based: insert AFTER the 'uses' line }
    AEdit.Text   := '  ' + AUnit + ',';
  end
  else
  begin
    { 'uses A, B;' -- inject immediately after the keyword, which keeps the
      edit to one line and cannot disturb a continuation line below it }
    AEdit.Kind:= tekInsertInLine;
    AEdit.Line:= UsesAt + 1;
    AEdit.Col := Pos(USES_KW, LowerCase(ALines[UsesAt])) + Length(USES_KW);
    AEdit.Text:= ' ' + AUnit + ',';
  end;
  Result:= True;
end;

function EnsureImplUses(const APath: string; ALines: TStrings; const AUnit: string; out AEdit: TTextEdit): Boolean;
var
  UnitNameRe: string;
  InUses: Boolean;
  T     : string ;
  M     : Integer;
begin
  AEdit:= Default(TTextEdit);
  Result:= False;
  if AUnit = '' then Exit;
  { scan every uses clause (from the keyword to its ';') for AUnit as a whole name; the unit-scope alias counts too
    (System.Math is the same unit as Math: adding both is E2004) }
  UnitNameRe:= TRegEx.Escape(AUnit);
  if AUnit.StartsWith('System.', True) then UnitNameRe:= '(?:System\.)?' + TRegEx.Escape(Copy(AUnit, Length('System.') + 1, MaxInt));
  InUses:= False;
  for M:= 0 to ALines.Count - 1 do
  begin
    T:= LowerCase(Trim(ALines[M]));
    if (T = 'uses') or T.StartsWith('uses ') then InUses:= True;
    if InUses then
    begin
      if TRegEx.IsMatch(ALines[M], '(^|[\s,])' + UnitNameRe + '\s*([,;]|$|\{|//)', [roIgnoreCase]) then Exit;
      if ALines[M].Contains(';') then InUses:= False;
    end;
  end;
  Result:= BuildImplUsesEdit(APath, AUnit, ALines, AEdit);
end;

function DeclTypeOf(const APath: string; ALine: Integer; const AName: string): string;
const
  LF = 10;
var
  PF    : TParsedFile;
  Row   : Integer    ;
  B     : Integer    ;
  LineAt: Integer    ;
  Txt   : string     ;
  Col   : Integer    ;
begin
  Result:= '';
  if (AName = '') or (ALine < 1) or not TFile.Exists(APath) then Exit;
  PF:= TAstParseCache.Get(APath);
  if PF.Tree = nil then Exit;
  { byte offset of line ALine (the parsed source is offset-preserving) }
  Row:= 1;
  LineAt:= 0;
  B:= 0;
  while (B < Length(PF.Src)) and (Row < ALine) do
  begin
    if PF.Src[B] = LF then
    begin
      Inc(Row);
      LineAt:= B + 1;
    end;
    Inc(B);
  end;
  if Row <> ALine then Exit;
  { the name's own column on that line when it is there, else the line start }
  B:= LineAt;
  while (B < Length(PF.Src)) and (PF.Src[B] <> LF) do Inc(B);
  Txt:= TEncoding.ANSI.GetString(PF.Src, LineAt, B - LineAt);
  Col:= TRegEx.Match(Txt, '\b' + TRegEx.Escape(AName) + '\b', [roIgnoreCase]).Index;
  if Col < 1 then Col:= 1;
  if not DeclaredTypeAt(PF.Tree.RootNode, PF.Src, UInt32(LineAt + Col - 1), AName, Result) then Result:= '';
end;

initialization
  Fixers;   { created first; a fixer unit initialized earlier would create it lazily anyway }

finalization
  GSidecarFixer:= nil;
  GFixStore:= nil;
  GFixers.Free;

end.