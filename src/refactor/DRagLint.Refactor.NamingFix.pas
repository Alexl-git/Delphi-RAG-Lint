unit DRagLint.Refactor.NamingFix;

interface

uses
  DRagLint.Core.Interfaces,
  DRagLint.Core.Model,
  DRagLint.Lint.Config,
  DRagLint.Refactor.TextEdit;

type
  /// <summary>Target casing styles, matching TNamingConfig's textual vocabulary.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Refactor.NamingFix.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TNameStyle = (nsPascalCase, nsCamelCase, nsUpperCase);

/// <summary>Maps a TNamingConfig case string ('PascalCase' | 'camelCase' |
/// 'UPPER_CASE') to a TNameStyle. Unknown/empty -> nsPascalCase.</summary>
/// <param name="AConfigCase"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->TNameStyle -- Observed: nsCamelCase; nsUpperCase;
/// nsPascalCase.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Refactor.NamingFix.ConstCaseCandidates (DRagLint.Refactor.NamingFix.pas), DRagLint.Refactor.NamingFix.NamingCandidates (DRagLint.Refactor.NamingFix.pas)</para>
/// <para>Calls: SameText</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function StyleFromConfigText(const AConfigCase: string): TNameStyle;

/// <summary>Returns AOldName re-cased to AStyle WITHOUT changing its letters or
/// inserting separators (a pure, collision-free re-casing in a case-insensitive
/// language). PascalCase upper-cases the first char; camelCase lower-cases it;
/// UPPER_CASE upper-cases the whole identifier. Idempotent. Empty -> ''.</summary>
/// <param name="AOldName">The offending identifier verbatim.</param>
/// <param name="AStyle">Target style.</param>
/// <returns>The re-cased identifier.</returns>
/// <remarks>
/// DECISION: phase-1 is pure re-casing only -- no separator
/// insertion. UPPER_CASE therefore yields e.g. MAXCOUNT, not MAX_COUNT
/// (word-boundary detection is a phase-2 concern; this keeps phase-1
/// collision-free and mechanical).
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Refactor.NamingFix.NamingCandidates (DRagLint.Refactor.NamingFix.pas)</para>
/// <para>Calls: Copy, LowerCase, UpperCase</para>
/// <para>Returns: UpperCase(AOldName); LowerCase(AOldName[1]) + Copy(AOldName, 2, MaxInt); UpperCase(AOldName[1]) + Copy(AOldName, 2, MaxInt)</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SynthesizeCasedName(const AOldName: string; AStyle: TNameStyle): string;

/// <summary>Returns APrefix + Cap(AOldName): the identifier with the naming-convention
/// prefix prepended and its first letter capitalized (e.g. 'client' + 'F' -> 'FClient';
/// 'x' + 'p' -> 'pX'). Idempotent: if AOldName already starts with APrefix followed by an
/// uppercase letter (already prefixed), returns AOldName unchanged. Empty APrefix or empty
/// AOldName returns AOldName. Unlike SynthesizeCasedName this CHANGES the identifier, so the
/// caller MUST collision-check the result before applying.</summary>
/// <param name="AOldName">The offending identifier verbatim.</param>
/// <param name="APrefix">The configured prefix (e.g. 'F', 'p', 'T'); '' disables.</param>
/// <returns>The prefixed identifier, or AOldName unchanged if already prefixed/empty input.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Refactor.NamingFix.NamingCandidates (DRagLint.Refactor.NamingFix.pas)</para>
/// <para>Calls: CharInSet, Copy, SameText, UpperCase</para>
/// <para>Returns: APrefix + UpperCase(AOldName[1]) + Copy(AOldName, 2, MaxInt)</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SynthesizePrefixedName(const AOldName, APrefix: string): string;

/// <summary>The names const-casing may rename AOldName to, in preference order:
/// one per style in AConstCase (the configured order), duplicates and the
/// unchanged name removed.</summary>
/// <param name="AOldName">The offending constant name verbatim.</param>
/// <param name="AConstCase">The configured const_case styles; empty means UPPER_CASE.</param>
/// <returns>Candidates, best first; empty when no style changes the name.</returns>
/// <remarks>WORD-AWARE, unlike SynthesizeCasedName (owner report 2026-10-13: most
/// of ORM3's const-casing findings looked like StationType_Operator, which a
/// first-letter re-casing leaves unchanged, so nothing was ever fixable). Words
/// split at '_' and at a lower-to-upper step:
///   PascalCase  StationType_Operator -> StationTypeOperator, wr_str -> WrStr,
///               MAX_COUNT -> MaxCount, wrStr -> WrStr
///   UPPER_CASE  StationType_Operator -> STATION_TYPE_OPERATOR, wrStr -> WR_STR
///   camelCase   StationType_Operator -> stationTypeOperator
/// A candidate CHANGES the identifier, so the caller must ask the index whether
/// it is free (FreeCandidates keeps those ConflictReason clears; BuildNamingFixEdits takes the first).
/// Pure. Pinned by tests\autotest\run_const_casing_word_fix.ps1.</remarks>
function ConstCaseCandidates(const AOldName: string; const AConstCase: TArray<string>): TArray<string>;

type
  /// <summary>Which rename engine a naming target goes through.</summary>
  /// <remarks>nsGlobal: the store-backed TRenameRefactoring.Build on the resolved
  /// symbol's qualified name (method-pascalcase, const-casing, field-name-prefix,
  /// type-name-prefix). nsLocal: the routine-local TRenameRefactoring.BuildLocal at
  /// the finding's own position (local-var-casing, param-name-prefix,
  /// local-field-prefix); no store symbol is resolved for it.</remarks>
  TNamingScope = (nsGlobal, nsLocal);

  /// <summary>Outcome of the TARGET phase (BuildNamingTargets) for one naming finding.</summary>
  /// <remarks>
  /// tsReady: identifier read, at least one candidate, and (nsGlobal) the symbol resolved.
  /// tsNoChange: no candidate differs from OldName (it already conforms), or
  /// local-field-prefix would strip it to an empty or digit-led name.
  /// tsUnresolved: the identifier could not be read from the file, or (nsGlobal) no
  /// store symbol sits at the position and the store does not know the name in that file.
  /// tsStalePosition: (nsGlobal) unresolved at the position although the store DOES hold
  /// a symbol of that name in that file -- the index predates an edit that moved the
  /// declaration; BuildNamingFixEdits counts these in AStaleCount
  /// (pinned by tests\autotest\run_naming_fix_stale_position.ps1).
  /// tsAllCandidatesTaken: never produced by BuildNamingTargets; for a caller that finds
  /// FreeCandidates empty (for instance across several stores) to record that.
  /// </remarks>
  TTargetStatus = (tsReady, tsNoChange, tsUnresolved, tsStalePosition, tsAllCandidatesTaken);

  /// <summary>One naming finding resolved against ONE symbol store, before a new name
  /// is chosen: the identifier, its candidate names and how it is renamed.</summary>
  /// <remarks>Value type; owns nothing. Store-dependent fields are QName, SymLine,
  /// Status and, for type-name-prefix only (its prefix follows the resolved symbol's
  /// kind), Candidates.</remarks>
  TNamingTarget = record
    Key       : string;          // lower(file)|line|col|rule -- one target per key
    Finding   : TLintFinding;
    OldName   : string;          // identifier verbatim from the finding's file span
    Candidates: TArray<string>;  // best first; exactly one for non-const rules
    Scope     : TNamingScope;
    QName     : string;          // Sym.QualifiedName for nsGlobal, '' for nsLocal
    SymLine   : Integer;         // Sym.StartLine (EmitRenameEdits anchor); 0 for nsLocal
    Status    : TTargetStatus;
  end;

/// <summary>TARGET phase: turns the naming findings the fixer handles into one
/// TNamingTarget each, against ONE store -- reads the identifier, synthesizes its
/// candidate names and, for nsGlobal, resolves the declaring symbol. Builds no edits
/// and runs no conflict check.</summary>
/// <param name="AStore">Store used to resolve nsGlobal symbols (and the type kind
/// for type-name-prefix). nil returns nil.</param>
/// <param name="AFindings">Candidate findings; rule-ids the fixer does not handle are
/// omitted from the result.</param>
/// <param name="ANaming">Naming config supplying the casing styles and prefixes.</param>
/// <returns>Targets in finding order, one per Key (the first finding wins). Every
/// status is included; a finding whose processing raises is omitted.</returns>
/// <remarks>Rules handled: method-pascalcase, local-var-casing, const-casing,
/// field-name-prefix, param-name-prefix, type-name-prefix, local-field-prefix.
/// const-casing candidates come from ConstCaseCandidates; every other rule has
/// exactly one candidate. Exercised through BuildNamingFixEdits by
/// run_naming_autofix.ps1, run_naming_prefix_autofix.ps1, run_const_casing_word_fix.ps1
/// and run_naming_fix_stale_position.ps1.</remarks>
function BuildNamingTargets(const AStore: ISymbolStore; const AFindings: TArray<TLintFinding>;
  const ANaming: TNamingConfig): TArray<TNamingTarget>;

/// <summary>The candidates of ATarget that are free to rename to, in their original
/// (preference) order.</summary>
/// <param name="AStore">Store asked about nsGlobal conflicts; nil yields nil for an
/// nsGlobal target.</param>
/// <param name="ATarget">A target from BuildNamingTargets built against AStore.</param>
/// <returns>The free candidates, best first; nil when ATarget.Status is not tsReady
/// or none is free.</returns>
/// <remarks>nsGlobal: a candidate is free when TRenameRefactoring.ConflictReason
/// reports no conflict for ATarget.QName. nsLocal: param-name-prefix and
/// local-field-prefix drop a candidate LocalNameCollides finds in the enclosing
/// routine; local-var-casing keeps its candidate (a pure re-casing cannot collide).
/// Pinned by run_const_casing_word_fix.ps1 (Station_Name -> STATION_NAME because
/// StationName already exists).</remarks>
function FreeCandidates(const AStore: ISymbolStore; const ATarget: TNamingTarget): TArray<string>;

/// <summary>EDIT phase: the text edits that rename ATarget to ANewName, each one
/// POSITION-VERIFIED against the file as it is on disk now.</summary>
/// <param name="AStore">Store backing the nsGlobal rename; nil yields no edits for an
/// nsGlobal target. Unused for nsLocal.</param>
/// <param name="ATarget">A tsReady target from BuildNamingTargets built against AStore.</param>
/// <param name="ANewName">The new identifier. Not checked for conflicts here -- pass a
/// FreeCandidates result.</param>
/// <param name="ASkipped">Out: edits dropped because the recorded span no longer
/// holds the identifier (the stale-position guard); those sites are not written.</param>
/// <returns>The surviving edits; empty when ATarget is not tsReady, ANewName is empty
/// or nothing survived.</returns>
/// <remarks>An edit on the finding's own line takes the finding's verified
/// [StartCol, EndCol) span; every other edit uses the rename engine's coordinates.
/// Each edit carries ExpectText for the applier to re-verify at write time. Pinned
/// by run_autofix_apply_accounting.ps1 and the naming autofix suites.</remarks>
function BuildTargetEdits(const AStore: ISymbolStore; const ATarget: TNamingTarget;
  const ANewName: string; out ASkipped: Integer): TArray<TTextEdit>;

/// <summary>Turns naming findings -- the 3 phase-1 re-casing rules
/// (method-pascalcase, local-var-casing, const-casing) AND the 3 phase-2
/// prefix-adding rules (field-name-prefix, param-name-prefix, type-name-prefix)
/// -- into concrete text edits via the rename engine. For each finding:
/// recovers the offending identifier from AStore's source file at [StartCol,
/// EndCol) on StartLine (naming findings carry no identifier text), synthesizes
/// the target name (SynthesizeCasedName for the 3 case rules; SynthesizePrefixedName
/// for the 3 prefix rules), and -- if it actually differs -- builds rename edits,
/// converting each TRenameEdit to a tekReplaceInLine TTextEdit. Findings whose
/// rule is not one of the six, whose identifier already satisfies the
/// convention, whose owning symbol cannot be resolved, or whose rename has a
/// conflict/collision are skipped (no edit emitted for that finding).</summary>
/// <param name="AStore">Symbol store backing the qualified-name resolution and
/// the global rename engine. Must not be nil.</param>
/// <param name="AFindings">Candidate findings; non-naming rule-ids are ignored.</param>
/// <param name="ANaming">Effective naming config supplying the target casing
/// (MethodCase / LocalCase / ConstCase) and prefixes (FieldPrefix / ParamPrefix /
/// ClassPrefix / ExceptionPrefix / InterfacePrefix / PointerPrefix) per rule.</param>
/// <param name="AFixCount">Out: number of distinct identifiers actually fixed
/// (one per fixed decl, not per edit/site). A finding whose every edit was
/// rejected by the stale-position guard is NOT counted here.</param>
/// <param name="ASkippedCount">Out: number of edits rejected by the
/// stale-position guard -- i.e. sites where the recorded (line, col) no longer
/// holds the identifier being renamed. Non-zero means the store is stale for
/// the target file(s) and the caller should surface a "reindex and re-run"
/// hint; those sites were NOT written.</param>
/// <param name="AStaleCount">Out: number of FINDINGS (not edits) skipped because
/// the store-backed symbol could not be resolved at the finding's position
/// although the store DOES hold a symbol of that name in that file -- the
/// index predates an edit that moved the declaration (spec criterion 12).
/// Counted separately from ASkippedCount, which counts edits. A finding whose
/// name the store does not know in that file at all is not counted.</param>
/// <returns>The applied edit set (empty if nothing was fixable).</returns>
/// <remarks>
/// Re-casing (phase 1) is collision-free in a case-insensitive language
/// (the new name is just a different casing of the same letters), but
/// ConflictReason is still run as defense-in-depth against a same-named sibling.
/// Prefix-adding (phase 2) genuinely CHANGES the identifier, so it is NOT
/// collision-free: field-name-prefix/type-name-prefix route through the global
/// Build path and reuse the same ConflictReason guard; param-name-prefix routes
/// through the routine-local BuildLocal path, which has no collision check of
/// its own, so LocalNameCollides is run first (load-bearing -- see its remarks).
/// For method-pascalcase/field-name-prefix/type-name-prefix, the symbol's
/// separate `implementation` section header (Type.OldName) is renamed too --
/// TRenameRefactoring.Build itself emits that edit (see its ImplStartLine
/// handling), so --fix --apply never leaves a stale, now-uncompilable header
/// referencing the pre-rename name.
/// GUARANTEE (v0.82, stale-index corruption fix): every emitted edit is
/// POSITION-VERIFIED against the file as it is on disk RIGHT NOW -- the span
/// [Col, EndCol) on line Line must actually hold the identifier being renamed
/// (compared case-insensitively, Delphi identifiers being case-insensitive).
/// The rename engine resolves declaration and reference sites from the SYMBOL
/// STORE, whose coordinates are a snapshot; when the file has changed since it
/// was indexed those coordinates point at unrelated text (observed: an
/// identifier glued onto the `then`/`else` keywords, exit code 0). Any edit
/// whose span is out of range or does not hold the expected identifier is
/// DROPPED and counted in ASkippedCount -- never written. When the new name
/// differs from the old in more than letter case, one dropped site drops the
/// whole rename (every edit of it counted in ASkippedCount): a half-applied
/// rename does not compile (pinned by run_fix_stale_index_guard.ps1).
/// COMPOSITION (2026-10-13, pure refactor): BuildNamingTargets, then for each
/// tsReady target FreeCandidates, then BuildTargetEdits with the FIRST free
/// candidate; a tsStalePosition target increments AStaleCount.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.Refactor.NamingFix.BuildNamingTargets, DRagLint.Refactor.NamingFix.BuildTargetEdits, DRagLint.Refactor.NamingFix.FreeCandidates, SameText</para>
/// <para>Catches: Exception (empty)</para>
/// <para>Mutates: AFixCount (out), ASkippedCount (out), AStaleCount (out)</para>
/// <seealso cref="DRagLint.Refactor.NamingFix.BuildNamingTargets"/>
/// <seealso cref="DRagLint.Refactor.NamingFix.BuildTargetEdits"/>
/// <seealso cref="DRagLint.Refactor.NamingFix.FreeCandidates"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BuildNamingFixEdits(const AStore: ISymbolStore;
  const AFindings: TArray<TLintFinding>; const ANaming: TNamingConfig;
  out AFixCount: Integer; out ASkippedCount: Integer; out AStaleCount: Integer): TArray<TTextEdit>;

/// <summary>The identifier a naming finding's span holds in the file today.</summary>
/// <param name="AFile">Path of the source file.</param>
/// <param name="ALine">1-based line of the span.</param>
/// <param name="AStartCol">1-based first column.</param>
/// <param name="AEndCol">Exclusive end column.</param>
/// <returns>The text of the span, or '' when the file or span is not there.</returns>
function ReadIdentifierAt(const AFile: string; ALine, AStartCol, AEndCol: Integer): string;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  System.Classes,
  System.Generics.Collections,
  System.RegularExpressions,
  TreeSitter,
  DRagLint.Diagnostics.ParseCache,
  DRagLint.Refactor.Rename;

function StyleFromConfigText(const AConfigCase: string): TNameStyle;
begin
  if SameText(AConfigCase, 'camelCase') then Result := nsCamelCase
  else if SameText(AConfigCase, 'UPPER_CASE') then Result := nsUpperCase
  else Result := nsPascalCase;
end;

{ Words of an identifier: split at '_' (dropped) and at a lower-to-upper step
  ('StationType' -> Station, Type). Digits stay with the word they follow. }
function IdentWords(const AName: string): TArray<string>;
var
  I    : Integer;
  Start: Integer; { 1-based start of the word being collected; 0 = none }
begin
  Result:= nil;
  Start:= 0;
  for I:= 1 to Length(AName) do
  begin
    if AName[I] = '_' then
    begin
      if Start > 0 then Result:= Result + [Copy(AName, Start, I - Start)];
      Start:= 0;
      Continue;
    end;
    if (Start > 0) and CharInSet(AName[I], ['A'..'Z']) and CharInSet(AName[I - 1], ['a'..'z', '0'..'9']) then
    begin
      Result:= Result + [Copy(AName, Start, I - Start)];
      Start:= 0;
    end;
    if Start = 0 then Start:= I;
  end;
  if Start > 0 then Result:= Result + [Copy(AName, Start, MaxInt)];
end;
{ One word as PascalCase: first letter upper; an ALL-CAPS word ('MAX') is
  lowered after its first letter, a mixed one keeps its inner capitals. }
function PascalWord(const AWord: string): string;
begin
  if AWord = '' then Exit('');
  if (Length(AWord) > 1) and (AWord = UpperCase(AWord)) then
    Result:= UpperCase(AWord[1]) + LowerCase(Copy(AWord, 2, MaxInt))
  else
    Result:= UpperCase(AWord[1]) + Copy(AWord, 2, MaxInt);
end;

function ConstCaseCandidates(const AOldName: string; const AConstCase: TArray<string>): TArray<string>;
var
  Styles: TArray<string>;
  Words : TArray<string>;
  S, W  : string;
  Cand  : string;
  Parts : TArray<string>;
begin
  Result:= nil;
  if AOldName = '' then Exit;
  Styles:= AConstCase;
  if Length(Styles) = 0 then Styles:= ['UPPER_CASE'];
  Words:= IdentWords(AOldName);
  if Length(Words) = 0 then Exit;
  for S in Styles do
  begin
    Parts:= nil;
    for W in Words do
      Parts:= Parts + [if StyleFromConfigText(S) = nsUpperCase then UpperCase(W) else PascalWord(W)];
    case StyleFromConfigText(S) of
      nsUpperCase: Cand:= string.Join('_', Parts);
      nsCamelCase:
        begin
          Cand:= string.Join('', Parts);
          Cand:= LowerCase(Cand[1]) + Copy(Cand, 2, MaxInt);
        end;
    else
      Cand:= string.Join('', Parts);
    end;    if (Cand <> '') and (Cand <> AOldName) and (IndexStr(Cand, Result) < 0) then Result:= Result + [Cand];
  end;
end;

function SynthesizeCasedName(const AOldName: string; AStyle: TNameStyle): string;
begin
  if AOldName = '' then Exit('');
  case AStyle of
    nsUpperCase : Result := UpperCase(AOldName);
    nsCamelCase : Result := LowerCase(AOldName[1]) + Copy(AOldName, 2, MaxInt);
    else          Result := UpperCase(AOldName[1]) + Copy(AOldName, 2, MaxInt); // nsPascalCase
  end;
end;

function SynthesizePrefixedName(const AOldName, APrefix: string): string;
begin
  if (AOldName = '') or (APrefix = '') then Exit(AOldName);
  // Already prefixed? (APrefix followed by an uppercase letter)
  if (Length(AOldName) > Length(APrefix))
     and SameText(Copy(AOldName, 1, Length(APrefix)), APrefix)
     and CharInSet(AOldName[Length(APrefix) + 1], ['A'..'Z']) then Exit(AOldName);
  Result := APrefix + UpperCase(AOldName[1]) + Copy(AOldName, 2, MaxInt);
end;

{ Reads AFile's ALine (1-based) and returns the substring at 1-based columns
  [AStartCol, AEndCol) (exclusive end), matching TLintFinding.StartCol/EndCol's
  convention (see DRagLint.Diagnostics.NamingChecks.EmitAt). Empty string on any
  out-of-range condition. ANSI-decoded like the rest of the refactor engines. }
function ReadIdentifierAt(const AFile: string; ALine, AStartCol, AEndCol: Integer): string;
var
  Lines : TStringList;
  LnText: string;
  Len   : Integer;
begin
  Result:= '';
  if not TFile.Exists(AFile) then Exit;
  if (ALine < 1) or (AStartCol < 1) or (AEndCol <= AStartCol) then Exit;
  Lines:= TStringList.Create;
  try
    Lines.Text:= TEncoding.ANSI.GetString(TFile.ReadAllBytes(AFile));
    if ALine > Lines.Count then Exit;
    LnText:= Lines[ALine - 1];
    if AStartCol > Length(LnText) then Exit;
    Len:= AEndCol - AStartCol;
    if AStartCol + Len - 1 > Length(LnText) then Len:= Length(LnText) - AStartCol + 1;
    if Len <= 0 then Exit;
    Result:= Copy(LnText, AStartCol, Len);
  finally
    Lines.Free;
  end;
end;

{ The symbol declared at (AFilePath, ALine, ACol), or a zeroed TSymbol (Id = 0)
  if none matches. Mirrors TDocLintRules.FixEditsForMissingDoc's re-resolution
  precedent (file+line lookup via FindSymbolsByFile) but also checks StartCol,
  since a naming finding is anchored at the identifier itself (tighter than a
  missing-doc finding's decl-line anchor) and a line can carry more than one
  declared name (e.g. a multi-const declSection).

  AExpectedName is the identifier the caller is about to rename, read verbatim
  from the file's own span. It gates the LINE-ONLY fallback, and it is the root
  fix for the stale-index corruption: the store is a snapshot, so against a file
  edited since it was indexed "whatever symbol the store recorded on line N" is
  routinely a COMPLETELY DIFFERENT identifier -- that is how a rename of
  glyActive came to be emitted at an unrelated site 100+ lines away. A fallback
  match is therefore accepted only when the store symbol's own short name equals
  AExpectedName (case-insensitively, Delphi identifiers being case-insensitive);
  on mismatch we resolve NOTHING rather than resolving wrongly, and the caller
  skips the finding.

  The exact (line, col) match is deliberately left ungated so the normal path is
  bit-for-bit unchanged; the line-only fallback is the one that exists solely to
  absorb StartCol drift (e.g. a method decl whose store StartCol is the
  `procedure` keyword, not the identifier) and so is the one that needs a leash.
  An empty AExpectedName disables the fallback entirely. }
function ResolveSymbolAt(const AStore: ISymbolStore; const AFilePath: string;
  ALine, ACol: Integer; const AExpectedName: string): TSymbol;
var
  Syms: TArray<TSymbol>;
  Sym : TSymbol;
begin
  Result:= Default(TSymbol);
  Syms:= AStore.FindSymbolsByFile(AFilePath);
  for Sym in Syms do
    if (Sym.StartLine = ALine) and (Sym.StartCol = ACol) then Exit(Sym);
  { Fall back to a line-only match (defensive -- covers any StartCol drift
    between the naming checker's node position and the indexer's decl position),
    but ONLY for a symbol that actually bears the name being renamed. }
  if AExpectedName = '' then Exit;
  for Sym in Syms do
    if (Sym.StartLine = ALine) and SameText(Sym.Name, AExpectedName) then Exit(Sym);
end;

{ True when ANewName already exists as ANOTHER param or local variable in the
  routine enclosing (AFile, ALine, ACol) -- i.e. the rename target renamed at
  that position, if driven through BuildLocal, would collide with a sibling
  in the same scope. THE COLLISION GUARD for param-name-prefix (load-bearing):
  unlike phase-1 re-casing, prefix-adding CHANGES the identifier (x -> pX), and
  BuildLocal itself has NO collision check of its own (it is a pure mechanical
  AST rename). Without this guard, `procedure P(x: Integer); var pX: Integer;`
  would rename the param x to pX and produce two identically-named locals in
  the same routine -- a silent, now-uncompilable collision that --fix --apply
  would happily write to disk.

  Implementation: reuses TAstParseCache the same way TRenameRefactoring.BuildLocal
  does (same cache, same tree, no re-parse cost), finds the identifier node at
  (ALine, ACol), locates its smallest enclosing defProc by byte span, then scans
  that defProc's header args (declArg) AND its local var sections (declVar) for
  any OTHER identifier (different byte position than the target) matching
  ANewName case-insensitively. This is a full AST scope scan (not the text-span
  fallback the brief allows for infeasible cases) -- BuildLocal's own helpers
  (EnclosingProc/declArg/declVar shapes) are reused directly, so a proper scope
  scan was straightforward here, not infeasible.
  Deliberately conservative in ONE direction only: it does not attempt to
  reason about nested-routine shadowing (a nested defProc's own params/locals
  are not scanned) -- this mirrors BuildLocal's own shadowing treatment (a
  nested redeclaration stops the walk rather than being treated as identical
  scope), so a collision inside a nested routine is out of scope for both the
  rename and this guard. }
function LocalNameCollides(const AFile: string; ALine, ACol: Integer; const ANewName: string): Boolean;
var
  PF        : TParsedFile;
  Src       : TBytes;
  TargetByte: Integer;
  OwnerProc : TTSNode;

  function NStr(const N: TTSNode): string;
  var S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte);
    E:= Integer(N.EndByte);
    L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  function NLine(const N: TTSNode): Integer;
  begin Result:= Integer(N.StartPoint.Row) + 1; end;

  function NColOf(const N: TTSNode): Integer;
  begin Result:= Integer(N.StartPoint.Column) + 1; end;

  { Find the identifier node at (ALine,ACol). Returns null node if none. }
  function FindIdentAt(const N: TTSNode): TTSNode;
  var I: Integer; Ch, R: TTSNode;
  begin
    Result:= Default(TTSNode);
    if N.IsNull then Exit;
    if (N.NodeType = 'identifier') and (NLine(N) = ALine) and (NColOf(N) = ACol) then
      Exit(N);
    for I:= 0 to N.NamedChildCount - 1 do
    begin
      Ch:= N.NamedChild(I);
      R:= FindIdentAt(Ch);
      if not R.IsNull then Exit(R);
    end;
  end;

  { Smallest enclosing defProc of a node, by byte span (mirrors BuildLocal's
    own EnclosingProc helper). }
  function EnclosingProc(const N: TTSNode; const ABest: TTSNode): TTSNode;
  var I: Integer; Ch: TTSNode;
  begin
    Result:= ABest;
    if N.IsNull then Exit;
    if (N.NodeType = 'defProc')
      and (Integer(N.StartByte) <= TargetByte) and (Integer(N.EndByte) >= TargetByte) then
      Result:= N;
    for I:= 0 to N.NamedChildCount - 1 do
    begin
      Ch:= N.NamedChild(I);
      Result:= EnclosingProc(Ch, Result);
    end;
  end;

  { True when AN (a declArg or declVar node) declares ANewName at a byte
    position OTHER than the target identifier's own -- i.e. a genuine sibling,
    not the very identifier being renamed. Name identifiers in both declArg
    and declVar sit before the 'type' field child (mirrors BuildLocal's
    ScanDeclArgs and the local-var-casing checker's declVar walk). }
  function DeclHasOtherName(const AN: TTSNode): Boolean;
  var
    TN       : TTSNode;
    TypeStart: Integer;
    J        : Integer;
    Id       : TTSNode;
  begin
    Result:= False;
    TN:= AN.ChildByField('type');
    TypeStart:= MaxInt;
    if not TN.IsNull then TypeStart:= Integer(TN.StartByte);
    for J:= 0 to AN.NamedChildCount - 1 do
    begin
      Id:= AN.NamedChild(J);
      if Id.NodeType <> 'identifier' then Continue;
      if Integer(Id.StartByte) >= TypeStart then Continue;
      if Integer(Id.StartByte) = TargetByte then Continue; // the identifier being renamed itself
      if SameText(Trim(NStr(Id)), ANewName) then Exit(True);
    end;
  end;

  { Scan OwnerProc's own header args (declArg) and body-local var sections
    (declVar) for a sibling named ANewName. Does not descend into nested
    defProc subtrees (see remarks above -- mirrors BuildLocal's shadowing
    treatment). }
  function ScanScope(const N: TTSNode): Boolean;
  var I: Integer; Ch: TTSNode;
  begin
    Result:= False;
    if N.IsNull then Exit;
    if (not (N = OwnerProc)) and (N.NodeType = 'defProc') then Exit; // nested routine: out of scope
    if (N.NodeType = 'declArg') or (N.NodeType = 'declVar') then
      if DeclHasOtherName(N) then Exit(True);
    for I:= 0 to N.NamedChildCount - 1 do
    begin
      Ch:= N.NamedChild(I);
      if ScanScope(Ch) then Exit(True);
    end;
  end;

var
  IdNode: TTSNode;
begin
  Result:= False;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;

  IdNode:= FindIdentAt(PF.Tree.RootNode);
  if IdNode.IsNull then Exit;
  TargetByte:= Integer(IdNode.StartByte);

  OwnerProc:= EnclosingProc(PF.Tree.RootNode, Default(TTSNode));
  if OwnerProc.IsNull then Exit;

  { Also scan the OwnerProc's header (declArg lives under header.args, not
    directly under OwnerProc's own named children in the defProc shape used
    by declProc forward decls -- but for a defProc body the header IS a named
    child, so the generic ScanScope recursion already reaches it). }
  Result:= ScanScope(OwnerProc);
end;

{ True when the store holds a symbol named AName (case-insensitively) declared
  in AFilePath -- at ANY position. Separates "the index is stale for this
  file" from "the index does not know this name here at all". }
function DeclaredInFile(const AStore: ISymbolStore; const AFilePath, AName: string): Boolean;
begin
  for var S: TSymbol in AStore.FindSymbolsByFile(AFilePath) do
    if SameText(S.Name, AName) then Exit(True);
  Result:= False;
end;

{ property-accessor-name (lane A5B): the finding sits on the accessor's name
  INSIDE the property declaration, which is a use, not a declaration -- so
  ResolveSymbolAt finds nothing there. The target is the member of the
  property's own class that bears AOldName: exactly one, else nothing (an
  inherited accessor, or an overload, is left for a human). }
function ResolveAccessor(const AStore: ISymbolStore; const AF: TLintFinding; const AOldName: string): TSymbol;
var
  Syms   : TArray<TSymbol>;
  Sym    : TSymbol;
  ClassId: Int64;
  Hits   : Integer;
begin
  Result:= Default(TSymbol);
  Syms:= AStore.FindSymbolsByFile(AF.FilePath);
  ClassId:= 0;
  for Sym in Syms do
    if (Sym.Kind = skProperty) and (Sym.StartLine <= AF.StartLine) and (Sym.EndLine >= AF.StartLine) then ClassId:= Sym.ParentId;
  if ClassId = 0 then Exit;
  Hits:= 0;
  for Sym in Syms do
    if (Sym.ParentId = ClassId) and (Sym.Kind in [skField, skMethod]) and SameText(Sym.Name, AOldName) then
    begin
      Inc(Hits);
      Result:= Sym;
    end;
  if Hits <> 1 then Result:= Default(TSymbol);
end;

{ The rename candidates for finding AF whose identifier is AOldName, best first;
  nil when no candidate differs from AOldName or no legal one exists. }
function NamingCandidates(const AStore: ISymbolStore; const AF: TLintFinding;
  const AOldName: string; const ANaming: TNamingConfig): TArray<string>;
var
  NewName: string;
  Prefix : string;
  Sym    : TSymbol;
begin
  Result:= nil;
  { local-field-prefix is the MIRROR of the phase-2 prefix rules: the
    others ADD a missing prefix, this one STRIPS a prefix a local should
    never have worn. It is the safest rename in the family -- scope is a
    single routine body, so no call site anywhere can be affected -- which
    is why it routes through BuildLocal with the same collision guard
    param-name-prefix uses rather than the store-backed global rename. }
  if SameText(AF.RuleId, 'local-field-prefix') then
  begin
    NewName:= AOldName;
    if (ANaming.FieldPrefix <> '') and NewName.StartsWith(ANaming.FieldPrefix, True) then
      NewName:= Copy(NewName, Length(ANaming.FieldPrefix) + 1, MaxInt);
    { A local called exactly the prefix ("F") would strip to '', and one
      whose remainder starts with a digit ("F1") would produce an illegal
      identifier. Leave both for a human -- silently emitting a broken
      rename is worse than reporting the finding unfixed. }
    if (NewName = '') or CharInSet(NewName[1], ['0'..'9']) then Exit;
  end
  else if SameText(AF.RuleId, 'property-accessor-name') then
  begin
    { The message names both legal names (DeclParityChecks.CheckAccessorNames):
      "should be named F<Prop> or Get<Prop>" -- the first for a field, the
      second for a method accessor. }
    var AccM: TMatch:= TRegEx.Match(AF.Message, 'should be named ([A-Za-z_]\w*) or ([A-Za-z_]\w*)$');
    if not AccM.Success then Exit;
    Sym:= ResolveAccessor(AStore, AF, AOldName);
    if Sym.Id = 0 then Exit;
    NewName:= if Sym.Kind = skField then AccM.Groups[1].Value else AccM.Groups[2].Value;
  end
  else if SameText(AF.RuleId, 'const-casing') then
    { Word-aware; ConstCaseCandidates already drops the unchanged name. }
    Exit(ConstCaseCandidates(AOldName, ANaming.ConstCase))
  else if SameText(AF.RuleId, 'method-pascalcase') then
    NewName:= SynthesizeCasedName(AOldName, StyleFromConfigText(ANaming.MethodCase))
  else if SameText(AF.RuleId, 'local-var-casing') then
    NewName:= SynthesizeCasedName(AOldName, StyleFromConfigText(ANaming.LocalCase))
  else
  begin
    { Phase 2: prefix-adding. Pick the configured prefix per rule; for
      type-name-prefix, resolve the symbol's kind to choose between
      ClassPrefix/ExceptionPrefix/InterfacePrefix/PointerPrefix (default
      ClassPrefix when ambiguous/unresolved, mirroring the checker's own
      conservative default). }
    if SameText(AF.RuleId, 'field-name-prefix') then Prefix:= ANaming.FieldPrefix
    else if SameText(AF.RuleId, 'param-name-prefix') then Prefix:= ANaming.ParamPrefix
    else if TryExpectedPrefixFromTypePrefixMessage(AF.Message, Prefix) then
    begin
      // type-name-prefix: the letter comes from the finding itself. A second
      // classification here drifted (EKeyViolation -> TEKeyViolation,
      // 2026-10-16). The message is built by TypePrefixFindingMessage in
      // Lint.Config -- one source for checker and fixer.
    end
    else if IsTypePrefixGapMessage(AF.Message) then
      Exit // index-gap finding: the E/T letter is undecidable, never rename
    else { type-name-prefix, message not ours: legacy fallback }
    begin
      Sym:= ResolveSymbolAt(AStore, AF.FilePath, AF.StartLine, AF.StartCol, AOldName);
      if (Sym.Id <> 0) and (Sym.Kind = skInterface) then Prefix:= ANaming.InterfacePrefix
      else if (Sym.Id <> 0) and (Sym.Kind = skClass) and (ANaming.ExceptionPrefix <> '')
              and AStore.IsDescendantOf(Sym.Name, 'Exception', Sym.FileId) then Prefix:= ANaming.ExceptionPrefix
      else Prefix:= ANaming.ClassPrefix; // default: class, or unresolved/ambiguous
    end;
    NewName:= SynthesizePrefixedName(AOldName, Prefix);
  end;
  if NewName <> AOldName then Result:= [NewName]; // equal: already correct -- nothing to do
end;

function BuildNamingTargets(const AStore: ISymbolStore; const AFindings: TArray<TLintFinding>;
  const ANaming: TNamingConfig): TArray<TNamingTarget>;
var
  Seen   : TDictionary<string, Boolean>;
  F      : TLintFinding;
  T      : TNamingTarget;
  Sym    : TSymbol;
  IsLocal: Boolean;
begin
  Result:= nil;
  if AStore = nil then Exit;
  Seen:= TDictionary<string, Boolean>.Create;
  try
    for F in AFindings do
    begin
      IsLocal:= SameText(F.RuleId, 'local-var-casing') or SameText(F.RuleId, 'param-name-prefix')
                or SameText(F.RuleId, 'local-field-prefix');
      if not (IsLocal or SameText(F.RuleId, 'method-pascalcase') or SameText(F.RuleId, 'const-casing')
          or SameText(F.RuleId, 'field-name-prefix') or SameText(F.RuleId, 'type-name-prefix')
          or SameText(F.RuleId, 'property-accessor-name')) then Continue;

      try
        T:= Default(TNamingTarget);
        { One fix per (file,line,col) decl -- multiple findings could target the
          same identifier (defensive; mirrors FixEditsForMissingDoc's Seen guard). }
        T.Key:= LowerCase(F.FilePath) + '|' + IntToStr(F.StartLine) + '|' + IntToStr(F.StartCol) + '|' + LowerCase(F.RuleId);
        if Seen.ContainsKey(T.Key) then Continue;
        Seen.Add(T.Key, True);
        T.Finding:= F;
        T.Scope:= if IsLocal then nsLocal else nsGlobal;

        { Naming findings carry no identifier text -- recover it from the
          source span the checker anchored to. }
        T.OldName:= ReadIdentifierAt(F.FilePath, F.StartLine, F.StartCol, F.EndCol);
        if T.OldName = '' then
          T.Status:= tsUnresolved
        else
        begin
          T.Candidates:= NamingCandidates(AStore, F, T.OldName, ANaming);
          if Length(T.Candidates) = 0 then
            T.Status:= tsNoChange
          else if T.Scope = nsLocal then
            T.Status:= tsReady
          else
          begin
            { Global rename: needs a symbol resolved from the store for its
              qualified name. Unresolved at this position but still known by
              name in this file means the index predates an edit that moved the
              declaration: "stale index", not "no fixable findings" (spec
              criterion 12). }
            Sym:= if SameText(F.RuleId, 'property-accessor-name') then ResolveAccessor(AStore, F, T.OldName)
                  else ResolveSymbolAt(AStore, F.FilePath, F.StartLine, F.StartCol, T.OldName);
            if Sym.Id = 0 then
              T.Status:= if DeclaredInFile(AStore, F.FilePath, T.OldName) then tsStalePosition else tsUnresolved
            else
            begin
              T.QName:= Sym.QualifiedName;
              T.SymLine:= Sym.StartLine;
              T.Status:= tsReady;
            end;
          end;
        end;
        Result:= Result + [T];
      except
        { A single malformed finding must not abort the whole fix sweep. }
      end;
    end;
  finally
    Seen.Free;
  end;
end;

function FreeCandidates(const AStore: ISymbolStore; const ATarget: TNamingTarget): TArray<string>;
var
  F         : TLintFinding;
  Cand      : string;
  LocalGuard: Boolean;
begin
  Result:= nil;
  if ATarget.Status <> tsReady then Exit;
  if (ATarget.Scope = nsGlobal) and (AStore = nil) then Exit;
  F:= ATarget.Finding;
  { Routine-local prefix rules: UNLIKE local-var-casing (collision-free
    re-casing), prefix-adding/stripping genuinely changes the identifier, so
    BuildLocal -- which has no collision check of its own -- needs
    LocalNameCollides. }
  LocalGuard:= SameText(F.RuleId, 'param-name-prefix') or SameText(F.RuleId, 'local-field-prefix');
  for Cand in ATarget.Candidates do
    if ATarget.Scope = nsLocal then
    begin
      if not (LocalGuard and LocalNameCollides(F.FilePath, F.StartLine, F.StartCol, Cand)) then
        Result:= Result + [Cand];
    end
    { ASK THE INDEX (owner, 2026-10-13): a name that already exists is not free. }
    else if TRenameRefactoring.ConflictReason(AStore, ATarget.QName, Cand) = '' then
      Result:= Result + [Cand];
end;

function BuildTargetEdits(const AStore: ISymbolStore; const ATarget: TNamingTarget;
  const ANewName: string; out ASkipped: Integer): TArray<TTextEdit>;
var
  Edits: TList<TTextEdit>;
  Cache: TDictionary<string, TStringList>;

  { ANSI-decoded lines of APath, read AT MOST ONCE per file (mirrors
    BuildAutofixEdits' LinesFor). An unreadable/absent file yields an empty
    list, which makes every span check on it fail -- i.e. skip, not write. }
  function LinesFor(const APath: string): TStringList;
  begin
    if not Cache.TryGetValue(APath, Result) then
    begin
      Result:= TStringList.Create;
      if TFile.Exists(APath) then Result.Text:= TEncoding.ANSI.GetString(TFile.ReadAllBytes(APath));
      Cache.Add(APath, Result);
    end;
  end;

  { THE STALE-POSITION GUARD. True only when APath, AS IT IS ON DISK NOW, holds
    AExpected at 1-based columns [ACol, AEndCol) of line ALine, compared
    case-insensitively (Delphi identifiers are case-insensitive, and a re-casing
    rename differs from the old name ONLY in case).

    Load-bearing: the rename engine resolves decl/reference sites from the
    SYMBOL STORE, which is a snapshot. Against a file edited since it was
    indexed those coordinates address unrelated text, and TTextEditApplier's
    tekReplaceInLine clamps EndCol but NOT Col -- so a column past end-of-line
    silently APPENDS the new name to whatever the line ends with (observed:
    `then` + `GlyActive` -> `thenGlyActive`, exit code 0). Every out-of-range
    condition below is therefore a MISMATCH (skip), never an exception and
    never a write. }
  function SpanHoldsIdent(const APath: string; ALine, ACol, AEndCol: Integer;
    const AExpected: string): Boolean;
  var
    SL  : TStringList;
    Ln  : string     ;
  begin
    Result:= False;
    if AExpected = '' then Exit;
    if (ALine < 1) or (ACol < 1) or (AEndCol <= ACol) then Exit;
    if (AEndCol - ACol) <> Length(AExpected) then Exit; { span width must match the identifier }
    SL:= LinesFor(APath);
    if ALine > SL.Count then Exit;                      { past EOF }
    Ln:= SL[ALine - 1];
    if (AEndCol - 1) > Length(Ln) then Exit;            { past end-of-line }
    Result:= SameText(Copy(Ln, ACol, AEndCol - ACol), AExpected);
  end;

  { AFindingLine/AFindingCol/AFindingEndCol: the ORIGINATING finding's own
    (already lint-verified) identifier span. TRenameRefactoring.Build's
    declaration-site edit uses the store symbol's Sym.StartLine/StartCol --
    which for a method decl is the declProc SPAN start (the `procedure`/
    `function` keyword column), NOT the identifier's own column. Blindly
    trusting RE.Col + Length(OldName) there replaces the wrong slice of text
    (observed: "procedure dosomething" -> "Dosomethingosomething", eating part
    of the keyword). Guard against that: any rename edit that lands on the
    SAME line as the finding gets the finding's own verified StartCol/EndCol
    instead of the engine's Col/OldName-length; every other edit (reference
    sites, resolved from the refs table via FindCallersByName, which are
    identifier-accurate) is trusted as-is.

    AOldName is the identifier VERBATIM as it stands in the finding's own file
    span -- the text SpanHoldsIdent must find at a finding-coordinate edit. For
    every other (engine-coordinate) edit the expected text is RE.OldName, which
    TRenameRefactoring.Build/BuildLocal always set to the bare short name. An
    edit that fails the check is dropped and counted in ASkipped; the caller
    counts a fix only when at least one edit of this rename SURVIVED, so a
    fully-skipped finding never inflates the CLI's "applied N fix(es)". }
  procedure EmitRenameEdits(const ARenameEdits: TArray<TRenameEdit>;
    AFindingLine, AFindingCol, AFindingEndCol: Integer; const AOldName: string);
  var
    RE     : TRenameEdit;
    TE     : TTextEdit  ;
    Want   : string     ;
  begin
    for RE in ARenameEdits do
    begin
      TE:= Default(TTextEdit);
      TE.FilePath:= RE.FilePath;
      TE.Kind    := tekReplaceInLine;
      TE.Line    := RE.Line;
      if (RE.Line = AFindingLine) and (AFindingCol > 0) and (AFindingEndCol > AFindingCol) then
      begin
        TE.Col   := AFindingCol;
        TE.EndCol:= AFindingEndCol;
        Want     := AOldName;
      end
      else
      begin
        TE.Col   := RE.Col;
        TE.EndCol:= RE.Col + Length(RE.OldName);
        Want     := RE.OldName;
      end;
      TE.Text:= RE.NewName;
      { Belt and braces: the same expectation the local SpanHoldsIdent check
        enforces here is ALSO carried on the edit itself, so TTextEditApplier
        re-verifies it against the file at WRITE time -- covering the window
        between building the edit set and applying it, and covering any future
        caller that reaches the applier by another route. }
      TE.ExpectText:= Want;
      { Never write a position the file no longer backs -- see SpanHoldsIdent. }
      if not SpanHoldsIdent(TE.FilePath, TE.Line, TE.Col, TE.EndCol, Want) then
      begin
        Inc(ASkipped);
        Continue;
      end;
      Edits.Add(TE);
    end;
  end;

var
  F: TLintFinding;
begin
  ASkipped:= 0;
  Result:= nil;
  if (ATarget.Status <> tsReady) or (ANewName = '') then Exit;
  if (ATarget.Scope = nsGlobal) and (AStore = nil) then Exit;
  F:= ATarget.Finding;

  Edits:= TList<TTextEdit>.Create;
  Cache:= TDictionary<string, TStringList>.Create;
  try
    if ATarget.Scope = nsLocal then
      EmitRenameEdits(TRenameRefactoring.BuildLocal(F.FilePath, F.StartLine, F.StartCol, ANewName),
        F.StartLine, F.StartCol, F.EndCol, ATarget.OldName)
    else if SameText(F.RuleId, 'property-accessor-name') then
    begin
      { The finding sits on the PROPERTY line, which the refs table does not
        hold, so the finding-span override below would hand the declaration
        line the property line's columns. Instead: an engine edit whose column
        is the `procedure` / `function` keyword moves to the ONE whole-word
        occurrence of the old name on its own line (none or several: left as
        is, so the span guard skips it), and the property's `read X` /
        `write X` is renamed from the finding's own verified span. }
      var REs: TArray<TRenameEdit>:= TRenameRefactoring.Build(AStore, ATarget.QName, ANewName);
      var OnProp: Boolean:= False;
      for var I:= 0 to High(REs) do
      begin
        var SL: TStringList:= LinesFor(REs[I].FilePath);
        if (REs[I].Line < 1) or (REs[I].Line > SL.Count) then Continue;
        OnProp:= OnProp or ((REs[I].Line = F.StartLine) and SameText(REs[I].FilePath, F.FilePath));
        if SameText(Copy(SL[REs[I].Line - 1], REs[I].Col, Length(REs[I].OldName)), REs[I].OldName) then Continue;
        var Ms: TMatchCollection:= TRegEx.Matches(SL[REs[I].Line - 1], '\b' + TRegEx.Escape(REs[I].OldName) + '\b', [roIgnoreCase]);
        if Ms.Count = 1 then REs[I].Col:= Ms[0].Index;
      end;
      if not OnProp then
      begin
        var PE: TRenameEdit;
        PE.FilePath:= F.FilePath;
        PE.Line    := F.StartLine;
        PE.Col     := F.StartCol;
        PE.OldName := ATarget.OldName;
        PE.NewName := ANewName;
        REs:= REs + [PE];
      end;
      EmitRenameEdits(REs, 0, 0, 0, ATarget.OldName);
    end
    else
      { method-pascalcase / const-casing / field-name-prefix / type-name-prefix:
        Build also covers the symbol's separate implementation-section header
        (Type.OldName) itself, so no local workaround is needed here. }
      EmitRenameEdits(TRenameRefactoring.Build(AStore, ATarget.QName, ANewName),
        ATarget.SymLine, F.StartCol, F.EndCol, ATarget.OldName);
    Result:= Edits.ToArray;
  finally
    for var SL: TStringList in Cache.Values do SL.Free;
    Cache.Free;
    Edits.Free;
  end;
end;

function BuildNamingFixEdits(const AStore: ISymbolStore;
  const AFindings: TArray<TLintFinding>; const ANaming: TNamingConfig;
  out AFixCount: Integer; out ASkippedCount: Integer; out AStaleCount: Integer): TArray<TTextEdit>;
var
  T        : TNamingTarget;
  FreeNames: TArray<string>;
  TargetTE : TArray<TTextEdit>;
  Skipped  : Integer;
begin
  AFixCount:= 0;
  ASkippedCount:= 0;
  AStaleCount:= 0;
  Result:= nil;
  if AStore = nil then Exit;

  for T in BuildNamingTargets(AStore, AFindings, ANaming) do
  begin
    if T.Status = tsStalePosition then Inc(AStaleCount);
    if T.Status <> tsReady then Continue;
    try
      { The first FREE candidate wins; with none free the finding is left
        alone rather than renamed into a clash. }
      FreeNames:= FreeCandidates(AStore, T);
      if Length(FreeNames) = 0 then Continue;
      TargetTE:= BuildTargetEdits(AStore, T, FreeNames[0], Skipped);
      { All or nothing once the new name differs in more than letter case
        (glyActive -> GLY_ACTIVE, Foo -> TFoo): renaming the sites the guard
        kept and leaving the skipped ones writes a unit that no longer
        compiles. The multi-project path refuses the same way. }
      if (Skipped > 0) and (not SameText(T.OldName, FreeNames[0])) then
      begin
        Inc(Skipped, Length(TargetTE));
        TargetTE:= nil;
      end;
      Inc(ASkippedCount, Skipped);
      if Length(TargetTE) > 0 then
      begin
        Result:= Result + TargetTE;
        Inc(AFixCount);
      end;
    except
      { A single malformed finding must not abort the whole fix sweep. }
    end;
  end;
end;

end.
