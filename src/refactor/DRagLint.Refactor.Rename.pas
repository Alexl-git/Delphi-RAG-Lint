unit DRagLint.Refactor.Rename;

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System  .Generics.Collections
  , System  .Generics.Defaults
  , TreeSitter
  , TreeSitterLib
  , DRagLint.Core    .Model
  , DRagLint.Core    .Interfaces
  , DRagLint.Diagnostics.ParseCache
  ;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.MCP.Server.pas), DRagLint.CLI.CountDistinctFiles (DRagLint.CLI.pas), DRagLint.CLI.DoRename (DRagLint.CLI.pas), DRagLint.MCP.Server.TMCPServer.FormatRenameEditsAsJson (DRagLint.MCP.Server.pas), DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas) (+7 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.MCP.Server, DRagLint.Refactor.NamingFix, DRagLint.Refactor.Rename</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TRenameEdit = record
    FilePath: string ;
    Line    : Integer; // 1-based
    Col     : Integer; // 1-based
    OldName : string ;
    NewName : string ;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoRename (DRagLint.CLI.pas), DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas), DRagLint.Refactor.ExtractMethod.TExtractMethodRefactoring.Build (DRagLint.Refactor.ExtractMethod.pas), DRagLint.Refactor.NamingFix.BuildNamingFixEdits (DRagLint.Refactor.NamingFix.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.MCP.Server, DRagLint.Refactor.ExtractMethod, DRagLint.Refactor.NamingFix</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TRenameRefactoring = class
    public
      /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
      /// <param name="AQName"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ANewName"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->TArray&lt;TRenameEdit&gt; -- Observed: nil;
      /// List.ToArray.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoRename (DRagLint.CLI.pas), DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas), DRagLint.Refactor.NamingFix.BuildNamingFixEdits (DRagLint.Refactor.NamingFix.pas)</para>
      /// <para>Calls: Copy, DRagLint.Core.Interfaces.ISymbolStore.FindCallersByName, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByQualifiedName, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Refactor.Rename.CompareEdits, DRagLint.Refactor.Rename.LastDotSegment, IntToStr, SameText, UpperCase</para>
      /// <para>Complexity: 12 (cyclomatic, outer body), 113 lines (full implementation)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindCallersByName"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByQualifiedName"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
      /// <seealso cref="DRagLint.Refactor.Rename.CompareEdits"/>
      /// <seealso cref="DRagLint.Refactor.Rename.LastDotSegment"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function Build(const AStore: ISymbolStore; const AQName, ANewName: string): TArray<TRenameEdit>;
      /// <param name="AEdits"><!-- drag-lint:auto type -->const TArray&lt;TRenameEdit&gt;</param>
      /// <param name="AWriteBackups"><!-- drag-lint:auto type -->Boolean</param>
      /// <returns><!-- drag-lint:auto -->Integer -- Observed: FilesTouched.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoRename (DRagLint.CLI.pas), DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)</para>
      /// <para>Calls: Copy, SameText</para>
      /// <para>Complexity: 16 (cyclomatic, outer body), 111 lines (full implementation)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Refactor.Rename.TRenameRefactoring.Build"/>
      /// <seealso cref="DRagLint.Refactor.Rename.TRenameRefactoring.BuildLocal"/>
      /// <seealso cref="DRagLint.Refactor.Rename.TRenameRefactoring.ConflictReason"/>
      /// <seealso cref="DRagLint.Refactor.Rename.TRenameRefactoring.IsReservedWord"/>
      /// <seealso cref="DRagLint.Refactor.Rename.TRenameRefactoring.RenderDryRun"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function Apply(const AEdits: TArray<TRenameEdit>; AWriteBackups: Boolean) : Integer            ; // returns files touched
      /// <param name="AEdits"><!-- drag-lint:auto type -->const TArray&lt;TRenameEdit&gt;</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: SB.ToString.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoRename (DRagLint.CLI.pas)</para>
      /// <para>Calls: Format</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Refactor.Rename.TRenameRefactoring.Apply"/>
      /// <seealso cref="DRagLint.Refactor.Rename.TRenameRefactoring.Build"/>
      /// <seealso cref="DRagLint.Refactor.Rename.TRenameRefactoring.BuildLocal"/>
      /// <seealso cref="DRagLint.Refactor.Rename.TRenameRefactoring.ConflictReason"/>
      /// <seealso cref="DRagLint.Refactor.Rename.TRenameRefactoring.IsReservedWord"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function RenderDryRun(const AEdits: TArray<TRenameEdit>)                  : string             ;
      /// <summary>True when AName is a Delphi reserved word (case-insensitive) and
      /// therefore cannot be used as an identifier.</summary>
      /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoRename (DRagLint.CLI.pas), DRagLint.Refactor.ExtractMethod.TExtractMethodRefactoring.Build (DRagLint.Refactor.ExtractMethod.pas), DRagLint.Refactor.Rename.TRenameRefactoring.ConflictReason (DRagLint.Refactor.Rename.pas)</para>
      /// <para>Calls: CompareStr, LowerCase</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Refactor.Rename.TRenameRefactoring.Apply"/>
      /// <seealso cref="DRagLint.Refactor.Rename.TRenameRefactoring.Build"/>
      /// <seealso cref="DRagLint.Refactor.Rename.TRenameRefactoring.BuildLocal"/>
      /// <seealso cref="DRagLint.Refactor.Rename.TRenameRefactoring.ConflictReason"/>
      /// <seealso cref="DRagLint.Refactor.Rename.TRenameRefactoring.RenderDryRun"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function IsReservedWord(const AName: string): Boolean;
      /// <summary>Non-empty human reason when renaming AQName to ANewName would be
      /// unsafe: ANewName is a reserved word, or a sibling symbol named ANewName
      /// already exists under the same parent. '' when the rename is safe.</summary>
      /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
      /// <param name="AQName"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ANewName"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: ''; Format('"%s" is a
      /// reserved word', [ANewName]); Format('a symbol named "%s" already exists in the
      /// same scope', [ANewName]).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoRename (DRagLint.CLI.pas), DRagLint.Refactor.NamingFix.BuildNamingFixEdits (DRagLint.Refactor.NamingFix.pas)</para>
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindChildSymbolByName, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByQualifiedName, DRagLint.Refactor.Rename.TRenameRefactoring.IsReservedWord, Format</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindChildSymbolByName"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByQualifiedName"/>
      /// <seealso cref="DRagLint.Refactor.Rename.TRenameRefactoring.IsReservedWord"/>
      /// <seealso cref="DRagLint.Refactor.Rename.TRenameRefactoring.Apply"/>
      /// <seealso cref="DRagLint.Refactor.Rename.TRenameRefactoring.Build"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function ConflictReason(const AStore: ISymbolStore; const AQName, ANewName: string): string;
      /// <summary>Non-empty human reason when the short name of AQName occurs as an
      /// identifier token in an .inc file the index holds; '' otherwise. A rename
      /// must then be refused: the index records no references inside {$I}
      /// included text (until extractor 1.22), so Build would rewrite the
      /// declaration and leave every use inside the include stale.</summary>
      /// <param name="AStore">Open index; its `files` rows are the project closure
      /// that is scanned. Must not be nil.</param>
      /// <param name="AQName">Qualified name of the symbol to rename; only its last
      /// dot segment is matched (case-insensitive, whole identifier).</param>
      /// <returns>'' when no indexed .inc file uses the name; else a message that
      /// names every such .inc file.</returns>
      /// <remarks>A text scan, deliberately conservative: comments ({ }, (* *), //)
      /// and string literals are skipped, but any other same-named identifier in an
      /// include refuses the rename even if it binds to a different symbol. An .inc
      /// that is listed but missing on disk is ignored.</remarks>
      class function IncludeUseReason(const AStore: ISymbolStore; const AQName: string): string;
      /// <summary>Non-empty human reason when the unit declaring AQName has a
      /// BINARY form file (sibling .dfm) that contains the symbol's short name as
      /// an identifier; '' otherwise. A rename must then be refused: Build rewrites
      /// event bindings (`OnClick = Button1Click`) only in TEXT .dfm files, which
      /// the index parses; a binary .dfm is opaque to it, so the form would keep
      /// the old handler name and fail to load.</summary>
      /// <param name="AStore">Open index; resolves AQName to its declaring file.
      /// Must not be nil.</param>
      /// <param name="AQName">Qualified name of the symbol to rename; only its last
      /// dot segment is matched (case-insensitive, whole identifier).</param>
      /// <returns>'' when the symbol is unknown, its unit has no .dfm, the .dfm is
      /// text, or the binary .dfm does not contain the name; else a message naming
      /// the .dfm and saying it is binary.</returns>
      /// <remarks>A byte scan, deliberately conservative: any same-named
      /// identifier in the binary stream refuses (a component or property of that
      /// name, too). Binary = the file starts with the resource header byte $FF or
      /// with the 'TPF0' signature.</remarks>
      class function BinaryDfmReason(const AStore: ISymbolStore; const AQName: string): string;
      /// <summary>Non-empty human reason when any edit's recorded position no
      /// longer holds its old name on disk; '' when every edit is still in place.
      /// A rename must then be refused: the file changed after it was indexed, and
      /// rewriting whatever now sits there would corrupt it.</summary>
      /// <param name="AEdits">Edits as Build / BuildLocal return them (Col already
      /// snapped from a declaration keyword onto the name).</param>
      /// <returns>'' when, for every edit, the file exists and OldName sits at
      /// (Line, Col) as a whole identifier (case-insensitive); else a message
      /// "index out of date for File:Line ..." naming the first stale edit.</returns>
      /// <remarks>Never scans for the name elsewhere: a reference that moved on
      /// disk (other line, or other column on its line) is stale, not retargeted.
      /// Reads each file once.</remarks>
      class function StaleEditReason(const AEdits: TArray<TRenameEdit>): string;
      /// <summary>Routine-local rename of the parameter or local variable whose
      /// declaration identifier sits at (ALine, ACol) (1-based) in AFile. Emits a
      /// TRenameEdit for the declaration, every in-scope use within the owning
      /// routine body, and the matching parameter in any same-named forward/interface
      /// declProc header. Shadowing nested routines, qualified members (X.Name) on
      /// both exprDot and genericDot rhs sides, and with-statement members are
      /// conservatively skipped. Empty array if no param/local decl is found at that
      /// position. Pure AST -- no symbol store.
      /// Known limitations (deliberate conservative choices): occurrences inside a
      /// with block are skipped entirely; a same-named param in an unrelated same-name
      /// overload header may be touched (header-only, not a body rename).</summary>
      /// <param name="AFile"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ALine"><!-- drag-lint:auto type -->Integer</param>
      /// <param name="ACol"><!-- drag-lint:auto type -->Integer</param>
      /// <param name="ANewName"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->TArray&lt;TRenameEdit&gt; -- Observed: nil;
      /// Final.ToArray.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoRename (DRagLint.CLI.pas), DRagLint.Refactor.NamingFix.BuildNamingFixEdits (DRagLint.Refactor.NamingFix.pas)</para>
      /// <para>Calls: AddEdit, Default, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, DRagLint.Refactor.Rename.TRenameRefactoring.BuildLocal.EnclosingProc, DRagLint.Refactor.Rename.TRenameRefactoring.BuildLocal.FindIdentAt, DRagLint.Refactor.Rename.TRenameRefactoring.BuildLocal.NStr, DRagLint.Refactor.Rename.TRenameRefactoring.BuildLocal.SyncForwardHeaders, DRagLint.Refactor.Rename.TRenameRefactoring.BuildLocal.Walk, HdrName, Integer (+9 more)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Refactor.Rename.TRenameRefactoring.BuildLocal.EnclosingProc"/>
      /// <seealso cref="DRagLint.Refactor.Rename.TRenameRefactoring.BuildLocal.FindIdentAt"/>
      /// <seealso cref="DRagLint.Refactor.Rename.TRenameRefactoring.BuildLocal.NStr"/>
      /// <seealso cref="DRagLint.Refactor.Rename.TRenameRefactoring.BuildLocal.SyncForwardHeaders"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function BuildLocal(const AFile: string; ALine, ACol: Integer; const ANewName: string): TArray<TRenameEdit>;
  end;

implementation

uses
  System.StrUtils;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function LastDotSegment(const S: string): string;
var
  DotPos: Integer;
begin
  DotPos:= LastDelimiter('.', S);
  if DotPos > 0 then Result:= Copy(S, DotPos + 1, MaxInt)
  else Result:= S;
end;

// Compare two TRenameEdit values: FilePath ASC, Line DESC, Col DESC.
// Used to sort edits so we apply them back-to-front within each file,
// preventing earlier column-position shifts from invalidating later edits.
function CompareEdits(const A, B: TRenameEdit): Integer;
begin
  Result:= CompareText(A.FilePath, B.FilePath);
  if Result <> 0 then Exit;
  // Same file: sort Line DESC
  Result:= B.Line - A.Line;
  if Result <> 0 then Exit;
  // Same line: sort Col DESC
  Result:= B.Col - A.Col;
end;

function IsIdentChar(C: Char): Boolean;
begin
  Result:= CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

// 1-based column of the first whole-identifier, case-insensitive occurrence of
// AName in ALine at or after AFrom; 0 when there is none.
function FindIdentFrom(const ALine, AName: string; AFrom: Integer): Integer;
var
  P: Integer;
begin
  Result:= 0;
  if AFrom < 1 then AFrom:= 1;
  for P:= AFrom to Length(ALine) - Length(AName) + 1 do
    if SameText(Copy(ALine, P, Length(AName)), AName)
       and ((P = 1) or not IsIdentChar(ALine[P - 1]))
       and ((P + Length(AName) > Length(ALine)) or not IsIdentChar(ALine[P + Length(AName)])) then
      Exit(P);
end;

// Moves each edit's Col onto the identifier it replaces. Index rows can carry a
// column that is NOT the name token: a routine/property declaration's symbol
// starts at its `procedure`/`function`/`property` keyword. Apply used to
// recover from that by scanning forward, but the edit set itself (rename --json,
// MCP rename_symbol, LSP) reported the keyword column. Only that shape moves:
// the stored column must start a declaration keyword run (`class procedure`,
// `function`, `property`, ...) that is followed, on the SAME line, by the name.
// Anything else keeps its column -- a reference that moved on disk must stay
// where the index says so StaleEditReason / the LSP refuse it, never be
// silently retargeted to a later same-named token (11477a8c regression).
function IsIdentAt(const ALine, AName: string; ACol: Integer): Boolean;
var
  InRange, OpenEdge, CloseEdge: Boolean;
begin
  InRange  := (ACol >= 1) and (ACol + Length(AName) - 1 <= Length(ALine));
  if not InRange then Exit(False);
  OpenEdge := (ACol = 1) or not IsIdentChar(ALine[ACol - 1]);
  CloseEdge:= (ACol + Length(AName) > Length(ALine)) or not IsIdentChar(ALine[ACol + Length(AName)]);
  Result   := OpenEdge and CloseEdge and SameText(Copy(ALine, ACol, Length(AName)), AName);
end;

// Column of AName after the declaration keyword run that starts at ACol; 0 when
// ACol does not start such a run or the run is not followed by AName.
function NameAfterDeclKeywords(const ALine, AName: string; ACol: Integer): Integer;
const
  DeclKeywords: array[0..6] of string = ('class', 'procedure', 'function',
    'constructor', 'destructor', 'property', 'operator');
var
  P, Q    : Integer;
  Tok     : string;
  Keywords: Integer;
begin
  Result  := 0;
  Keywords:= 0;
  P       := ACol;
  while (P >= 1) and (P <= Length(ALine)) do
  begin
    Q:= P;
    while (Q <= Length(ALine)) and IsIdentChar(ALine[Q]) do Inc(Q);
    Tok:= Copy(ALine, P, Q - P);
    if (Keywords > 0) and IsIdentAt(ALine, AName, P) then Exit(P);
    if not MatchText(Tok, DeclKeywords) then Exit;
    Inc(Keywords);
    P:= Q;
    while (P <= Length(ALine)) and CharInSet(ALine[P], [' ', #9]) do Inc(P);
  end;
end;

procedure SnapEditsToToken(AList: TList<TRenameEdit>);
var
  Cache: TObjectDictionary<string, TStringList>;
  Lines: TStringList;
  Edit : TRenameEdit;
  I    : Integer;
  Col  : Integer;
begin
  Cache:= TObjectDictionary<string, TStringList>.Create([doOwnsValues]);
  try
    for I:= 0 to AList.Count - 1 do
    begin
      Edit:= AList[I];
      if not Cache.TryGetValue(UpperCase(Edit.FilePath), Lines) then
      begin
        Lines:= TStringList.Create;
        if TFile.Exists(Edit.FilePath) then Lines.Text:= TEncoding.ANSI.GetString(TFile.ReadAllBytes(Edit.FilePath));
        Cache.Add(UpperCase(Edit.FilePath), Lines);
      end;
      if (Edit.Line < 1) or (Edit.Line > Lines.Count) then Continue;
      if IsIdentAt(Lines[Edit.Line - 1], Edit.OldName, Edit.Col) then Continue;
      Col:= NameAfterDeclKeywords(Lines[Edit.Line - 1], Edit.OldName, Edit.Col);
      if Col > 0 then
      begin
        Edit.Col:= Col;
        AList[I]:= Edit;
      end;
    end;
  finally
    Cache.Free;
  end;
end;

// ---------------------------------------------------------------------------
// TRenameRefactoring
// ---------------------------------------------------------------------------

class function TRenameRefactoring.Build(const AStore: ISymbolStore; const AQName, ANewName: string): TArray<TRenameEdit>;
var
  Syms     : TArray<TSymbol>       ;
  Refs     : TArray<TReference>    ;
  ShortName: string                ;
  Sym      : TSymbol               ;
  Ref      : TReference            ;
  Edit     : TRenameEdit           ;
  List     : TList<TRenameEdit>    ;
  Comparer : IComparer<TRenameEdit>;
begin
  Result:= nil;
  Syms:= AStore.FindSymbolsByQualifiedName(AQName);
  if Length(Syms) = 0 then Exit;
  Sym:= Syms[0];

  ShortName:= LastDotSegment(AQName);

  List:= TList<TRenameEdit>.Create;
  try
    // Declaration site
    Edit.FilePath:= AStore.GetFilePath(Sym.FileId);
    Edit.Line:= Sym.StartLine;
    Edit.Col := Sym.StartCol;
    Edit.OldName:= ShortName;
    Edit.NewName:= ANewName;
    List.Add(Edit);

    // All reference sites
    Refs:= AStore.FindCallersByName(ShortName);
    for Ref in Refs do
    begin
      Edit.FilePath:= AStore.GetFilePath(Ref.FileId);
      Edit.Line:= Ref.StartLine;
      Edit.Col := Ref.StartCol;
      Edit.OldName:= ShortName;
      Edit.NewName:= ANewName;
      List.Add(Edit);
    end;

    // Implementation-section header (procedure TFoo.Bar;) -- NOT a decl symbol nor
    // a refs row, so neither branch above catches it. Emit it explicitly when the
    // symbol has a separate impl body (ImplStartLine > 0 and <> the decl line).
    if (Sym.ImplStartLine > 0) and (Sym.ImplStartLine <> Sym.StartLine) then
    begin
      var ImplPath: string := AStore.GetFilePath(Sym.FileId);
      if TFile.Exists(ImplPath) then
      begin
        var ILines := TStringList.Create;
        try
          ILines.Text := TEncoding.ANSI.GetString(TFile.ReadAllBytes(ImplPath));
          if Sym.ImplStartLine <= ILines.Count then
          begin
            var LnText := ILines[Sym.ImplStartLine - 1];
            // The name as a whole identifier: preceded by '.' for the dotted
            // Type.Name member shape, else (a global routine's own impl header,
            // `function Compute(...)`) the first occurrence on the line.
            var HitCol  := 0;
            var ScanAt  := FindIdentFrom(LnText, ShortName, 1);
            while ScanAt > 0 do
            begin
              if HitCol = 0 then HitCol:= ScanAt;
              if (ScanAt >= 2) and (LnText[ScanAt - 1] = '.') then
              begin
                HitCol:= ScanAt;
                Break;
              end;
              ScanAt:= FindIdentFrom(LnText, ShortName, ScanAt + 1);
            end;
            if HitCol > 0 then
            begin
              Edit.FilePath := ImplPath;
              Edit.Line     := Sym.ImplStartLine;
              Edit.Col      := HitCol;
              Edit.OldName  := ShortName;
              Edit.NewName  := ANewName;
              List.Add(Edit);
            end;
          end;
        finally
          ILines.Free;
        end;
      end;
    end;

    // Every edit's Col onto its name token BEFORE the dedup below, so a keyword-
    // column decl row and a name-column row for the same token collapse.
    SnapEditsToToken(List);

    // Dedup by exact (FilePath, Line, Col). Multiple sources above can legitimately
    // point at the SAME source position: e.g. a bare paren-less method call like
    // `t.DoIt;` is walked by both the statement-level bare-call handler ('call'
    // kind ref) and the generic exprDot usage-ref handler ('member-access' kind
    // ref, ref-gap G), so FindCallersByName returns TWO ref rows at the identical
    // (file, line, col) for that one call site. Apply() replaces OldName with
    // NewName in place; since OldName is a PREFIX of NewName in the common case
    // (DoIt -> DoItNow), a second replace at the same position re-matches the
    // just-written text's OldName prefix and appends NewName's suffix a second
    // time (DoIt -> DoItNow -> DoItNowNow). A rename at a given position must
    // fire exactly once no matter how many rows independently reference it, so
    // collapse same-position edits here, keeping the first (decl site, then refs,
    // then the explicit impl-header edit -- order is immaterial since duplicates
    // share the same OldName/NewName).
    var SeenPos:= TDictionary<string, Boolean>.Create;
    try
      var Idx:= 0;
      while Idx < List.Count do
      begin
        var PosKey:= UpperCase(List[Idx].FilePath) + '|' + IntToStr(List[Idx].Line) + '|' + IntToStr(List[Idx].Col);
        if SeenPos.ContainsKey(PosKey) then List.Delete(Idx)
        else begin SeenPos.Add(PosKey, True); Inc(Idx); end;
      end;
    finally
      SeenPos.Free;
    end;

    // Sort: FilePath ASC, Line DESC, Col DESC
    Comparer:= TComparer<TRenameEdit>.Construct( function(const A, B: TRenameEdit): Integer begin Result:= CompareEdits(A, B); end);
    List.Sort(Comparer);

    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end; // function

class function TRenameRefactoring.Apply(const AEdits: TArray<TRenameEdit>; AWriteBackups: Boolean): Integer;
var
  FileMap     : TDictionary<string, TList<TRenameEdit>>;
  Edit        : TRenameEdit                            ;
  FilePath    : string                                 ;
  Group       : TList<TRenameEdit>                     ;
  Pair        : TPair<string, TList<TRenameEdit>>      ;
  RawBytes    : TBytes                                 ;
  Content     : string                                 ;
  Lines       : TStringList                            ;
  LineStr     : string                                 ;
  ColIdx      : Integer                                ; // 0-based index into line string
  OldLen      : Integer                                ;
  FilesTouched: Integer                                ;
begin
  FilesTouched:= 0;
  FileMap:= TDictionary<string, TList<TRenameEdit>>.Create;
  try
    // Group edits by FilePath (edits are already sorted FilePath ASC,
    // Line DESC, Col DESC, so same-file edits are consecutive).
    for Edit in AEdits do
    begin
      if not FileMap.TryGetValue(Edit.FilePath, Group) then
      begin
        Group:= TList<TRenameEdit>.Create;
        FileMap.Add(Edit.FilePath, Group);
      end;
      Group.Add(Edit);
    end;

    for Pair in FileMap do
    begin
      FilePath:= Pair.Key;
      Group   := Pair.Value;
      if not TFile.Exists(FilePath) then Continue;

      // Read as raw bytes, decode as ANSI.
      RawBytes:= TFile.ReadAllBytes(FilePath);
      Content:= TEncoding.ANSI.GetString(RawBytes);

      // Backup before modifying if requested.
      if AWriteBackups then TFile.WriteAllBytes(FilePath + '.bak', RawBytes);

      // Split into lines. We preserve original line endings by splitting
      // on #10 after stripping #13, then re-joining with CRLF.
      Lines:= TStringList.Create;
      try
        Lines.Text:= Content;
        // Lines.Text splits on CR/LF/CRLF automatically.

        // Apply each edit in this file. They are sorted Line DESC / Col DESC
        // so later positions in the file come first, avoiding offset drift.
        for Edit in Group do
        begin
          // Convert 1-based Line to 0-based Lines index.
          if (Edit.Line < 1) or (Edit.Line > Lines.Count) then Continue;
          LineStr:= Lines[Edit.Line - 1];
          // Convert 1-based Col to 0-based string index.
          ColIdx:= Edit.Col - 1;
          OldLen:= Length(Edit.OldName);
          if ColIdx < 0 then ColIdx:= 0;
          // Verify the token at the expected position matches (case-insensitive).
          // If it doesn't, the parser may have stored the keyword position
          // (e.g. "function" before "Compute"). In that case, scan forward
          // on the same line for the first occurrence of OldName as a token.
          if (ColIdx + OldLen > Length(LineStr)) or (not SameText(Copy(LineStr, ColIdx + 1, OldLen), Edit.OldName)) then
          begin
            // Linear scan from ColIdx forward.
            var ScanPos:= ColIdx;
            var Found  := False;
            while ScanPos + OldLen <= Length(LineStr) do
            begin
              if SameText(Copy(LineStr, ScanPos + 1, OldLen), Edit.OldName) then
              begin
                ColIdx:= ScanPos;
                Found := True;
                Break;
              end;
              Inc(ScanPos);
            end;
            if not Found then Continue;
          end; // if
          Lines[Edit.Line - 1]:= Copy(LineStr, 1, ColIdx) + Edit.NewName + Copy(LineStr, ColIdx + OldLen + 1, MaxInt);
        end; // for

        // Re-encode as ANSI bytes preserving CRLF.
        // TStringList.Text uses system line ending; force CRLF explicitly.
        var SB:= TStringBuilder.Create;
        try
          var I: Integer;
          for I:= 0 to Lines.Count - 1 do
          begin
            SB.Append(Lines[I]);
            if I < Lines.Count - 1 then SB.Append(#13#10);
          end;
          // Preserve trailing newline if original had one.
          if (Length(Content) > 0) and (Content[Length(Content)] = #10) then SB.Append(#13#10);
          TFile.WriteAllBytes(FilePath, TEncoding.ANSI.GetBytes(SB.ToString));
        finally
          SB.Free;
        end; // try
        Inc(FilesTouched);
      finally
        Lines.Free;
      end; // try
    end; // for
  finally
    for Pair in FileMap do Pair.Value.Free;
    FileMap.Free;
  end; // try
  Result:= FilesTouched;
end; // function

class function TRenameRefactoring.RenderDryRun( const AEdits: TArray<TRenameEdit>): string;
var
  SB      : TStringBuilder;
  Edit    : TRenameEdit   ;
  LastFile: string        ;
begin
  SB:= TStringBuilder.Create;
  try
    LastFile:= '';
    for Edit in AEdits do
    begin
      if Edit.FilePath <> LastFile then
      begin
        SB.AppendLine('File: ' + Edit.FilePath);
        LastFile:= Edit.FilePath;
      end;
      SB.AppendLine(Format('  L%d:C%d  %s -> %s', [Edit.Line, Edit.Col, Edit.OldName, Edit.NewName]));
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end; // function

class function TRenameRefactoring.BuildLocal(const AFile: string; ALine, ACol: Integer;
  const ANewName: string): TArray<TRenameEdit>;
var
  PF       : TParsedFile        ;
  Src      : TBytes             ;
  Edits    : TList<TRenameEdit> ;
  Target   : string             ;
  OwnerProc: TTSNode            ;

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

  procedure AddEdit(const N: TTSNode);
  var Ed: TRenameEdit;
  begin
    Ed.FilePath:= AFile; Ed.Line:= NLine(N); Ed.Col:= NColOf(N);
    Ed.OldName:= Target; Ed.NewName:= ANewName;
    Edits.Add(Ed);
  end;

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

  { Smallest enclosing defProc of a node, by byte span. }
  function EnclosingProc(const ATargetByte: Integer; const N: TTSNode; const ABest: TTSNode): TTSNode;
  var I: Integer; Ch: TTSNode;
  begin
    Result:= ABest;
    if N.IsNull then Exit;
    if (N.NodeType = 'defProc')
      and (Integer(N.StartByte) <= ATargetByte) and (Integer(N.EndByte) >= ATargetByte) then
      Result:= N;
    for I:= 0 to N.NamedChildCount - 1 do
    begin
      Ch:= N.NamedChild(I);
      Result:= EnclosingProc(ATargetByte, Ch, Result);
    end;
  end;

  { True when a defProc's header args re-declare Target (shadowing guard). }
  function NestedRedeclares(const AProc: TTSNode): Boolean;
  var HN, AN, Nm: TTSNode; K, J: Integer;
  begin
    Result:= False;
    HN:= AProc.ChildByField('header');
    if HN.IsNull then Exit;
    AN:= HN.ChildByField('args');
    if AN.IsNull then Exit;
    for K:= 0 to AN.NamedChildCount - 1 do
    begin
      Nm:= AN.NamedChild(K);
      if Nm.NodeType <> 'declArg' then Continue;
      for J:= 0 to Nm.NamedChildCount - 1 do
        if (Nm.NamedChild(J).NodeType = 'identifier')
          and SameText(Trim(NStr(Nm.NamedChild(J))), Target) then Exit(True);
    end;
  end;

  { Walk the owning routine subtree, emitting edits for bare-identifier uses of
    Target. Skip: a nested defProc that re-declares Target (shadowing); the rhs
    of an exprDot or genericDot (qualified member access); a 'with' statement
    subtree (ambiguous). }
  procedure Walk(const N: TTSNode);
  var I: Integer; Ch: TTSNode;
  begin
    if N.IsNull then Exit;
    { Entering a nested defProc that shadows Target -> stop descending for renames. }
    if (not (N = OwnerProc)) and (N.NodeType = 'defProc') and NestedRedeclares(N) then
      Exit;
    { Skip with-statement subtrees (ambiguous). }
    if N.NodeType = 'with' then Exit;
    { An identifier matching Target. }
    if (N.NodeType = 'identifier') and SameText(Trim(NStr(N)), Target) then
    begin
      AddEdit(N);
      Exit;
    end;
    for I:= 0 to N.NamedChildCount - 1 do
    begin
      Ch:= N.NamedChild(I);
      { Exclude qualified-member rhs (member access): skip the last named child of
        exprDot (Foo.Value) and genericDot (TType.Value / UnitName.Value). Both are
        [lhs, rhs] two-child nodes; skipping index NamedChildCount-1 skips the rhs
        member while still walking the lhs. }
      if ((N.NodeType = 'exprDot') or (N.NodeType = 'genericDot'))
          and (I = N.NamedChildCount - 1) then Continue;
      Walk(Ch);
    end;
  end;

  { Add the matching parameter in any forward/interface declProc with the same
    routine name as OwnerProc. Scans all declProc nodes in the file.
    NOTE: declProc has 'args' as a direct child field (no 'header' wrapper). }
  procedure SyncForwardHeaders(const ARoot: TTSNode);
  var I   : Integer;
    OwnerName: string;

    function HdrName(const AProc: TTSNode): string;
    var H, Nm: TTSNode;
    begin
      Result:= '';
      { defProc: name is under header field }
      H:= AProc.ChildByField('header');
      if not H.IsNull then
      begin
        Nm:= H.ChildByField('name');
        if not Nm.IsNull then begin Result:= Trim(NStr(Nm)); Exit; end;
      end;
      { declProc: name is a direct child field }
      Nm:= AProc.ChildByField('name');
      if not Nm.IsNull then Result:= Trim(NStr(Nm));
    end;

    procedure ScanDeclArgs(const AProc: TTSNode);
    var AN, NmN, Id: TTSNode; K, J: Integer; TypeStart: Integer; TN: TTSNode;
    begin
      { declProc: args is direct child field }
      AN:= AProc.ChildByField('args');
      if AN.IsNull then Exit;
      for K:= 0 to AN.NamedChildCount - 1 do
      begin
        NmN:= AN.NamedChild(K);
        if NmN.NodeType <> 'declArg' then Continue;
        TN:= NmN.ChildByField('type'); TypeStart:= MaxInt;
        if not TN.IsNull then TypeStart:= Integer(TN.StartByte);
        for J:= 0 to NmN.NamedChildCount - 1 do
        begin
          Id:= NmN.NamedChild(J);
          if Id.NodeType <> 'identifier' then Continue;
          if Integer(Id.StartByte) >= TypeStart then Continue;
          if SameText(Trim(NStr(Id)), Target) then AddEdit(Id);
        end;
      end;
    end;

  var
    Stack: TList<TTSNode>;
    Cur  : TTSNode;
  begin
    OwnerName:= HdrName(OwnerProc);
    if OwnerName = '' then Exit;
    Stack:= TList<TTSNode>.Create;
    try
      Stack.Add(ARoot);
      while Stack.Count > 0 do
      begin
        Cur:= Stack[Stack.Count - 1];
        Stack.Delete(Stack.Count - 1);
        if Cur.NodeType = 'declProc' then
        begin
          if SameText(HdrName(Cur), OwnerName) then ScanDeclArgs(Cur);
        end;
        for I:= 0 to Cur.NamedChildCount - 1 do Stack.Add(Cur.NamedChild(I));
      end;
    finally
      Stack.Free;
    end;
  end;

var
  IdNode  : TTSNode;
  Dedup   : TDictionary<string, Boolean>;
  Ed      : TRenameEdit;
  Key     : string;
  Comparer: IComparer<TRenameEdit>;
  Final   : TList<TRenameEdit>;
begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;

  IdNode:= FindIdentAt(PF.Tree.RootNode);
  if IdNode.IsNull then Exit;
  Target:= Trim(NStr(IdNode));
  if Target = '' then Exit;

  OwnerProc:= EnclosingProc(Integer(IdNode.StartByte), PF.Tree.RootNode, Default(TTSNode));
  if OwnerProc.IsNull then Exit;

  Edits:= TList<TRenameEdit>.Create;
  try
    Walk(OwnerProc);
    SyncForwardHeaders(PF.Tree.RootNode);

    { De-dup by (line,col); sort back-to-front for Apply. }
    Dedup:= TDictionary<string, Boolean>.Create;
    Final:= TList<TRenameEdit>.Create;
    try
      for Ed in Edits do
      begin
        Key:= IntToStr(Ed.Line) + ':' + IntToStr(Ed.Col);
        if not Dedup.ContainsKey(Key) then begin Dedup.Add(Key, True); Final.Add(Ed); end;
      end;
      Comparer:= TComparer<TRenameEdit>.Construct(
        function(const A, B: TRenameEdit): Integer
        begin
          Result:= B.Line - A.Line;
          if Result = 0 then Result:= B.Col - A.Col;
        end);
      Final.Sort(Comparer);
      Result:= Final.ToArray;
    finally
      Final.Free;
      Dedup.Free;
    end;
  finally
    Edits.Free;
  end;
end;


// ---------------------------------------------------------------------------
// Conflict detection helpers
// ---------------------------------------------------------------------------

class function TRenameRefactoring.IsReservedWord(const AName: string): Boolean;
const
  KReserved: array[0..63] of string = (
    'and','array','as','asm','begin','case','class','const','constructor','destructor',
    'dispinterface','div','do','downto','else','end','except','exports','file','finalization',
    'finally','for','function','goto','if','implementation','in','inherited','initialization',
    'inline','interface','is','label','library','mod','nil','not','object','of','or',
    'packed','procedure','program','property','raise','record','repeat','resourcestring',
    'set','shl','shr','string','then','threadvar','to','try','type','unit','until','uses',
    'var','while','with','xor');
var L, H, M, C: Integer; Low: string;
begin
  Low:= LowerCase(AName);
  L:= 0; H:= High(KReserved);
  while L <= H do
  begin
    M:= (L + H) div 2;
    C:= CompareStr(Low, KReserved[M]);
    if C = 0 then Exit(True)
    else if C < 0 then H:= M - 1
    else L:= M + 1;
  end;
  Result:= False;
end;

class function TRenameRefactoring.ConflictReason(const AStore: ISymbolStore;
  const AQName, ANewName: string): string;
var
  Syms: TArray<TSymbol>;
  Sib : TSymbol;
begin
  Result:= '';
  if IsReservedWord(ANewName) then
    Exit(Format('"%s" is a reserved word', [ANewName]));
  Syms:= AStore.FindSymbolsByQualifiedName(AQName);
  if Length(Syms) = 0 then Exit;
  { sibling-name collision under the same parent }
  Sib:= AStore.FindChildSymbolByName(Syms[0].ParentId, ANewName);
  if Sib.Id <> 0 then
    Exit(Format('a symbol named "%s" already exists in the same scope', [ANewName]));
end;

{ True when AName occurs in AText as a whole Pascal identifier token outside
  comments and string literals (case-insensitive). }
const
  IDENT_START = ['A'..'Z', 'a'..'z', '_'];
  IDENT_CHARS = ['A'..'Z', 'a'..'z', '_', '0'..'9'];

{ Index just past the comment, string literal or numeric run that starts at
  APos in AText; APos itself when none starts there. A number, hex ($FF) or
  char code (#13) is skipped whole so its digit run never reads as a name. }
function SkipNonIdent(const AText: string; APos: Integer): Integer;
var
  Len: Integer;
begin
  Len:= Length(AText);
  Result:= APos;
  if AText[APos] = '{' then
    Result:= Pos('}', AText, APos + 1)
  else if Copy(AText, APos, 2) = '(*' then
    Result:= Pos('*)', AText, APos + 2) + 1
  else if Copy(AText, APos, 2) = '//' then
    Result:= Pos(#10, AText, APos + 2)
  else if AText[APos] = '''' then
    Result:= Pos('''', AText, APos + 1)
  else if CharInSet(AText[APos], ['0'..'9', '$', '#']) then
  begin
    Result:= APos + 1;
    while (Result <= Len) and CharInSet(AText[Result], IDENT_CHARS) do Inc(Result);
    Exit;
  end
  else
    Exit;
  { an unterminated comment or string runs to the end of the text }
  if Result <= APos then Result:= Len;
  Inc(Result);
end;

function IdentOccursIn(const AText, AName: string): Boolean;
var
  I, Len, Start, Next: Integer;
begin
  Result:= False;
  Len:= Length(AText);
  I:= 1;
  while I <= Len do
  begin
    Next:= SkipNonIdent(AText, I);
    if Next > I then
      I:= Next
    else if CharInSet(AText[I], IDENT_START) then
    begin
      Start:= I;
      while (I <= Len) and CharInSet(AText[I], IDENT_CHARS) do Inc(I);
      if SameText(Copy(AText, Start, I - Start), AName) then Exit(True);
    end
    else
      Inc(I);
  end;
end;

class function TRenameRefactoring.IncludeUseReason(const AStore: ISymbolStore;
  const AQName: string): string;
var
  ShortName: string;
  Hits     : TStringList;
  Stamp    : TFileStamp;
begin
  Result:= '';
  ShortName:= LastDotSegment(AQName);
  if ShortName = '' then Exit;
  Hits:= TStringList.Create;
  try
    for Stamp in AStore.GetAllFileStamps do
      if SameText(ExtractFileExt(Stamp.Path), '.inc') and FileExists(Stamp.Path)
        and IdentOccursIn(TFile.ReadAllText(Stamp.Path, TEncoding.ANSI), ShortName) then
        Hits.Add(Stamp.Path);
    if Hits.Count = 0 then Exit;
    Hits.Sort;
    Result:= Format('"%s" is used in include file(s) %s -- the index records no ' +
      'references inside {$I} included text yet (extractor 1.22), so those uses ' +
      'would be left stale. Rename them by hand together with the declaration.',
      [ShortName, string.Join(', ', Hits.ToStringArray)]);
  finally
    Hits.Free;
  end;
end;

class function TRenameRefactoring.BinaryDfmReason(const AStore: ISymbolStore;
  const AQName: string): string;
const
  ResHeaderByte = $FF;
var
  Syms     : TArray<TSymbol>;
  ShortName: string;
  DfmPath  : string;
  Bytes    : TBytes;
begin
  Result:= '';
  ShortName:= LastDotSegment(AQName);
  Syms:= AStore.FindSymbolsByQualifiedName(AQName);
  if (ShortName = '') or (Length(Syms) = 0) then Exit;
  DfmPath:= ChangeFileExt(AStore.GetFilePath(Syms[0].FileId), '.dfm');
  if not FileExists(DfmPath) then Exit;
  Bytes:= TFile.ReadAllBytes(DfmPath);
  if Length(Bytes) = 0 then Exit;
  if (Bytes[0] <> ResHeaderByte) and not TEncoding.ANSI.GetString(Bytes).StartsWith('TPF0') then Exit;
  if FindIdentFrom(TEncoding.ANSI.GetString(Bytes), ShortName, 1) = 0 then Exit;
  Result:= Format('%s is a binary .dfm that contains "%s" -- rename only rewrites ' +
    'event bindings in text .dfm files, so the form would keep the old name. ' +
    'Convert it to text (IDE: right-click the form > Text DFM, or convert.exe -t) and ' +
    're-index first.', [DfmPath, ShortName]);
end;

class function TRenameRefactoring.StaleEditReason(const AEdits: TArray<TRenameEdit>): string;
var
  Cache: TObjectDictionary<string, TStringList>;
  Lines: TStringList;
  Edit : TRenameEdit;
begin
  Result:= '';
  Cache:= TObjectDictionary<string, TStringList>.Create([doOwnsValues]);
  try
    for Edit in AEdits do
    begin
      if not Cache.TryGetValue(UpperCase(Edit.FilePath), Lines) then
      begin
        Lines:= TStringList.Create;
        Cache.Add(UpperCase(Edit.FilePath), Lines);
        if TFile.Exists(Edit.FilePath) then Lines.Text:= TEncoding.ANSI.GetString(TFile.ReadAllBytes(Edit.FilePath));
      end;
      if (Edit.Line < 1) or (Edit.Line > Lines.Count) or not IsIdentAt(Lines[Edit.Line - 1], Edit.OldName, Edit.Col) then
        Exit(Format('index out of date for %s:%d (no "%s" at column %d) -- save and reindex, then retry',
          [Edit.FilePath, Edit.Line, Edit.OldName, Edit.Col]));
    end;
  finally
    Cache.Free;
  end;
end;

end.