unit DRagLint.Refactor.NamingFix;

interface

uses
  DRagLint.Core.Interfaces,
  DRagLint.Core.Model,
  DRagLint.Lint.Config,
  DRagLint.Refactor.TextEdit;

type
  /// <summary>Target casing styles, matching TNamingConfig's textual vocabulary.</summary>
  TNameStyle = (nsPascalCase, nsCamelCase, nsUpperCase);

/// <summary>Maps a TNamingConfig case string ('PascalCase' | 'camelCase' |
/// 'UPPER_CASE') to a TNameStyle. Unknown/empty -> nsPascalCase.</summary>
function StyleFromConfigText(const AConfigCase: string): TNameStyle;

/// <summary>Returns AOldName re-cased to AStyle WITHOUT changing its letters or
/// inserting separators (a pure, collision-free re-casing in a case-insensitive
/// language). PascalCase upper-cases the first char; camelCase lower-cases it;
/// UPPER_CASE upper-cases the whole identifier. Idempotent. Empty -> ''.</summary>
/// <param name="AOldName">The offending identifier verbatim.</param>
/// <param name="AStyle">Target style.</param>
/// <returns>The re-cased identifier.</returns>
/// <remarks>DECISION: phase-1 is pure re-casing only -- no separator
/// insertion. UPPER_CASE therefore yields e.g. MAXCOUNT, not MAX_COUNT
/// (word-boundary detection is a phase-2 concern; this keeps phase-1
/// collision-free and mechanical).</remarks>
function SynthesizeCasedName(const AOldName: string; AStyle: TNameStyle): string;

/// <summary>Turns naming re-casing findings (method-pascalcase, local-var-casing,
/// const-casing) into concrete text edits via the rename engine. For each
/// finding: recovers the offending identifier from AStore's source file at
/// [StartCol, EndCol) on StartLine (naming findings carry no identifier text),
/// synthesizes the target-style name, and -- if it actually differs -- builds
/// rename edits (TRenameRefactoring.BuildLocal for local-var-casing; Build via a
/// store-resolved qualified name for method-pascalcase/const-casing), converting
/// each TRenameEdit to a tekReplaceInLine TTextEdit. Findings whose rule is not
/// one of the three, whose identifier is already correctly cased, whose owning
/// symbol cannot be resolved, or whose rename has a conflict are skipped (no
/// edit emitted for that finding).</summary>
/// <param name="AStore">Symbol store backing the qualified-name resolution and
/// the global rename engine. Must not be nil.</param>
/// <param name="AFindings">Candidate findings; non-naming rule-ids are ignored.</param>
/// <param name="ANaming">Effective naming config supplying the target casing
/// per rule (MethodCase / LocalCase / ConstCase).</param>
/// <param name="AFixCount">Out: number of distinct identifiers actually fixed
/// (one per fixed decl, not per edit/site).</param>
/// <returns>The applied edit set (empty if nothing was fixable).</returns>
/// <remarks>Re-casing is collision-free in a case-insensitive language (the new
/// name is just a different casing of the same letters), but ConflictReason is
/// still run as defense-in-depth against a same-named sibling -- and is
/// load-bearing once phase 2 adds separator-inserting styles that could produce
/// a name distinct from the original. For method-pascalcase, the method's
/// separate `implementation` section header (Type.OldName) is renamed too --
/// TRenameRefactoring.Build itself emits that edit (see its ImplStartLine
/// handling), so --fix --apply never leaves a stale, now-uncompilable header
/// referencing the pre-rename name.</remarks>
function BuildNamingFixEdits(const AStore: ISymbolStore;
  const AFindings: TArray<TLintFinding>; const ANaming: TNamingConfig;
  out AFixCount: Integer): TArray<TTextEdit>;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  System.Generics.Collections,
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
  declared name (e.g. a multi-const declSection). }
function ResolveSymbolAt(const AStore: ISymbolStore; const AFilePath: string;
  ALine, ACol: Integer): TSymbol;
var
  Syms: TArray<TSymbol>;
  Sym : TSymbol;
begin
  Result:= Default(TSymbol);
  Syms:= AStore.FindSymbolsByFile(AFilePath);
  for Sym in Syms do
    if (Sym.StartLine = ALine) and (Sym.StartCol = ACol) then Exit(Sym);
  { Fall back to a line-only match (defensive -- covers any StartCol drift
    between the naming checker's node position and the indexer's decl position). }
  for Sym in Syms do
    if Sym.StartLine = ALine then Exit(Sym);
end;

function BuildNamingFixEdits(const AStore: ISymbolStore;
  const AFindings: TArray<TLintFinding>; const ANaming: TNamingConfig;
  out AFixCount: Integer): TArray<TTextEdit>;
var
  Edits: TList<TTextEdit>;
  Seen : TDictionary<string, Boolean>;

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
    identifier-accurate) is trusted as-is. }
  procedure EmitRenameEdits(const ARenameEdits: TArray<TRenameEdit>;
    AFindingLine, AFindingCol, AFindingEndCol: Integer);
  var
    RE: TRenameEdit;
    TE: TTextEdit;
  begin
    if Length(ARenameEdits) = 0 then Exit;
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
      end
      else
      begin
        TE.Col   := RE.Col;
        TE.EndCol:= RE.Col + Length(RE.OldName);
      end;
      TE.Text:= RE.NewName;
      Edits.Add(TE);
    end;
    Inc(AFixCount);
  end;

var
  F        : TLintFinding;
  OldName  : string;
  Style    : TNameStyle;
  NewName  : string;
  Sym      : TSymbol;
  DedupKey : string;
begin
  AFixCount:= 0;
  Result:= nil;
  if AStore = nil then Exit;

  Edits:= TList<TTextEdit>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for F in AFindings do
    begin
      if not (SameText(F.RuleId, 'method-pascalcase') or SameText(F.RuleId, 'local-var-casing')
          or SameText(F.RuleId, 'const-casing')) then Continue;

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

        if SameText(F.RuleId, 'method-pascalcase') then Style:= StyleFromConfigText(ANaming.MethodCase)
        else if SameText(F.RuleId, 'local-var-casing') then Style:= StyleFromConfigText(ANaming.LocalCase)
        else { const-casing } begin
          if Length(ANaming.ConstCase) > 0 then Style:= StyleFromConfigText(ANaming.ConstCase[0])
          else Style:= StyleFromConfigText('UPPER_CASE');
        end;

        NewName:= SynthesizeCasedName(OldName, Style);
        if NewName = OldName then Continue; // already exactly cased -- nothing to do

        if SameText(F.RuleId, 'local-var-casing') then
          EmitRenameEdits(TRenameRefactoring.BuildLocal(F.FilePath, F.StartLine, F.StartCol, NewName), F.StartLine, F.StartCol, F.EndCol)
        else
        begin
          { method-pascalcase / unit-level const-casing: global rename, needs a
            symbol resolved from the store for its qualified name. Build now
            also covers the method's separate implementation-section header
            (Type.OldName) itself, so no local workaround is needed here. }
          Sym:= ResolveSymbolAt(AStore, F.FilePath, F.StartLine, F.StartCol);
          if Sym.Id = 0 then Continue; // unresolved symbol -- report NEEDS_CONTEXT by skipping
          if TRenameRefactoring.ConflictReason(AStore, Sym.QualifiedName, NewName) <> '' then Continue; // conflict -- skip
          EmitRenameEdits(TRenameRefactoring.Build(AStore, Sym.QualifiedName, NewName), Sym.StartLine, F.StartCol, F.EndCol);
        end;
      except
        { A single malformed finding must not abort the whole fix sweep. }
      end;
    end;
    Result:= Edits.ToArray;
  finally
    Seen.Free;
    Edits.Free;
  end;
end;

end.
