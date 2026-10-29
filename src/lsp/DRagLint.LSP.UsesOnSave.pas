unit DRagLint.LSP.UsesOnSave;

{ Auto uses on save (plan docs\superpowers\plans\2026-10-29-auto-uses-on-save.md).
  VS Code's editor.codeActionsOnSave asks the server for code actions of a
  named source.* kind and applies EVERY one it gets back without asking. This
  unit re-emits the uses-clause edits the quickfixes make under those two
  kinds, behind gates that keep a silent edit from being a guess:

    source.addMissingImports   -- only for a finding with exactly ONE fix (D1);
                                  an ambiguous name stays quickfix-only.
    source.removeUnusedImports -- only when the buffer IS what the index saw and
                                  the whole index is fresh (D2), and never for an
                                  entry of a uses clause holding a {$ directive
                                  (D3). ONE action per file carries every removal:
                                  the client applies each returned action against
                                  the text it had BEFORE the first, so two
                                  line-deleting actions would land off by a line.

  The quickfix actions are untouched; these are extra actions. The removal
  quickfix (light bulb) is offered for the client's diagnostic and edits the
  BUFFER -- the user picks it, so it needs no freshness gate. }

interface

uses
  System.JSON,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces;

const
  /// <summary>The code-action kinds this server answers on save, advertised in
  /// initialize under codeActionProvider.codeActionKinds beside 'quickfix'.</summary>
  /// <remarks>[0] adds a missing unit, [1] removes an unused one. A client
  /// enables either through editor.codeActionsOnSave.</remarks>
  KINDS_ON_SAVE: array[0..1] of string = ('source.addMissingImports', 'source.removeUnusedImports');

  /// <summary>The rule whose findings source.removeUnusedImports removes.</summary>
  UNUSED_UNIT_RULE = 'unused-unit-in-uses';

type
  /// <summary>The three facts that decide whether a removal may be applied
  /// silently on save (plan D2/D3).</summary>
  /// <remarks>All three False by default (Default(TDropGate)): an unset gate
  /// never opens.</remarks>
  TDropGate = record
    /// <summary>The buffer's sha256 equals the indexed file's content hash:
    /// the index has seen THIS text, including any reference just typed.</summary>
    BufferMatchesIndex: Boolean;
    /// <summary>ProbeIndexFreshness answered fvFresh: no indexed file changed on
    /// disk since the index was built (fvUnknown counts as not fresh).</summary>
    IndexFresh: Boolean;
    /// <summary>The uses clause holding the finding carries a {$ directive, so
    /// the clause the compiler sees is not the text the rule read.</summary>
    UsesClauseHasDirective: Boolean;
  end;

  /// <summary>Builds the on-save (source.*) code actions for the uses clause,
  /// and the removal quickfix.</summary>
  /// <remarks>Stateless; every function is thread-safe. Each returned JSON
  /// object is new and the caller owns it.</remarks>
  TUsesOnSave = class
  public
    /// <summary>The source.addMissingImports twin of a unit-missing-from-uses
    /// quickfix, or nil when the finding is not safe to fix silently.</summary>
    /// <param name="ADiag">The unit-missing-from-uses diagnostic; cloned into the
    /// action's diagnostics list. Must not be nil.</param>
    /// <param name="AFixes">The diagnostic's data.fixes. Exactly one entry is
    /// required (D1): two or more (a circular-reference alternative) or none (an
    /// ambiguous name, declared in several units) yield nil.</param>
    /// <param name="AQuickfixEdit">The WorkspaceEdit of that single fix's
    /// quickfix; cloned, so the source action applies the SAME edit.</param>
    /// <returns>A new action {title, kind: 'source.addMissingImports',
    /// diagnostics: [ADiag], edit}; nil when AFixes.Count &lt;&gt; 1 or an argument
    /// is nil. The caller owns the result.</returns>
    class function AddMissingImportAction(const ADiag: TJSONObject; const AFixes: TJSONArray;
      const AQuickfixEdit: TJSONObject): TJSONObject; static;

    /// <summary>Computes the drop gate for APath.</summary>
    /// <param name="AStore">The index that owns APath; nil yields a closed gate.</param>
    /// <param name="APath">The file, as the index stores it.</param>
    /// <param name="ABufferText">The editor's text, decoded as the indexer
    /// decodes file bytes (ANSI), so an unchanged file hashes identically.</param>
    /// <param name="AFindingLine">1-based line of the finding whose clause
    /// decides UsesClauseHasDirective; 0 leaves that field False.</param>
    /// <returns>The gate; open only when BufferMatchesIndex and IndexFresh and
    /// not UsesClauseHasDirective.</returns>
    /// <remarks>Reads the store (one hash lookup plus one stat per indexed file);
    /// never raises.</remarks>
    class function ComputeDropGate(const AStore: ISymbolStore; const APath, ABufferText: string;
      AFindingLine: Integer = 0): TDropGate; static;

    /// <summary>True when the uses clause containing ALine holds a compiler
    /// directive ({$ or (*$) between its `uses` keyword and its ';'.</summary>
    /// <param name="AText">The unit's source text.</param>
    /// <param name="ALine">1-based line; a line in no uses clause yields False.</param>
    /// <returns>Whether that clause carries a directive.</returns>
    /// <remarks>Pure. `uses` and ';' inside // { } (* *) comments and '...'
    /// strings are skipped, so a comment never opens or closes a clause.</remarks>
    class function UsesClauseHasDirectiveAt(const AText: string; ALine: Integer): Boolean; static;

    /// <summary>The source.removeUnusedImports action for one file, or nil.</summary>
    /// <param name="ADiags">The unused-unit-in-uses diagnostics the edit removes;
    /// cloned into the action. Must hold at least one.</param>
    /// <param name="AEdit">The WorkspaceEdit removing every one of them; cloned.</param>
    /// <param name="AGate">The drop gate (ComputeDropGate).</param>
    /// <returns>A new action {title, kind: 'source.removeUnusedImports',
    /// diagnostics, edit} only when AGate.BufferMatchesIndex and AGate.IndexFresh
    /// and not AGate.UsesClauseHasDirective, and AEdit and ADiags are non-empty;
    /// otherwise nil. The caller owns the result.</returns>
    class function RemoveUnusedImportAction(const ADiags: TJSONArray; const AEdit: TJSONObject;
      const AGate: TDropGate): TJSONObject; static;

    /// <summary>One WorkspaceEdit turning AOldText into ANewText: a single
    /// TextEdit over the span between their common prefix and suffix.</summary>
    /// <param name="AFileUri">The document URI the edit targets.</param>
    /// <param name="AOldText">The text the client holds.</param>
    /// <param name="ANewText">The text it must end up with.</param>
    /// <returns>A new WorkspaceEdit, or nil when the two texts are equal.</returns>
    /// <remarks>Pure. Line/character are counted in UTF-16 units over AOldText,
    /// LSP's default position encoding.</remarks>
    class function TextChangeEdit(const AFileUri, AOldText, ANewText: string): TJSONObject; static;

    /// <summary>The text after removing every unused-unit-in-uses entry of
    /// AFindings from AText, exactly as `lint --fix` removes them.</summary>
    /// <param name="APath">The file; only findings on it are used.</param>
    /// <param name="AText">The file's text.</param>
    /// <param name="AFindings">The findings; other rules are ignored.</param>
    /// <returns>The edited text; AText when nothing could be removed (an
    /// initialization-section tier, a layout the fixer declines, a stale line).</returns>
    /// <remarks>Uses the uses-clause core the CLI fixer uses (RemoveUsesEntry,
    /// with its overlap check), on AText instead of the disk copy.</remarks>
    class function RemoveUnusedEntries(const APath, AText: string; const AFindings: TArray<TLintFinding>): string; static;

    /// <summary>The unused-unit-in-uses findings of a `lint --json` answer.</summary>
    /// <param name="AJson">The child lint's stdout (a JSON array).</param>
    /// <param name="APath">The linted file; findings on another file are dropped.</param>
    /// <returns>Findings with index (1-based) positions; empty on bad JSON.</returns>
    class function UnusedFindingsFromLintJson(const AJson, APath: string): TArray<TLintFinding>; static;

    /// <summary>The finding an LSP diagnostic was made from
    /// (TLspCompletion.DiagnosticsFromLintJson's inverse).</summary>
    /// <param name="ADiag">A drag-lint diagnostic; nil yields a finding with an empty RuleId.</param>
    /// <param name="APath">The file the diagnostic belongs to.</param>
    /// <returns>RuleId, FilePath, 1-based positions and Message.</returns>
    class function FindingOfDiagnostic(const ADiag: TJSONObject; const APath: string): TLintFinding; static;

    /// <summary>A drag-lint diagnostic for AFinding, as the full-rules path
    /// publishes it.</summary>
    /// <param name="AFinding">The finding (1-based positions).</param>
    /// <returns>A new diagnostic object; the caller owns it.</returns>
    class function DiagnosticOfFinding(const AFinding: TLintFinding): TJSONObject; static;

    /// <summary>"Remove unused unit" quickfixes for the unused-unit-in-uses
    /// diagnostics on lines AStartLine..AEndLine, editing the buffer.</summary>
    /// <param name="APath">The file.</param>
    /// <param name="AFileUri">Its document URI.</param>
    /// <param name="ABufferText">The editor's text.</param>
    /// <param name="ADiagnostics">The request's context diagnostics; nil yields none.</param>
    /// <param name="AStartLine">First requested line, 1-based.</param>
    /// <param name="AEndLine">Last requested line, 1-based.</param>
    /// <returns>A new array, one quickfix per removable finding.</returns>
    class function RemoveUnusedQuickfixes(const APath, AFileUri, ABufferText: string;
      const ADiagnostics: TJSONArray; AStartLine, AEndLine: Integer): TJSONArray; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Hash,
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  System.Math,
  DRagLint.Index.Freshness,
  DRagLint.Refactor.TextEdit,
  DRagLint.Fix.ProjectWide;

const
  { The fixer's own decline: an initialization-section unit may be linked for its side effect. }
  INIT_TIER_TEXT = 'HAS an initialization section';
  { A (*$ ... *) compiler directive opener. }
  PAREN_DIRECTIVE = '(*$';

class function TUsesOnSave.AddMissingImportAction(const ADiag: TJSONObject; const AFixes: TJSONArray;
  const AQuickfixEdit: TJSONObject): TJSONObject;
begin
  Result:= nil;
  if (ADiag = nil) or (AFixes = nil) or (AQuickfixEdit = nil) or (AFixes.Count <> 1) then Exit;
  var Title: string:= 'Add unit to uses';
  if AFixes.Items[0] is TJSONObject then
    Title:= TJSONObject(AFixes.Items[0]).GetValue<string>('title', Title);
  var DiagList: TJSONArray:= TJSONArray.Create;
  DiagList.AddElement(ADiag.Clone as TJSONObject);
  Result:= TJSONObject.Create;
  Result.AddPair('title'      , Title);
  Result.AddPair('kind'       , KINDS_ON_SAVE[0]);
  Result.AddPair('diagnostics', DiagList);
  Result.AddPair('edit'       , AQuickfixEdit.Clone as TJSONObject);
end;

class function TUsesOnSave.ComputeDropGate(const AStore: ISymbolStore; const APath, ABufferText: string;
  AFindingLine: Integer): TDropGate;
begin
  Result:= Default(TDropGate);
  if (AStore = nil) or (APath = '') then Exit;
  try
    { the indexer's own formula (TIndexer.IndexFile): sha256 of the ANSI-decoded bytes }
    Result.BufferMatchesIndex:= AStore.FileShaMatches(APath, THashSHA2.GetHashString(ABufferText));
    Result.IndexFresh        := ProbeIndexFreshness(AStore).Verdict = fvFresh;
  except
    on Exception do Result:= Default(TDropGate); { a store that cannot answer closes the gate }
  end;
  if AFindingLine > 0 then
    Result.UsesClauseHasDirective:= UsesClauseHasDirectiveAt(ABufferText, AFindingLine);
end;

{ Advances AI past a span of AText ending in ACloser, counting the line breaks inside. }
procedure SkipTo(const AText, ACloser: string; var AI, ALine: Integer);
begin
  var N: Integer:= Length(AText);
  while (AI <= N) and (Copy(AText, AI, Length(ACloser)) <> ACloser) do
  begin
    if AText[AI] = #10 then Inc(ALine);
    Inc(AI);
  end;
  Inc(AI, Length(ACloser));
end;

{ Consumes one line break, comment or string at AI (True), else leaves AI alone
  (False). ADirective: the consumed comment was a compiler directive. }
function SkipTrivia(const AText: string; var AI, ALine: Integer; out ADirective: Boolean): Boolean;
begin
  ADirective:= False;
  Result:= True;
  var Two: string:= Copy(AText, AI, 2);
  if AText[AI] = #10 then
  begin
    Inc(ALine);
    Inc(AI);
  end
  else if Two = '//' then
    while (AI <= Length(AText)) and (AText[AI] <> #10) do Inc(AI)
  else if AText[AI] = '{' then
  begin
    ADirective:= Two = '{$';
    Inc(AI);
    SkipTo(AText, '}', AI, ALine);
  end
  else if Two = '(*' then
  begin
    ADirective:= Copy(AText, AI, Length(PAREN_DIRECTIVE)) = PAREN_DIRECTIVE;
    Inc(AI, 2);
    SkipTo(AText, '*)', AI, ALine);
  end
  else if AText[AI] = '''' then
  begin
    Inc(AI);
    while (AI <= Length(AText)) and not CharInSet(AText[AI], ['''', #10]) do Inc(AI);
    Inc(AI);
  end
  else Result:= False;
end;

class function TUsesOnSave.UsesClauseHasDirectiveAt(const AText: string; ALine: Integer): Boolean;
const
  IDENT_CHARS: TSysCharSet = ['A'..'Z', 'a'..'z', '0'..'9', '_'];
begin
  Result:= False;
  if ALine < 1 then Exit;
  var I: Integer:= 1;
  var Line: Integer:= 1;
  var InClause: Boolean:= False;
  var ClauseDirective: Boolean:= False;
  var ClauseStart: Integer:= 0;
  while I <= Length(AText) do
  begin
    var IsDirective: Boolean;
    if SkipTrivia(AText, I, Line, IsDirective) then
      ClauseDirective:= ClauseDirective or (InClause and IsDirective)
    else if CharInSet(AText[I], IDENT_CHARS) then
    begin
      var S: Integer:= I;
      while (I <= Length(AText)) and CharInSet(AText[I], IDENT_CHARS) do Inc(I);
      if (not InClause) and SameText(Copy(AText, S, I - S), 'uses') then
      begin
        InClause:= True;
        ClauseDirective:= False;
        ClauseStart:= Line;
      end;
    end
    else if (AText[I] = ';') and InClause then
    begin
      if InRange(ALine, ClauseStart, Line) then Exit(ClauseDirective);
      InClause:= False;
      Inc(I);
    end
    else Inc(I);
  end;
end;

class function TUsesOnSave.RemoveUnusedImportAction(const ADiags: TJSONArray; const AEdit: TJSONObject;
  const AGate: TDropGate): TJSONObject;
begin
  Result:= nil;
  if not (AGate.BufferMatchesIndex and AGate.IndexFresh) or AGate.UsesClauseHasDirective then Exit;
  if (AEdit = nil) or (ADiags = nil) or (ADiags.Count = 0) then Exit;
  Result:= TJSONObject.Create;
  Result.AddPair('title'      , if ADiags.Count = 1 then 'Remove unused unit' else Format('Remove %d unused units', [ADiags.Count]));
  Result.AddPair('kind'       , KINDS_ON_SAVE[1]);
  Result.AddPair('diagnostics', ADiags.Clone as TJSONArray);
  Result.AddPair('edit'       , AEdit.Clone as TJSONObject);
end;

class function TUsesOnSave.TextChangeEdit(const AFileUri, AOldText, ANewText: string): TJSONObject;

  function PosOf(AOffset: Integer): TJSONObject; { AOffset: 0-based index into AOldText }
  begin
    var Ln: Integer:= 0;
    var LineStart: Integer:= 0;
    for var K: Integer:= 1 to AOffset do
      if AOldText[K] = #10 then
      begin
        Inc(Ln);
        LineStart:= K;
      end;
    Result:= TJSONObject.Create;
    Result.AddPair('line'     , TJSONNumber.Create(Ln));
    Result.AddPair('character', TJSONNumber.Create(AOffset - LineStart));
  end;

begin
  Result:= nil;
  if AOldText = ANewText then Exit;
  var LO: Integer:= Length(AOldText);
  var LN: Integer:= Length(ANewText);
  var Pre: Integer:= 0;
  while (Pre < LO) and (Pre < LN) and (AOldText[Pre + 1] = ANewText[Pre + 1]) do Inc(Pre);
  var Suf: Integer:= 0;
  while (Suf < LO - Pre) and (Suf < LN - Pre) and (AOldText[LO - Suf] = ANewText[LN - Suf]) do Inc(Suf);
  { never split a CRLF pair: a position between #13 and #10 is not a position in the document }
  while (Pre > 0) and (AOldText[Pre] = #13) do Dec(Pre);
  while (Suf > 0) and (LO - Suf >= 1) and (AOldText[LO - Suf + 1] = #10) and (AOldText[LO - Suf] = #13) do Dec(Suf);
  var Range: TJSONObject:= TJSONObject.Create;
  Range.AddPair('start', PosOf(Pre));
  Range.AddPair('end'  , PosOf(LO - Suf));
  var TE: TJSONObject:= TJSONObject.Create;
  TE.AddPair('range'  , Range);
  TE.AddPair('newText', Copy(ANewText, Pre + 1, LN - Pre - Suf));
  var Edits: TJSONArray:= TJSONArray.Create;
  Edits.AddElement(TE);
  var Changes: TJSONObject:= TJSONObject.Create;
  Changes.AddPair(AFileUri, Edits);
  Result:= TJSONObject.Create;
  Result.AddPair('changes', Changes);
end;

class function TUsesOnSave.RemoveUnusedEntries(const APath, AText: string; const AFindings: TArray<TLintFinding>): string;
var
  Lines: TStringList;
  One  : TList<TTextEdit>;
  All  : TList<TTextEdit>;
  Taken: TDictionary<Integer, Boolean>;
begin
  Result:= AText;
  Lines:= TStringList.Create;
  One  := TList<TTextEdit>.Create;
  All  := TList<TTextEdit>.Create;
  Taken:= TDictionary<Integer, Boolean>.Create;
  try
    Lines.Text:= AText;
    { the guards of DRagLint.Fix.Store.FixUnusedUnits, in the same order }
    for var F0: TLintFinding in AFindings do
    begin
      if not SameText(F0.RuleId, UNUSED_UNIT_RULE) or not SameText(F0.FilePath, APath) then Continue;
      if ContainsText(F0.Message, INIT_TIER_TEXT) then Continue;
      var F: TLintFinding:= WithCharColumns(F0, Lines);
      var M: TMatch:= TRegEx.Match(F.Message, '^Unit ''([A-Za-z_][\w.]*)''');  // dl:ok duplicate-code@0039 -- REVIEWED 2026-10-29: deliberately the same guards as DRagLint.Fix.Store.FixUnusedUnits, on the BUFFER text instead of the disk copy; the LSP guard pins byte parity with lint --fix
      if not M.Success or (F.StartLine < 1) or (F.StartLine > Lines.Count) then Continue;
      if not SameText(StringReplace(Copy(Lines[F.StartLine - 1], F.StartCol, F.EndCol - F.StartCol), ' ', '', [rfReplaceAll]),
                      M.Groups[1].Value) then Continue;
      One.Clear;
      if not RemoveUsesEntry(F, Lines, One) then Continue;
      var E: TTextEdit:= One[0];
      var Clash: Boolean:= False;
      for var L: Integer:= E.Line to Max(E.Line, E.EndLine) do Clash:= Clash or Taken.ContainsKey(L);
      if Clash then Continue;
      for var L: Integer:= E.Line to Max(E.Line, E.EndLine) do Taken.AddOrSetValue(L, True);
      All.Add(E);
    end;
    if All.Count > 0 then Result:= TTextEditApplier.ApplyToText(APath, AText, All.ToArray);
  finally
    Taken.Free;
    All.Free;
    One.Free;
    Lines.Free;
  end;
end;

class function TUsesOnSave.UnusedFindingsFromLintJson(const AJson, APath: string): TArray<TLintFinding>;
begin
  Result:= nil;
  var Root: TJSONValue:= TJSONObject.ParseJSONValue(AJson);
  if Root = nil then Exit;
  try
    if Root is not TJSONArray then Exit;
    for var Item: TJSONValue in TJSONArray(Root) do
    begin
      if Item is not TJSONObject then Continue;
      var O: TJSONObject:= TJSONObject(Item);
      var Rule: string:= O.GetValue<string>('rule', O.GetValue<string>('rule_id', ''));
      if not SameText(Rule, UNUSED_UNIT_RULE) then Continue;
      var FilePath: string:= O.GetValue<string>('file', O.GetValue<string>('file_path', APath));
      if not SameText(ExpandFileName(FilePath), ExpandFileName(APath)) then Continue;
      var F: TLintFinding:= Default(TLintFinding);
      F.RuleId   := Rule;
      F.FilePath := APath;
      F.StartLine:= O.GetValue<Integer>('start_line', 0);
      F.StartCol := O.GetValue<Integer>('start_col' , 1);
      F.EndLine  := O.GetValue<Integer>('end_line'  , F.StartLine);
      F.EndCol   := O.GetValue<Integer>('end_col'   , F.StartCol);
      F.Severity := O.GetValue<string>('severity', 'warning');
      F.Message  := O.GetValue<string>('message', '');
      Result:= Result + [F];
    end;
  finally
    Root.Free;
  end;
end;

class function TUsesOnSave.FindingOfDiagnostic(const ADiag: TJSONObject; const APath: string): TLintFinding;
begin
  Result:= Default(TLintFinding);
  if ADiag = nil then Exit;
  Result.RuleId   := ADiag.GetValue<string>('code', '');
  Result.FilePath := APath;
  Result.StartLine:= ADiag.GetValue<Integer>('range.start.line'     , -1) + 1;
  Result.StartCol := ADiag.GetValue<Integer>('range.start.character', 0) + 1;
  Result.EndLine  := ADiag.GetValue<Integer>('range.end.line'       , Result.StartLine - 1) + 1;
  Result.EndCol   := ADiag.GetValue<Integer>('range.end.character'  , Result.StartCol - 1) + 1;
  Result.Message  := ADiag.GetValue<string>('message', '');
end;

class function TUsesOnSave.DiagnosticOfFinding(const AFinding: TLintFinding): TJSONObject;

  function Pos0(ALine, ACol: Integer): TJSONObject;
  begin
    Result:= TJSONObject.Create;
    Result.AddPair('line'     , TJSONNumber.Create(ALine - 1));
    Result.AddPair('character', TJSONNumber.Create(ACol  - 1));
  end;

begin
  var Range: TJSONObject:= TJSONObject.Create;
  Range.AddPair('start', Pos0(AFinding.StartLine, AFinding.StartCol));
  Range.AddPair('end'  , Pos0(AFinding.EndLine  , AFinding.EndCol  ));
  Result:= TJSONObject.Create;
  Result.AddPair('range'  , Range);
  Result.AddPair('source' , 'drag-lint');
  Result.AddPair('code'   , AFinding.RuleId);
  Result.AddPair('message', AFinding.Message);
end;

class function TUsesOnSave.RemoveUnusedQuickfixes(const APath, AFileUri, ABufferText: string;
  const ADiagnostics: TJSONArray; AStartLine, AEndLine: Integer): TJSONArray;
begin
  Result:= TJSONArray.Create;
  if ADiagnostics = nil then Exit;
  for var I: Integer:= 0 to ADiagnostics.Count - 1 do
  begin
    if ADiagnostics.Items[I] is not TJSONObject then Continue;
    var Diag: TJSONObject:= TJSONObject(ADiagnostics.Items[I]);
    var F: TLintFinding:= FindingOfDiagnostic(Diag, APath);
    if not SameText(F.RuleId, UNUSED_UNIT_RULE) then Continue;
    if (F.StartLine < AStartLine) or (F.StartLine > AEndLine) then Continue;
    var Edit: TJSONObject:= TextChangeEdit(AFileUri, ABufferText, RemoveUnusedEntries(APath, ABufferText, [F]));
    if Edit = nil then Continue;
    var DiagList: TJSONArray:= TJSONArray.Create;
    DiagList.AddElement(Diag.Clone as TJSONObject);
    var M: TMatch:= TRegEx.Match(F.Message, '^Unit ''([A-Za-z_][\w.]*)''');
    var Act: TJSONObject:= TJSONObject.Create;
    Act.AddPair('title'      , if M.Success then Format('Remove unused unit %s', [M.Groups[1].Value]) else 'Remove unused unit');
    Act.AddPair('kind'       , 'quickfix');
    Act.AddPair('diagnostics', DiagList);
    Act.AddPair('edit'       , Edit);
    Result.AddElement(Act);
  end;
end;

end.
