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
  /// Used by: declaration (DRagLint.Refactor.NamingFix.pas), DRagLint.Refactor.NamingFix.BuildNamingFixEdits (DRagLint.Refactor.NamingFix.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TNameStyle = (nsPascalCase, nsCamelCase, nsUpperCase);

/// <summary>Maps a TNamingConfig case string ('PascalCase' | 'camelCase' |
/// 'UPPER_CASE') to a TNameStyle. Unknown/empty -> nsPascalCase.</summary>
/// <param name="AConfigCase"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->Observed: nsCamelCase; nsUpperCase; nsPascalCase.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.Refactor.NamingFix.BuildNamingFixEdits (DRagLint.Refactor.NamingFix.pas)
/// Calls: SameText
/// Pure
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
/// Called from: DRagLint.Refactor.NamingFix.BuildNamingFixEdits (DRagLint.Refactor.NamingFix.pas)
/// Calls: Copy, LowerCase, UpperCase
/// Returns: UpperCase(AOldName); LowerCase(AOldName[1]) + Copy(AOldName, 2, MaxInt); UpperCase(AOldName[1]) + Copy(AOldName, 2, MaxInt)
/// Pure
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
/// Called from: DRagLint.Refactor.NamingFix.BuildNamingFixEdits (DRagLint.Refactor.NamingFix.pas)
/// Calls: CharInSet, Copy, SameText, UpperCase
/// Returns: APrefix + UpperCase(AOldName[1]) + Copy(AOldName, 2, MaxInt)
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function SynthesizePrefixedName(const AOldName, APrefix: string): string;

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
/// DROPPED and counted in ASkippedCount -- never written.
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas)
/// Calls: CharInSet, Copy, Default, DRagLint.Core.Interfaces.ISymbolStore.IsDescendantOf, DRagLint.Refactor.NamingFix.BuildNamingFixEdits.EmitRenameEdits, DRagLint.Refactor.NamingFix.LocalNameCollides, DRagLint.Refactor.NamingFix.ReadIdentifierAt, DRagLint.Refactor.NamingFix.ResolveSymbolAt, DRagLint.Refactor.NamingFix.StyleFromConfigText, DRagLint.Refactor.NamingFix.SynthesizeCasedName (+9 more)
/// Returns: nil; Edits.ToArray
/// Complexity: 35 (cyclomatic, outer body), 239 lines (full implementation)
/// Mutates: AFixCount (out), ASkippedCount (out)
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.IsDescendantOf"/>
/// <seealso cref="DRagLint.Refactor.NamingFix.BuildNamingFixEdits.EmitRenameEdits"/>
/// <seealso cref="DRagLint.Refactor.NamingFix.LocalNameCollides"/>
/// <seealso cref="DRagLint.Refactor.NamingFix.ReadIdentifierAt"/>
/// <seealso cref="DRagLint.Refactor.NamingFix.ResolveSymbolAt"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BuildNamingFixEdits(const AStore: ISymbolStore;
  const AFindings: TArray<TLintFinding>; const ANaming: TNamingConfig;
  out AFixCount: Integer; out ASkippedCount: Integer): TArray<TTextEdit>;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  System.Generics.Collections,
  TreeSitter,
  TreeSitterLib,
  DRagLint.Diagnostics.ParseCache,
  DRagLint.Refactor.Rename;

function StyleFromConfigText(const AConfigCase: string): TNameStyle;
begin
  if SameText(AConfigCase, 'camelCase') then Result := nsCamelCase
  else if SameText(AConfigCase, 'UPPER_CASE') then Result := nsUpperCase
  else Result := nsPascalCase;
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
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
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

function BuildNamingFixEdits(const AStore: ISymbolStore;
  const AFindings: TArray<TLintFinding>; const ANaming: TNamingConfig;
  out AFixCount: Integer; out ASkippedCount: Integer): TArray<TTextEdit>;
var
  Edits: TList<TTextEdit>;
  Seen : TDictionary<string, Boolean>;
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
    edit that fails the check is dropped and counted in ASkippedCount; AFixCount
    is incremented only when at least one edit of this rename SURVIVED, so a
    fully-skipped finding never inflates the CLI's "applied N fix(es)". }
  procedure EmitRenameEdits(const ARenameEdits: TArray<TRenameEdit>;
    AFindingLine, AFindingCol, AFindingEndCol: Integer; const AOldName: string);
  var
    RE     : TRenameEdit;
    TE     : TTextEdit  ;
    Want   : string     ;
    Emitted: Integer    ;
  begin
    if Length(ARenameEdits) = 0 then Exit;
    Emitted:= 0;
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
        Inc(ASkippedCount);
        Continue;
      end;
      Edits.Add(TE);
      Inc(Emitted);
    end;
    if Emitted > 0 then Inc(AFixCount);
  end;

var
  F         : TLintFinding;
  OldName   : string;
  Style     : TNameStyle;
  NewName   : string;
  Sym       : TSymbol;
  DedupKey  : string;
  IsPrefixRule: Boolean;
  Prefix    : string;
begin
  AFixCount:= 0;
  ASkippedCount:= 0;
  Result:= nil;
  if AStore = nil then Exit;

  Edits:= TList<TTextEdit>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  Cache:= TDictionary<string, TStringList>.Create;
  try
    for F in AFindings do
    begin
      IsPrefixRule:= SameText(F.RuleId, 'field-name-prefix') or SameText(F.RuleId, 'param-name-prefix')
                     or SameText(F.RuleId, 'type-name-prefix');
      if not (IsPrefixRule or SameText(F.RuleId, 'method-pascalcase') or SameText(F.RuleId, 'local-var-casing')
          or SameText(F.RuleId, 'const-casing') or SameText(F.RuleId, 'local-field-prefix')) then Continue;

      try
        { One fix per (file,line,col) decl -- multiple findings could target the
          same identifier (defensive; mirrors FixEditsForMissingDoc's Seen guard). }
        DedupKey:= LowerCase(F.FilePath) + '|' + IntToStr(F.StartLine) + '|' + IntToStr(F.StartCol) + '|' + LowerCase(F.RuleId);
        if Seen.ContainsKey(DedupKey) then Continue;
        Seen.Add(DedupKey, True);

        { Naming findings carry no identifier text -- recover it from the
          source span the checker anchored to. }
        OldName:= ReadIdentifierAt(F.FilePath, F.StartLine, F.StartCol, F.EndCol);
        if OldName = '' then Continue;

        { local-field-prefix is the MIRROR of the phase-2 prefix rules: the
          others ADD a missing prefix, this one STRIPS a prefix a local should
          never have worn. It is the safest rename in the family -- scope is a
          single routine body, so no call site anywhere can be affected -- which
          is why it routes through BuildLocal with the same collision guard
          param-name-prefix uses rather than the store-backed global rename. }
        if SameText(F.RuleId, 'local-field-prefix') then
        begin
          NewName:= OldName;
          if (ANaming.FieldPrefix <> '') and NewName.StartsWith(ANaming.FieldPrefix, True) then
            NewName:= Copy(NewName, Length(ANaming.FieldPrefix) + 1, MaxInt);
          { A local called exactly the prefix ("F") would strip to '', and one
            whose remainder starts with a digit ("F1") would produce an illegal
            identifier. Leave both for a human -- silently emitting a broken
            rename is worse than reporting the finding unfixed. }
          if (NewName = '') or CharInSet(NewName[1], ['0'..'9']) then Continue;
        end
        else if IsPrefixRule then
        begin
          { Phase 2: prefix-adding. Pick the configured prefix per rule; for
            type-name-prefix, resolve the symbol's kind to choose between
            ClassPrefix/ExceptionPrefix/InterfacePrefix/PointerPrefix (default
            ClassPrefix when ambiguous/unresolved, mirroring the checker's own
            conservative default). }
          if SameText(F.RuleId, 'field-name-prefix') then Prefix:= ANaming.FieldPrefix
          else if SameText(F.RuleId, 'param-name-prefix') then Prefix:= ANaming.ParamPrefix
          else { type-name-prefix }
          begin
            Sym:= ResolveSymbolAt(AStore, F.FilePath, F.StartLine, F.StartCol, OldName);
            if (Sym.Id <> 0) and (Sym.Kind = skInterface) then Prefix:= ANaming.InterfacePrefix
            else if (Sym.Id <> 0) and (Sym.Kind = skClass) and (ANaming.ExceptionPrefix <> '')
                    and AStore.IsDescendantOf(Sym.Name, 'Exception', Sym.FileId) then Prefix:= ANaming.ExceptionPrefix
            else Prefix:= ANaming.ClassPrefix; // default: class, or unresolved/ambiguous
          end;
          NewName:= SynthesizePrefixedName(OldName, Prefix);
        end
        else
        begin
          if SameText(F.RuleId, 'method-pascalcase') then Style:= StyleFromConfigText(ANaming.MethodCase)
          else if SameText(F.RuleId, 'local-var-casing') then Style:= StyleFromConfigText(ANaming.LocalCase)
          else { const-casing } begin
            if Length(ANaming.ConstCase) > 0 then Style:= StyleFromConfigText(ANaming.ConstCase[0])
            else Style:= StyleFromConfigText('UPPER_CASE');
          end;
          NewName:= SynthesizeCasedName(OldName, Style);
        end;
        if NewName = OldName then Continue; // already correct -- nothing to do

        if SameText(F.RuleId, 'local-var-casing') then
          EmitRenameEdits(TRenameRefactoring.BuildLocal(F.FilePath, F.StartLine, F.StartCol, NewName), F.StartLine, F.StartCol, F.EndCol, OldName)
        else if SameText(F.RuleId, 'param-name-prefix') or SameText(F.RuleId, 'local-field-prefix') then
        begin
          { Routine-local rename. UNLIKE local-var-casing (collision-free
            re-casing), prefix-adding genuinely changes the identifier, so
            BuildLocal -- which has no collision check of its own -- needs the
            NEW guard: skip the whole fix if NewName already exists as another
            local/param in the same routine scope. }
          if LocalNameCollides(F.FilePath, F.StartLine, F.StartCol, NewName) then Continue; // collision -- skip
          EmitRenameEdits(TRenameRefactoring.BuildLocal(F.FilePath, F.StartLine, F.StartCol, NewName), F.StartLine, F.StartCol, F.EndCol, OldName);
        end
        else
        begin
          { method-pascalcase / const-casing / field-name-prefix / type-name-prefix:
            global rename, needs a symbol resolved from the store for its
            qualified name. Build now also covers the symbol's separate
            implementation-section header (Type.OldName) itself, so no local
            workaround is needed here. }
          Sym:= ResolveSymbolAt(AStore, F.FilePath, F.StartLine, F.StartCol, OldName);
          if Sym.Id = 0 then Continue; // unresolved symbol -- report NEEDS_CONTEXT by skipping
          if TRenameRefactoring.ConflictReason(AStore, Sym.QualifiedName, NewName) <> '' then Continue; // conflict -- skip
          EmitRenameEdits(TRenameRefactoring.Build(AStore, Sym.QualifiedName, NewName), Sym.StartLine, F.StartCol, F.EndCol, OldName);
        end;
      except
        { A single malformed finding must not abort the whole fix sweep. }
      end;
    end;
    Result:= Edits.ToArray;
  finally
    for var SL: TStringList in Cache.Values do SL.Free;
    Cache.Free;
    Seen.Free;
    Edits.Free;
  end;
end;

end.
