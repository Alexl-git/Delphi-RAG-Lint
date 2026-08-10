unit DRagLint.Refactor.TextEdit;

{ Range insert/delete text edits for the non-rename refactors (find-unit,
  safe-delete). TRenameRefactoring.Apply is token-replace only; this applier
  does whole-line insert/delete + single-line character insert, with the same
  ANSI / CRLF / .bak discipline. Builders (TFindUnitRefactoring, TSafeDelete-
  Refactoring) are added in later tasks. }

interface

uses
  System.SysUtils, System.Classes, System.IOUtils,
  System.Generics.Collections, System.Generics.Defaults,
  DRagLint.Core.Model, DRagLint.Core.Interfaces;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: declaration (DRagLint.Refactor.TextEdit.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTextEditKind = (tekInsertInLine, tekInsertLines, tekDeleteLines, tekReplaceInLine);

  /// <summary>One text edit. tekInsertInLine: insert Text into line Line at
  /// 1-based column Col. tekInsertLines: insert Text (CRLF-joined) after line
  /// Line (0 = top). tekDeleteLines: delete lines Line..EndLine inclusive.
  /// tekReplaceInLine: on line Line, replace the characters in 1-based columns
  /// [Col, EndCol) (EndCol exclusive) with Text (Text may be '' to delete).</summary>
  /// <remarks>
  /// ExpectText is the OPTIONAL stale-position guard for
  /// tekReplaceInLine (ignored by every other kind). When it is non-empty the
  /// applier verifies -- case-insensitively, Delphi identifiers being
  /// case-insensitive -- that the file AS IT IS ON DISK really holds ExpectText
  /// at [Col, EndCol) of line Line, and DROPS the edit when it does not.
  /// Producers whose coordinates come from the SYMBOL STORE (a snapshot that
  /// goes stale the moment the file is edited) must set it; leaving it '' keeps
  /// the historical unguarded behaviour for every existing caller.
  /// v(PHASE A2): ExpectLine extends the SAME guard to the line kinds
  /// (tekInsertLines / tekDeleteLines), which had none at all -- see
  /// AnchorIsValid for what it verifies and why a substring test alone is not
  /// enough. Set BOTH fields to arm it; ExpectLine = 0 is unguarded.
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.BuildAutofixEdits (DRagLint.CLI.pas), DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas), DRagLint.CLI.DoConvertApply (DRagLint.CLI.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits.HandleProc (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits (DRagLint.Diagnostics.AstChecks.pas) (+17 more)
  /// Used in units: DRagLint.CLI, DRagLint.Convert.Apply, DRagLint.Diagnostics.AstChecks, DRagLint.Doc.Batch, DRagLint.Doc.Document, DRagLint.Doc.Strip, DRagLint.Lint.DocRules, DRagLint.Refactor.EnumHelper, DRagLint.Refactor.ExtractMethod, DRagLint.Refactor.NamingFix, DRagLint.Refactor.TextEdit
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTextEdit = record
    FilePath  : string;
    Kind      : TTextEditKind;
    Line      : Integer;
    Col       : Integer;
    EndCol    : Integer;      { tekReplaceInLine: 1-based exclusive end column }
    EndLine   : Integer;
    Text      : string;
    ExpectText: string;       { tekReplaceInLine: the span guard; with ExpectLine: the anchor guard }
    ExpectLine: Integer;      { 1-based ANCHOR line that must still hold ExpectText; 0 = unguarded }
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas), DRagLint.CLI.ReportStrip (DRagLint.CLI.pas), DRagLint.CLI.DoDocumentUnit (DRagLint.CLI.pas), DRagLint.CLI.ReportDocBatch (DRagLint.CLI.pas), DRagLint.CLI.DoDocumentStripQName (DRagLint.CLI.pas) (+7 more)
  /// Used in units: DRagLint.CLI, DRagLint.Refactor.ExtractMethod
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTextEditApplier = class
  public
    /// <summary>Applies edits per file, back-to-front by line, preserving ANSI
    /// + CRLF + (optional) .bak backup. Returns files touched.</summary>
    /// <param name="AEdits"><!-- drag-lint:auto --></param>
    /// <param name="AWriteBackups"><!-- drag-lint:auto --></param>
    /// <returns><!-- drag-lint:auto -->Observed: Apply(AEdits, AWriteBackups, Skipped).</returns>
    /// <remarks>
    /// Edits are validated before they are written: a
    /// tekReplaceInLine whose Col lies past end-of-line is REJECTED (it would
    /// otherwise degrade into a silent append), and one carrying a non-empty
    /// ExpectText is rejected unless the current line really holds that text at
    /// [Col, EndCol) (compared case-insensitively). Use the overload with
    /// ASkippedEdits to learn how many were dropped.
    /// A file whose every edit was rejected is NOT rewritten and gets NO .bak --
    /// it is not counted as touched either. This matters beyond tidiness: the
    /// write path re-serializes through a TStringList (ANSI + CRLF normalization),
    /// so an unconditional rewrite would modify a file that no edit had changed.
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoConvertApply (DRagLint.CLI.pas), DRagLint.CLI.DoCreateEnumHelper (DRagLint.CLI.pas), DRagLint.CLI.DoDocumentStripQName (DRagLint.CLI.pas), DRagLint.CLI.DoDocumentUnit (DRagLint.CLI.pas), DRagLint.CLI.DoExtractMethod (DRagLint.CLI.pas) (+3 more)
    /// Calls: DRagLint.Refactor.TextEdit.TTextEditApplier.Apply/3
    /// Overload 1 of 2
    /// Pure
    /// <seealso cref="DRagLint.Refactor.TextEdit.TTextEditApplier.Apply"/>
    /// <seealso cref="DRagLint.Refactor.TextEdit.TTextEditApplier.RenderDryRun"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Apply(const AEdits: TArray<TTextEdit>; AWriteBackups: Boolean): Integer; overload;
    /// <summary>Same as Apply(AEdits, AWriteBackups), additionally reporting how
    /// many edits the pre-write validation dropped.</summary>
    /// <param name="AEdits">The edit set.</param>
    /// <param name="AWriteBackups">True writes a .bak beside each touched file.</param>
    /// <param name="ASkippedEdits">Out: count of edits rejected before writing --
    /// a tekReplaceInLine whose Col is past end-of-line, or whose non-empty
    /// ExpectText does not match the current line at [Col, EndCol). Non-zero
    /// means the producer's coordinates are stale for that file and the caller
    /// should surface a "reindex and re-run" hint; those sites were NOT
    /// written.</param>
    /// <returns>Number of files ACTUALLY modified -- a file whose every edit was
    /// rejected is not rewritten, backed up, or counted.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoDocument (DRagLint.CLI.pas), DRagLint.CLI.DoDocumentUnit (DRagLint.CLI.pas), DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas), DRagLint.CLI.ReportDocBatch (DRagLint.CLI.pas), DRagLint.Refactor.TextEdit.TTextEditApplier.Apply/2 (DRagLint.Refactor.TextEdit.pas)
    /// Calls: Copy, DRagLint.Refactor.TextEdit.AnchorIsValid, DRagLint.Refactor.TextEdit.EditTopLine, DRagLint.Refactor.TextEdit.ReplaceEditIsValid, preserving
    /// Returns: Touched
    /// Overload 2 of 2
    /// Complexity: 33 (cyclomatic, outer body), 162 lines (full implementation)
    /// Mutates: ASkippedEdits (out)
    /// Touches: file system
    /// <seealso cref="DRagLint.Refactor.TextEdit.AnchorIsValid"/>
    /// <seealso cref="DRagLint.Refactor.TextEdit.EditTopLine"/>
    /// <seealso cref="DRagLint.Refactor.TextEdit.ReplaceEditIsValid"/>
    /// <seealso cref="DRagLint.Refactor.TextEdit.TTextEditApplier.Apply"/>
    /// <seealso cref="DRagLint.Refactor.TextEdit.TTextEditApplier.RenderDryRun"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Apply(const AEdits: TArray<TTextEdit>; AWriteBackups: Boolean;
      out ASkippedEdits: Integer): Integer; overload;
    /// <summary>Human-readable preview of the edit set.</summary>
    /// <param name="AEdits"><!-- drag-lint:auto --></param>
    /// <returns><!-- drag-lint:auto -->Observed: SB.ToString.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoConvertApply (DRagLint.CLI.pas), DRagLint.CLI.DoCreateEnumHelper (DRagLint.CLI.pas), DRagLint.CLI.DoDocument (DRagLint.CLI.pas), DRagLint.CLI.DoDocumentUnit (DRagLint.CLI.pas), DRagLint.CLI.DoFindUnit (DRagLint.CLI.pas) (+5 more)
    /// Calls: Format
    /// Pure
    /// <seealso cref="DRagLint.Refactor.TextEdit.TTextEditApplier.Apply"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function RenderDryRun(const AEdits: TArray<TTextEdit>): string;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoFindUnit (DRagLint.CLI.pas), DRagLint.Convert.Apply.BuildApplyPlan (DRagLint.Convert.Apply.pas)
  /// Used in units: DRagLint.CLI, DRagLint.Convert.Apply
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TFindUnitRefactoring = class
  public
    /// <summary>Computes edits to add the unit declaring AName to AInFile's uses
    /// clause. AResolvedUnit = the chosen unit; AAlreadyUsed=True (empty result)
    /// when it is already imported. Empty result + AResolvedUnit='' when AName is
    /// unresolvable. Inserts into the implementation uses if present, else the
    /// interface uses, else a fresh implementation uses block.</summary>
    /// <param name="AStore"><!-- drag-lint:auto --></param>
    /// <param name="AName"><!-- drag-lint:auto --></param>
    /// <param name="AInFile"><!-- drag-lint:auto --></param>
    /// <param name="AResolvedUnit"><!-- drag-lint:auto --></param>
    /// <param name="AAlreadyUsed"><!-- drag-lint:auto --></param>
    /// <returns><!-- drag-lint:auto -->Observed: Build(AStore, AStore, AName, AInFile,
    /// AResolvedUnit, AAlreadyUsed).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoFindUnit (DRagLint.CLI.pas)
    /// Calls: DRagLint.Refactor.TextEdit.TFindUnitRefactoring.Build/6
    /// Overload 1 of 2
    /// Pure
    /// <seealso cref="DRagLint.Refactor.TextEdit.TFindUnitRefactoring.Build"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Build(const AStore: ISymbolStore; const AName, AInFile: string;
      out AResolvedUnit: string; out AAlreadyUsed: Boolean): TArray<TTextEdit>; overload;
    /// <summary>Same as the single-store overload, but resolves AName's
    /// declaring unit (FindSymbolsByExactName/GetFilePath) against ANameStore
    /// while AInFile's own uses-clause/insertion-point lookups (FindFileIdByPath/
    /// GetUnitUsesForFile) go against AUnitStore -- for callers whose target
    /// TYPE and target FILE are indexed in different --db stores (e.g.
    /// drag-lint convert-apply, where the To type may live in a different
    /// index than the form being converted).</summary>
    /// <param name="ANameStore"><!-- drag-lint:auto --></param>
    /// <param name="AUnitStore"><!-- drag-lint:auto --></param>
    /// <param name="AName"><!-- drag-lint:auto --></param>
    /// <param name="AInFile"><!-- drag-lint:auto --></param>
    /// <param name="AResolvedUnit"><!-- drag-lint:auto --></param>
    /// <param name="AAlreadyUsed"><!-- drag-lint:auto --></param>
    /// <returns><!-- drag-lint:auto -->Observed: nil; [Edit].</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Convert.Apply.BuildApplyPlan (DRagLint.Convert.Apply.pas), DRagLint.Refactor.TextEdit.TFindUnitRefactoring.Build/5 (DRagLint.Refactor.TextEdit.pas)
    /// Calls: AUnitStore, ChangeFileExt, DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Core.Interfaces.ISymbolStore.GetUnitUsesForFile, ExtractFileName, file, LowerCase, SameText, Trim
    /// Overload 2 of 2
    /// Complexity: 28 (cyclomatic, outer body), 120 lines (full implementation)
    /// Mutates: AResolvedUnit (out), AAlreadyUsed (out)
    /// Touches: file system
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetUnitUsesForFile"/>
    /// <seealso cref="DRagLint.Refactor.TextEdit.TFindUnitRefactoring.Build"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Build(const ANameStore, AUnitStore: ISymbolStore; const AName, AInFile: string;
      out AResolvedUnit: string; out AAlreadyUsed: Boolean): TArray<TTextEdit>; overload;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoSafeDelete (DRagLint.CLI.pas)
  /// Used in units: DRagLint.CLI
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSafeDeleteRefactoring = class
  public
    /// <summary>Edits to delete the declaration (and impl body, for a routine)
    /// of AQName, but ONLY when it has zero references. Reference check uses
    /// FindCallersByName(short name) -- FindReferencesTo is unreliable (refs.
    /// symbol_id is NULL in the index). Returns empty + ARefuseReason when the
    /// symbol is referenced or not found.</summary>
    /// <param name="AStore"><!-- drag-lint:auto --></param>
    /// <param name="AQName"><!-- drag-lint:auto --></param>
    /// <param name="ARefuseReason"><!-- drag-lint:auto --></param>
    /// <returns><!-- drag-lint:auto -->Observed: nil; Edits.ToArray.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoSafeDelete (DRagLint.CLI.pas)
    /// Calls: DRagLint.Core.Interfaces.ISymbolStore.FindCallersByName, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByQualifiedName, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Refactor.TextEdit.LastSeg, Format
    /// Complexity: 10 (cyclomatic, outer body), 56 lines (full implementation)
    /// Mutates: ARefuseReason (out)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindCallersByName"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByQualifiedName"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
    /// <seealso cref="DRagLint.Refactor.TextEdit.LastSeg"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Build(const AStore: ISymbolStore; const AQName: string;
      out ARefuseReason: string): TArray<TTextEdit>;
  end;

implementation

{ Sort key for back-to-front application within a file: larger line first; for
  deletes use EndLine as the key so a delete is processed before any edit above
  it. tekInsertInLine/Lines use Line. }
function EditTopLine(const E: TTextEdit): Integer;
begin
  if E.Kind = tekDeleteLines then Result:= E.EndLine else Result:= E.Line;
end;

{ THE STALE-POSITION GUARD for tekReplaceInLine. True when the edit may be
  written against ALine, the current on-disk content of its target line.
  Rejects two things the old unguarded path let through silently:
   * Col past end-of-line -- Copy(S, 1, C-1) + Text + Copy(S, EC, MaxInt) then
     degenerates into an APPEND, gluing the replacement onto whatever the line
     ends with (observed: `then` + `GlyActive` -> `thenGlyActive`, exit code 0);
   * a non-empty ExpectText that the line does not actually hold at
     [Col, EndCol) -- i.e. store coordinates that have drifted since indexing.
  An empty ExpectText leaves the second check off, which is exactly the historic
  behaviour every pre-existing caller relies on. }
function ReplaceEditIsValid(const E: TTextEdit; const ALine: string): Boolean;
var
  C, EC: Integer;
begin
  Result:= False;
  C:= E.Col; if C < 1 then C:= 1;
  if C > Length(ALine) + 1 then Exit;      { past end-of-line: reject, never append }
  if E.ExpectText = '' then Exit(True);    { unguarded (legacy) caller }
  EC:= E.EndCol;
  if EC <= C then Exit;
  if (EC - C) <> Length(E.ExpectText) then Exit;   { span width must match }
  if (EC - 1) > Length(ALine) then Exit;           { span runs past end-of-line }
  Result:= SameText(Copy(ALine, C, EC - C), E.ExpectText);
end;

{ THE STALE-ANCHOR GUARD, for edits whose Line came from the symbol store.

  ReplaceEditIsValid above answers "does this line still hold the text I am
  about to replace". It only ever applied to tekReplaceInLine, so the LINE kinds
  -- insert a block above a declaration, delete the block above it -- had no
  guard at all. That is the fourth instance of one root cause this repo has now
  hit: `unused-local`'s fixer destroyed 72 lines; the naming autofix wrote onto
  `then`/`else` and exited 0; `document --qname --apply` run twice on one class
  nested the second block inside the first and left the second symbol
  undocumented, because the store still held the PRE-EDIT start_line, which
  after the first insert pointed into the middle of the block just written.

  WHY "CONTAINS THE NAME" IS NOT ENOUGH, and the comment test is load-bearing:
  the stale coordinate in that defect landed on `/// Calls: Create` -- a line
  that DOES contain the identifier the guard is looking for. So the anchor must
  also still look like a DECLARATION: a line that starts a comment is never one.
  Together the two conditions are what makes this structural rather than a
  spelling check.

  Conservative in the only direction that matters: when the guard cannot
  confirm the anchor, the edit is DROPPED. Dropping a good edit costs a re-run;
  writing at a coordinate that has moved corrupts the user's source. }
function ContainsWholeWord(const AText, AWord: string): Boolean;
var
  L, W : string ;
  P, WL: Integer;

  function IsWordCh(const ACh: Char): Boolean;
  begin
    Result:= CharInSet(ACh, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
  end;

begin
  Result:= False;
  if AWord = '' then Exit;
  L := LowerCase(AText);
  W := LowerCase(AWord);
  WL:= Length(W);
  P := Pos(W, L);
  while P > 0 do
  begin
    if ((P = 1) or (not IsWordCh(L[P - 1]))) and
       ((P + WL > Length(L)) or (not IsWordCh(L[P + WL]))) then Exit(True);
    P:= Pos(W, L, P + 1);
  end;
end;

function AnchorIsValid(const E: TTextEdit; ALines: TStrings): Boolean;
var
  S: string;
begin
  if (E.ExpectLine <= 0) or (E.ExpectText = '') then Exit(True);  { unguarded }
  if (E.ExpectLine > ALines.Count) then Exit(False);              { file shrank past it }
  S:= TrimLeft(ALines[E.ExpectLine - 1]);
  { A comment line is never a declaration -- see the header above. }
  if S.StartsWith('//') or S.StartsWith('{') or S.StartsWith('(*') then Exit(False);
  Result:= ContainsWholeWord(S, E.ExpectText);
end;

class function TTextEditApplier.Apply(const AEdits: TArray<TTextEdit>; AWriteBackups: Boolean): Integer;
var
  Skipped: Integer;
begin
  Result:= Apply(AEdits, AWriteBackups, Skipped);
end;

class function TTextEditApplier.Apply(const AEdits: TArray<TTextEdit>; AWriteBackups: Boolean;
  out ASkippedEdits: Integer): Integer;
var
  FileMap : TDictionary<string, TList<TTextEdit>>;
  E       : TTextEdit;
  Group   : TList<TTextEdit>;
  Pair    : TPair<string, TList<TTextEdit>>;
  RawBytes: TBytes;
  Content : string;
  Lines   : TStringList;
  Touched : Integer;
  Cmp     : IComparer<TTextEdit>;
  Kept    : TList<TTextEdit>;   { v(PHASE A2): the edits that survived the stale-anchor pre-pass }
  AppliedInFile: Integer;
begin
  Touched:= 0;
  ASkippedEdits:= 0;
  FileMap:= TDictionary<string, TList<TTextEdit>>.Create;
  try
    for E in AEdits do
    begin
      if not FileMap.TryGetValue(E.FilePath, Group) then
      begin Group:= TList<TTextEdit>.Create; FileMap.Add(E.FilePath, Group); end;
      Group.Add(E);
    end;

    for Pair in FileMap do
    begin
      if not TFile.Exists(Pair.Key) then Continue;
      RawBytes:= TFile.ReadAllBytes(Pair.Key);
      Content := TEncoding.ANSI.GetString(RawBytes);
      { The .bak used to be written HERE, before a single edit had been
        evaluated -- so a file whose every edit the guard rejected still got a
        backup, was still rewritten, and still counted as touched. RawBytes holds
        the original, so the backup can wait until we know something changed. }

      Group:= Pair.Value;
      AppliedInFile:= 0;
      { back-to-front: largest top-line first so indices stay valid }
      Cmp:= TComparer<TTextEdit>.Construct(
        function(const A, B: TTextEdit): Integer
        begin
          Result:= EditTopLine(B) - EditTopLine(A);
          if Result = 0 then Result:= B.Col - A.Col; // same line: larger column first (back-to-front)
        end);
      Group.Sort(Cmp);

      Lines:= TStringList.Create;
      try
        Lines.Text:= Content;

        { v(PHASE A2): STALE-ANCHOR PRE-PASS, over the file AS FOUND.

          It runs BEFORE any edit is applied, and that is not a stylistic
          choice. Edits are applied back-to-front, and the doc repair path emits
          a DELETE of the old comment span plus an INSERT of the merged one --
          the delete is processed first, which shifts every line below it. An
          anchor checked mid-loop would therefore be read at the wrong offset
          for the insert, and the pair could half-apply: the existing comment
          deleted, its replacement dropped. Validating everything against the
          unmutated snapshot makes a pair fail or survive TOGETHER, since both
          carry the same anchor.

          Only ExpectLine-bearing edits are affected; every historic caller
          leaves it 0 and reaches the loop below exactly as before. }
        Kept:= TList<TTextEdit>.Create;
        try
          for E in Group do
            if AnchorIsValid(E, Lines) then Kept.Add(E)
            else Inc(ASkippedEdits);

        for E in Kept do
        begin
          case E.Kind of
            tekDeleteLines:
              begin
                var LHi: Integer:= E.EndLine; var LLo: Integer:= E.Line;
                if LLo < 1 then LLo:= 1;
                if LHi > Lines.Count then LHi:= Lines.Count;
                for var L: Integer:= LHi downto LLo do
                  if (L >= 1) and (L <= Lines.Count) then begin Lines.Delete(L - 1); Inc(AppliedInFile); end;
              end;
            tekInsertLines:
              begin
                var Idx: Integer:= E.Line; { insert AFTER 1-based Line => 0-based index Line }
                if Idx < 0 then Idx:= 0;
                if Idx > Lines.Count then Idx:= Lines.Count;
                { split Text on CRLF/LF so multi-line inserts keep separate lines }
                var Parts: TArray<string>:= E.Text.Replace(#13#10, #10).Split([#10]);
                for var PIdx: Integer:= High(Parts) downto 0 do
                  Lines.Insert(Idx, Parts[PIdx]);
                Inc(AppliedInFile);
              end;
            tekInsertInLine:
              begin
                if (E.Line >= 1) and (E.Line <= Lines.Count) then
                begin
                  var S: string:= Lines[E.Line - 1];
                  var C: Integer:= E.Col; if C < 1 then C:= 1;
                  if C > Length(S) + 1 then C:= Length(S) + 1;
                  Lines[E.Line - 1]:= Copy(S, 1, C - 1) + E.Text + Copy(S, C, MaxInt);
                  Inc(AppliedInFile);
                end
                else
                  Inc(ASkippedEdits);   { line does not exist: silently dropped before }
              end;
            tekReplaceInLine:
              begin
                if (E.Line >= 1) and (E.Line <= Lines.Count) then
                begin
                  var S: string:= Lines[E.Line - 1];
                  if not ReplaceEditIsValid(E, S) then
                    Inc(ASkippedEdits)
                  else
                  begin
                    var C: Integer:= E.Col;    if C < 1 then C:= 1;
                    var EC: Integer:= E.EndCol; if EC < C then EC:= C;
                    if EC > Length(S) + 1 then EC:= Length(S) + 1;
                    Lines[E.Line - 1]:= Copy(S, 1, C - 1) + E.Text + Copy(S, EC, MaxInt);
                    Inc(AppliedInFile);
                  end;
                end
                else
                  Inc(ASkippedEdits);   { line does not exist: out of range, never written }
              end;
          end;
        end;
        finally
          Kept.Free;
        end;

        { Nothing survived validation for this file: leave it exactly as found --
          no backup, no rewrite, not counted. The re-serialization below is NOT
          byte-preserving (TStringList + forced CRLF), so writing here would edit
          a file on behalf of zero applied edits. }
        if AppliedInFile = 0 then Continue;

        if AWriteBackups then TFile.WriteAllBytes(Pair.Key + '.bak', RawBytes);

        { re-encode ANSI + CRLF, preserve a trailing newline if the original had one }
        var SB: TStringBuilder:= TStringBuilder.Create;
        try
          for var I: Integer:= 0 to Lines.Count - 1 do
          begin
            SB.Append(Lines[I]);
            if I < Lines.Count - 1 then SB.Append(#13#10);
          end;
          if (Length(Content) > 0) and (Content[Length(Content)] = #10) then SB.Append(#13#10);
          TFile.WriteAllBytes(Pair.Key, TEncoding.ANSI.GetBytes(SB.ToString));
        finally
          SB.Free;
        end;
        Inc(Touched);
      finally
        Lines.Free;
      end;
    end;
  finally
    for Pair in FileMap do Pair.Value.Free;
    FileMap.Free;
  end;
  Result:= Touched;
end;

class function TTextEditApplier.RenderDryRun(const AEdits: TArray<TTextEdit>): string;
var SB: TStringBuilder; E: TTextEdit; Last: string;
begin
  SB:= TStringBuilder.Create;
  try
    Last:= '';
    for E in AEdits do
    begin
      if E.FilePath <> Last then begin SB.AppendLine('File: ' + E.FilePath); Last:= E.FilePath; end;
      case E.Kind of
        tekDeleteLines : SB.AppendLine(Format('  delete lines %d..%d', [E.Line, E.EndLine]));
        tekInsertLines : SB.AppendLine(Format('  insert after line %d: %s', [E.Line, E.Text]));
        tekInsertInLine: SB.AppendLine(Format('  insert at L%d:C%d: %s', [E.Line, E.Col, E.Text]));
        tekReplaceInLine: SB.AppendLine(Format('  replace L%d:C%d..%d -> "%s"', [E.Line, E.Col, E.EndCol, E.Text]));
      end;
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TFindUnitRefactoring.Build(const AStore: ISymbolStore;
  const AName, AInFile: string; out AResolvedUnit: string; out AAlreadyUsed: Boolean): TArray<TTextEdit>;
begin
  Result:= Build(AStore, AStore, AName, AInFile, AResolvedUnit, AAlreadyUsed);
end;

class function TFindUnitRefactoring.Build(const ANameStore, AUnitStore: ISymbolStore;
  const AName, AInFile: string; out AResolvedUnit: string; out AAlreadyUsed: Boolean): TArray<TTextEdit>;
var
  Syms : TArray<TSymbol>;
  S    : TSymbol;
  Cands: TDictionary<string, Integer>; { unit -> score }
  Best : string; BestScore: Integer;
  FullPath: string; InFileId: Int64;
  Uses_: TArray<TUnitUse>; U: TUnitUse;
  UsedSet: TDictionary<string, Boolean>;
  UnitName: string;
  TargetSection: TUnitUseSection;
  LastInSection: TUnitUse; HaveLast: Boolean;
  Edit: TTextEdit;
  Pair: TPair<string, Integer>;
begin
  Result:= nil; AResolvedUnit:= ''; AAlreadyUsed:= False;

  { 1. resolve the best declaring unit -- against ANameStore, which may be a
    DIFFERENT store than AUnitStore (the type being added to the uses clause
    may be indexed in a different --db than the file it's being added to). }
  Syms:= ANameStore.FindSymbolsByExactName(AName);
  if Length(Syms) = 0 then Exit;
  Cands:= TDictionary<string, Integer>.Create;
  try
    for S in Syms do
    begin
      UnitName:= ChangeFileExt(ExtractFileName(ANameStore.GetFilePath(S.FileId)), '');
      if UnitName = '' then Continue;
      var Sc: Integer:= 1;
      if not SameText(S.Section, 'implementation') then Inc(Sc, 10); { interface-visible }
      var Cur: Integer;
      if not Cands.TryGetValue(UnitName, Cur) then Cur:= 0;
      Cands.AddOrSetValue(UnitName, Cur + Sc);
    end;
    Best:= ''; BestScore:= -1;
    for Pair in Cands do
      if Pair.Value > BestScore then begin BestScore:= Pair.Value; Best:= Pair.Key; end;
  finally
    Cands.Free;
  end;
  if Best = '' then Exit;
  AResolvedUnit:= Best;

  { do not add a unit to itself }
  if SameText(ChangeFileExt(ExtractFileName(AInFile), ''), Best) then Exit;

  { 2. load the target file's existing uses -- against AUnitStore, which
    actually has AInFile indexed. }
  FullPath:= TPath.GetFullPath(AInFile);
  InFileId:= AUnitStore.FindFileIdByPath(FullPath);
  if InFileId <= 0 then InFileId:= AUnitStore.FindFileIdByPath(AInFile);
  Uses_:= nil;
  if InFileId > 0 then Uses_:= AUnitStore.GetUnitUsesForFile(InFileId);

  UsedSet:= TDictionary<string, Boolean>.Create;
  try
    for U in Uses_ do UsedSet.AddOrSetValue(LowerCase(U.UnitName), True);
    if UsedSet.ContainsKey(LowerCase(Best)) then begin AAlreadyUsed:= True; Exit; end;

    { 3. choose target section: implementation uses if present, else interface }
    TargetSection:= uusImplementation;
    HaveLast:= False;
    var HasImpl: Boolean:= False; var HasIntf: Boolean:= False;
    for U in Uses_ do
    begin
      if U.Section = uusImplementation then HasImpl:= True;
      if U.Section = uusInterface then HasIntf:= True;
    end;
    if HasImpl then TargetSection:= uusImplementation
    else if HasIntf then TargetSection:= uusInterface
    else TargetSection:= uusImplementation; { fresh block goes to implementation }

    { last entry in the chosen section -> append ', Best' after it }
    for U in Uses_ do
      if U.Section = TargetSection then
        if (not HaveLast) or (U.StartLine > LastInSection.StartLine)
           or ((U.StartLine = LastInSection.StartLine) and (U.StartCol > LastInSection.StartCol)) then
        begin LastInSection:= U; HaveLast:= True; end;

    if HaveLast then
    begin
      { insert ', Best' at the end of the last unit entry (before the ';') }
      Edit.FilePath:= AInFile; Edit.Kind:= tekInsertInLine;
      Edit.Line:= LastInSection.EndLine; Edit.Col:= LastInSection.EndCol;
      Edit.EndLine:= 0; Edit.Text:= ', ' + Best;
      Result:= [Edit];
    end
    else
    begin
      { no uses clause in the file at all -> a fresh "uses Best;" block.
        Insert after the 'implementation' line if the file has one, else after
        'interface'. We locate the keyword by reading the file (cheap, single file). }
      var KeywordLine: Integer:= 0;
      if TFile.Exists(AInFile) then
      begin
        var Raw: string:= TEncoding.ANSI.GetString(TFile.ReadAllBytes(AInFile));
        var SL: TStringList:= TStringList.Create;
        try
          SL.Text:= Raw;
          var WantImpl: Boolean:= (TargetSection = uusImplementation);
          for var I: Integer:= 0 to SL.Count - 1 do
          begin
            var T: string:= LowerCase(Trim(SL[I]));
            if WantImpl and (T = 'implementation') then begin KeywordLine:= I + 1; Break; end;
            if (not WantImpl) and (T = 'interface') then begin KeywordLine:= I + 1; Break; end;
          end;
        finally
          SL.Free;
        end;
      end;
      if KeywordLine = 0 then Exit; { cannot place safely }
      Edit.FilePath:= AInFile; Edit.Kind:= tekInsertLines;
      Edit.Line:= KeywordLine; Edit.Col:= 0; Edit.EndLine:= 0;
      Edit.Text:= ''#13#10'uses ' + Best + ';';
      Result:= [Edit];
    end;
  finally
    UsedSet.Free;
  end;
end;

function LastSeg(const S: string): string;
var P: Integer;
begin
  P:= LastDelimiter('.', S);
  if P > 0 then Result:= Copy(S, P + 1, MaxInt) else Result:= S;
end;

class function TSafeDeleteRefactoring.Build(const AStore: ISymbolStore;
  const AQName: string; out ARefuseReason: string): TArray<TTextEdit>;
var
  Syms        : TArray<TSymbol>  ;
  Sym         : TSymbol          ;
  Refs        : TArray<TReference>;
  Short       : string           ;
  Path        : string           ;
  Edits       : TList<TTextEdit> ;
  E           : TTextEdit        ;
  R           : TReference       ;
  ExternalRefs: Integer          ;
begin
  Result:= nil; ARefuseReason:= '';
  Syms:= AStore.FindSymbolsByQualifiedName(AQName);
  if Length(Syms) = 0 then begin ARefuseReason:= Format('symbol "%s" not found', [AQName]); Exit; end;
  Sym:= Syms[0];
  Short:= LastSeg(AQName);

  { Zero-reference check via name-text match (FindReferencesTo is unreliable:
    refs.symbol_id is NULL in the index, so it always returns empty). Any ref
    row returned by FindCallersByName that is NOT at exactly the declaration's
    (FileId, StartLine) is a real external usage. If ExternalRefs > 0, refuse. }
  Refs:= AStore.FindCallersByName(Short);
  ExternalRefs:= 0;
  for R in Refs do
    if not ((R.FileId = Sym.FileId) and (R.StartLine = Sym.StartLine)) then Inc(ExternalRefs);
  if ExternalRefs > 0 then
  begin
    ARefuseReason:= Format('"%s" has %d reference(s) -- refusing to delete', [AQName, ExternalRefs]);
    Exit;
  end;

  Path:= AStore.GetFilePath(Sym.FileId);
  if Path = '' then begin ARefuseReason:= 'declaration file path unknown'; Exit; end;

  Edits:= TList<TTextEdit>.Create;
  try
    { impl body first (higher line numbers), then declaration.
      The applier sorts back-to-front anyway, but emit in logical order. }
    if (Sym.ImplStartLine > 0) and (Sym.ImplEndLine >= Sym.ImplStartLine) then
    begin
      E.FilePath:= Path; E.Kind:= tekDeleteLines;
      E.Line:= Sym.ImplStartLine; E.EndLine:= Sym.ImplEndLine; E.Col:= 0; E.Text:= '';
      Edits.Add(E);
    end;
    if (Sym.StartLine > 0) and (Sym.EndLine >= Sym.StartLine) then
    begin
      E.FilePath:= Path; E.Kind:= tekDeleteLines;
      E.Line:= Sym.StartLine; E.EndLine:= Sym.EndLine; E.Col:= 0; E.Text:= '';
      Edits.Add(E);
    end;
    Result:= Edits.ToArray;
  finally
    Edits.Free;
  end;
end;

end.
