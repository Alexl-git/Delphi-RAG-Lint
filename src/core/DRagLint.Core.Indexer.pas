unit DRagLint.Core.Indexer;

interface

uses
  System.SysUtils
  , System.Classes
  , System.StrUtils
  , System.IOUtils
  , System.Hash
  , System.DateUtils
  , System  .Generics.Collections
  , DRagLint.Core    .Model
  , DRagLint.Core    .Interfaces
  , DRagLint.Core    .Encoding
  , DRagLint.Index   .Glob
  , DRagLint.Index   .IgnoreFiles
  , DRagLint.Parser  .DocComments
  , DRagLint.Preprocess         { PP-Task-9: in-process directive preprocessor }
  , DRagLint.Preprocess.Types   { TDefineProfile }
  ;

type
  TIndexer = class(TInterfacedObject, IIndexer)
    strict private
      FStore          : ISymbolStore                       ;
      FParsers        : TList<IParser>                     ;
      FSkippedUpToDate: Integer                            ;
      FDocConfig      : TDocConfig                         ;
      FExcludeRoots   : TList<string>                      ; { v0.42: normalized lowercase, trailing-sep }
      FWalkFilter     : TWalkFilter                        ; { v0.45: glob/ignore filtering }
      FIgnoreStack    : TIgnoreStack                       ; { v0.45: .gitignore/.hgignore stack; nil when not UseIgnoreFiles }
      FPreprocessEnabled: Boolean                          ; { PP-Task-9: run Preprocess before parsing }
      FProfile        : TDefineProfile                     ; { PP-Task-9: active define profile when preprocessing }
      FPreprocessFellBack: Boolean                         ; { PP-Task-9: one-shot fallback-log latch }
      /// <summary>PP-Task-9: log a per-file preprocess fallback the FIRST time it
      /// happens in this run, then stay silent so a bad batch does not flood the
      /// output with one line per file. The file is still indexed from its RAW
      /// UTF-8 bytes (old behaviour) -- a preprocess exception never hard-fails
      /// the run.</summary>
      procedure LogPreprocessFallbackOnce(const AFilePath: string; const AError: Exception);
      function ParserFor(const AExtension: string): IParser;
      procedure ReportProgress(const APath: string; ASymbols, ARefs, AErrors: Integer);
      function IsUnderExcludeRoot  (const APath: string): Boolean;
      function ShouldPruneDir      (const ADir : string): Boolean;
      function SqlFileAllowedFilter(const APath: string): Boolean;
      /// <summary>v13 (v0.82): resolve a ref's innermost enclosing routine.
      /// Among ASymbols of routine kind (method/function/procedure/constructor/
      /// destructor) with ImplStartLine &gt; 0 whose [ImplStartLine..ImplEndLine]
      /// contains ALine, pick the one with the LARGEST ImplStartLine (innermost --
      /// so a nested procedure wins over its outer routine), then map its array
      /// index to its DB id via AIdxToId.</summary>
      /// <param name="ASymbols">The file's just-parsed symbols (index i == the key used in AIdxToId).</param>
      /// <param name="AIdxToId">Array-index -&gt; inserted DB id map built by the symbols loop.</param>
      /// <param name="ALine">The ref's StartLine.</param>
      /// <returns>The enclosing routine's DB id, or 0 when the line is in no routine body.</returns>
      function ResolveEnclosingSymbolId(const ASymbols: TArray<TSymbol>;
        const AIdxToId: TDictionary<Integer, Int64>; ALine: Integer): Int64;
      /// <summary>v(ADP2 T2): 1-based, inclusive line-range slice of ALines
      /// (the file's SourceText, already split once per IndexFile call),
      /// clipped to ALines' actual bounds. Feeds a routine symbol's impl body
      /// to TSymbolFactsAnalyzer.Analyze without a per-symbol re-read/re-split
      /// of the file.</summary>
      /// <param name="ALines">The file's source lines (index 0 == line 1).</param>
      /// <param name="AFromLine">First body line, 1-based (Sym.ImplStartLine).</param>
      /// <param name="AToLine">Last body line, 1-based (Sym.ImplEndLine).</param>
      /// <returns>ALines[AFromLine..AToLine] clipped to bounds; nil when the
      /// clipped range is empty (e.g. ALines is empty).</returns>
      function SliceBodyLines(const ALines: TArray<string>; AFromLine, AToLine: Integer): TArray<string>;
      procedure WalkAndIndex(const ADir: string; ARecursive: Boolean);
    public
      constructor Create(const AStore: ISymbolStore; const AParsers: TArray<IParser>; const ADocConfig: TDocConfig); overload;
      constructor Create(const AStore: ISymbolStore; const AParsers: TArray<IParser>); overload;
      destructor Destroy; override;
      procedure IndexFolder(const APath: string; ARecursive: Boolean = True);
      procedure IndexFile(const AFilePath: string);
      function SkippedUpToDate: Integer;
      procedure AddExcludeRoot(const APath: string);
      procedure SetWalkFilter(const AFilter: TWalkFilter);
      procedure SetPreprocess(AEnabled: Boolean; const AProfile: TDefineProfile);
  end;

implementation

uses
  DRagLint.Doc.SymbolFacts        { v(ADP2 T2): TSymbolFactsAnalyzer -- index-time symbol_facts pass }
  , DRagLint.Diagnostics.ParseCache { v(ADP2 T3): TAstParseCache.Clear -- bound the per-file tree cache }
  ;

constructor TIndexer.Create(const AStore: ISymbolStore; const AParsers: TArray<IParser>; const ADocConfig: TDocConfig);
var
  P: IParser;
begin
  inherited Create;
  FStore    := AStore;
  FDocConfig:= ADocConfig;
  FParsers:= TList<IParser>.Create;
  FExcludeRoots:= TList<string>.Create;
  FIgnoreStack:= nil;
  { PP-Task-9: safe default -- preprocessing OFF until a caller opts in via
    SetPreprocess. A bare TIndexer (tests, embedders) keeps the pre-Task-9 raw
    all-branch behaviour; the CLI enables it by default (--no-preprocess opts
    out). FProfile stays empty (an empty profile = no seeded defines). }
  FPreprocessEnabled := False;
  FPreprocessFellBack:= False;
  { v0.45: default filter preserves prior behaviour -- only MS*.SQL indexed. }
  FWalkFilter:= TWalkFilter.Create;
  for P in AParsers do FParsers.Add(P);
end;

constructor TIndexer.Create(const AStore: ISymbolStore; const AParsers: TArray<IParser>);
begin
  Create(AStore, AParsers, DefaultDocConfig);
end;

destructor TIndexer.Destroy;
begin
  FParsers.Free;
  FExcludeRoots.Free;
  FIgnoreStack.Free;
  FStore:= nil;
  inherited;
end;

function TIndexer.SkippedUpToDate: Integer;
begin
  Result:= FSkippedUpToDate;
end;

procedure TIndexer.AddExcludeRoot(const APath: string);
var
  Norm: string;
begin
  if APath = '' then Exit;
  Norm:= LowerCase(IncludeTrailingPathDelimiter( ExcludeTrailingPathDelimiter(APath)));
  if not FExcludeRoots.Contains(Norm) then FExcludeRoots.Add(Norm);
end;

function TIndexer.IsUnderExcludeRoot(const APath: string): Boolean;
var
  L   : string;
  Root: string;
begin
  Result:= False;
  if FExcludeRoots.Count = 0 then Exit;
  L:= LowerCase(APath);
  for Root in FExcludeRoots do
    if StartsStr(Root, L) then Exit(True);
end;

procedure TIndexer.SetWalkFilter(const AFilter: TWalkFilter);
begin
  FWalkFilter:= AFilter;
  { (Re)create the ignore stack when UseIgnoreFiles is toggled. }
  FreeAndNil(FIgnoreStack);
  if FWalkFilter.UseIgnoreFiles then FIgnoreStack:= TIgnoreStack.Create;
end;

procedure TIndexer.SetPreprocess(AEnabled: Boolean; const AProfile: TDefineProfile);
begin
  { PP-Task-9: latch the per-run flag + profile. Reset the one-shot fallback
    latch so each run gets its own first-fallback log line. }
  FPreprocessEnabled := AEnabled;
  FProfile           := AProfile;
  FPreprocessFellBack:= False;
end;

procedure TIndexer.LogPreprocessFallbackOnce(const AFilePath: string; const AError: Exception);
begin
  { PP-Task-9: never hard-fail an index run because one file's preprocess threw
    -- the file is still indexed from its RAW UTF-8 bytes (old behaviour). Log
    only the FIRST fallback so a bad batch does not flood stderr with one line
    per file. }
  if FPreprocessFellBack then Exit;
  FPreprocessFellBack:= True;
  Writeln(ErrOutput, Format(
    '  PREPROCESS FALLBACK: %s -- %s: %s (indexing raw; further fallbacks silent)',
    [AFilePath, AError.ClassName, AError.Message]));
end;

function TIndexer.ParserFor(const AExtension: string): IParser;
var
  P    : IParser;
  E    : string ;
  Lower: string ;
begin
  Lower:= LowerCase(AExtension);
  for P in FParsers do
    for E in P.FileExtensions do
      if SameText(E, Lower) then Exit(P);
  Result:= nil;
end;

procedure TIndexer.ReportProgress(const APath: string; ASymbols, ARefs, AErrors: Integer);
begin
  Writeln(Format('  %s -> %d symbols, %d refs, %d errors', [APath, ASymbols, ARefs, AErrors]));
end;

// Returns the TDocCommentRegion immediately preceding ASymStartLine
// (EndLine in [SymStartLine - 1 - AllowGap, SymStartLine - 1]), REJECTING that
// candidate when another declaration's StartLine sits strictly BETWEEN the
// region and ASymStartLine (Best.EndLine < L < ASymStartLine for some L in
// ASymStartLines) -- such a region belongs to the INTERVENING declaration,
// not this one. Without this check, two back-to-back declarations with no
// blank line between them (A documented, B immediately after) both matched
// A's doc-comment against the line-distance window alone, so `document
// --apply` treated A's block as B's *existing* doc and rewrote/duplicated it
// -- corrupting A's comment and stamping A's prose onto B (see
// adp2-docregion-fix-report.md). ASymStartLines must be sorted ascending
// (every symbol's StartLine in the file, including ASymStartLine's own); the
// scan below early-exits once L >= ASymStartLine, keeping the cost bounded
// even on files with many symbols. A region separated from ASymStartLine by
// only blank lines (no intervening declaration) is unaffected -- blank lines
// are never symbol start-lines.
// When ACaptureLoose is False, regions with Kind in [dckLooseLine, dckLooseBlock]
// are skipped entirely.
// Sentinel: Result.Kind = TDocCommentKind(-1) means no region found.
// v(ADP3 T3j review round 1): the window and the guard described above are no
// longer implemented here -- both delegate to DRagLint.Core.Model's
// DocRegionInGapWindow + NoDeclarationInGap, shared with the twin copy in
// DRagLint.Doc.Document and with DRagLint.Doc.Strip's `--strip` path, so the
// three attribution sites cannot drift. See the block comment on those
// functions for why that mattered (register S1).
function FindDocRegionAbove(ADocRegions: TList<TDocCommentRegion>; ASymStartLine: Integer;
  AAllowGap: Integer; ACaptureLoose: Boolean; const ASymStartLines: TArray<Integer>): TDocCommentRegion;
var
  I      : Integer          ;
  Best   : TDocCommentRegion;
  HasBest: Boolean          ;
begin
  HasBest:= False;
  // ADocRegions is sorted by StartLine ascending.
  for I:= 0 to ADocRegions.Count - 1 do
  begin
    // Skip loose regions when captureLooseComments is disabled.
    if (not ACaptureLoose) and (ADocRegions[I].Kind in [dckLooseLine, dckLooseBlock]) then Continue;
    // v(ADP3 T3j review round 1): the window is now the SHARED
    // DocRegionInGapWindow (DRagLint.Core.Model) -- same arithmetic, one
    // declaration. Control flow deliberately unchanged: pick the last region
    // satisfying the window, THEN apply the declaration guard to it below.
    if DocRegionInGapWindow(ADocRegions[I].EndLine, ASymStartLine, AAllowGap) then
    begin
      Best:= ADocRegions[I];
      HasBest:= True;
    end;
    if ADocRegions[I].StartLine > ASymStartLine then Break;
  end;
  // Intervening-declaration check: reject Best when some OTHER symbol starts
  // strictly between Best.EndLine and ASymStartLine. v(ADP3 T3j review round 1):
  // now the SHARED NoDeclarationInGap, which `document --strip` reads too -- the
  // T3j defect was Doc.Strip copying the window above without this guard.
  if HasBest and (not NoDeclarationInGap(Best.EndLine, ASymStartLine, ASymStartLines)) then
    HasBest:= False;
  if HasBest then Result:= Best
  else
  begin
    FillChar(Result, SizeOf(Result), 0);
    Result.Kind:= TDocCommentKind(-1);
  end;
end; // function

function TIndexer.ResolveEnclosingSymbolId(const ASymbols: TArray<TSymbol>;
  const AIdxToId: TDictionary<Integer, Int64>; ALine: Integer): Int64;
var
  I         : Integer;
  BestIdx   : Integer;
  BestStart : Integer;
  DbId      : Int64  ;
begin
  Result   := 0 ;
  BestIdx  := -1;
  BestStart:= 0 ; // any real ImplStartLine is > 0, so the first hit always wins
  for I:= 0 to High(ASymbols) do
  begin
    case ASymbols[I].Kind of
      skMethod, skFunction, skProcedure, skConstructor, skDestructor: ; // routine kinds
    else
      Continue;
    end;
    if ASymbols[I].ImplStartLine <= 0 then Continue;
    if (ALine >= ASymbols[I].ImplStartLine) and (ALine <= ASymbols[I].ImplEndLine) then
    begin
      // Innermost wins: a nested routine has a LARGER ImplStartLine than the
      // outer routine whose body encloses it.
      if ASymbols[I].ImplStartLine > BestStart then
      begin
        BestStart:= ASymbols[I].ImplStartLine;
        BestIdx  := I;
      end;
    end;
  end;
  if (BestIdx >= 0) and AIdxToId.TryGetValue(BestIdx, DbId) then Result:= DbId;
end; // function

function TIndexer.SliceBodyLines(const ALines: TArray<string>; AFromLine, AToLine: Integer): TArray<string>;
var
  Lo, Hi, J: Integer;
begin
  Result:= nil;
  if Length(ALines) = 0 then Exit;
  Lo:= AFromLine;
  Hi:= AToLine;
  if Lo < 1 then Lo:= 1;
  if Hi > Length(ALines) then Hi:= Length(ALines);
  if Hi < Lo then Exit; // empty (or inverted) range after clipping
  SetLength(Result, Hi - Lo + 1);
  for J:= Lo to Hi do Result[J - Lo]:= ALines[J - 1];
end; // function

procedure TIndexer.IndexFile(const AFilePath: string);
var
  Parser        : IParser                    ;
  Source        : TBytes                     ; { raw on-disk bytes: sha/mtime/up-to-date }
  Utf8          : TBytes                     ; { v0.86: transcoded UTF-8 fed to parser/slices }
  ParseBytes    : TBytes                     ; { PP-Task-9: bytes actually parsed (preprocessed when enabled, else = Utf8) }
  SourceText    : string                     ;
  Sha           : string                     ;
  Mtime         : Int64                      ;
  ParseRes      : TParseResult               ;
  Token         : TFileTxToken               ;
  Sym           : TSymbol                    ;
  IdxToId       : TDictionary<Integer, Int64>;
  I             : Integer                    ;
  ResolvedParent: Int64                      ;
  NewSymId      : Int64                      ;
  DocRegions    : TList<TDocCommentRegion>   ;
  DocRegion     : TDocCommentRegion          ;
  ParsedDoc     : TParsedDoc                 ;
  Lit           : TStringLiteral             ;
  Encl          : TSymbol                    ;
  SourceLines   : TArray<string>             ; { v(ADP2 T2): SourceText split once, reused per routine's facts pass }
  Facts         : TSymbolFacts               ; { v(ADP2 T2) }
  FactsBody     : TArray<string>             ; { v(ADP2 T2) }
  SymStartLines : TArray<Integer>            ; { adp2-docregion-fix: every symbol's StartLine, sorted ascending -- lets FindDocRegionAbove reject a region separated from its symbol by an intervening declaration }
begin
  Parser:= ParserFor(ExtractFileExt(AFilePath));
  if Parser = nil then Exit;
  { v0.46: file-size guard -- skip files that would overflow the tree-sitter
    native stack. The segfault is not catchable by Delphi (it is a native
    stack overflow, not an OS exception the RTL wraps). Default: 2048 KB.
    0 = unlimited (caller explicitly opted out). }
  if FWalkFilter.MaxFileKB > 0 then
  begin
    var FileSize: Int64;
    try
      FileSize:= TFile.GetSize(AFilePath);
    except
      FileSize:= 0;
    end;
    if FileSize > Int64(FWalkFilter.MaxFileKB) * 1024 then
    begin
      Writeln(Format('  SKIP %s: %d KB exceeds parse limit (%d KB)', [AFilePath, FileSize div 1024, FWalkFilter.MaxFileKB]));
      Exit;
    end;
  end;
  Source:= TFile.ReadAllBytes(AFilePath);
  // Sha/Mtime/up-to-date stay computed over the RAW on-disk bytes so file
  // identity + the incremental-skip contract are byte-identical to before the
  // v0.86 encoding fix (changing the sha basis would invalidate every already
  // indexed file's stored sha -> forced mass reindex).
  Sha:= THashSHA2.GetHashString(TEncoding.ANSI.GetString(Source));
  Mtime:= DateTimeToUnix(TFile.GetLastWriteTime(AFilePath), False);
  // v0.4: incremental skip. If the file's already in the DB with the same
  // mtime and sha256, nothing to do - the parser would emit the same
  // symbols. Saves a parse + the per-file transaction.
  if FStore.FileIsUpToDate(AFilePath, Mtime, Sha) then
  begin
    Inc(FSkippedUpToDate);
    Exit;
  end;
  // v0.86 (Task 3): transcode ANSI/UTF-16 sources to valid UTF-8 before the
  // parse/slice pipeline (which assumes UTF-8). A valid CP1252 file (0xAE/0xA9
  // in a resourcestring -- the SOFTWID.PAS class) was SKIPPED here with
  // EEncodingError; now it parses. Downstream slice helpers see UTF-8.
  Utf8:= EnsureUtf8Bytes(Source);
  // PP-Task-9: when preprocessing is enabled, resolve compiler-directive
  // branches per the active define profile BEFORE parsing. Preprocess blanks
  // inactive-branch and directive bytes to spaces (LF preserved) and returns a
  // buffer of IDENTICAL byte length -- the offset-identity invariant -- so every
  // symbol/ref span the parser emits still maps 1:1 back to the original file
  // with NO source map. A per-file exception must NOT hard-fail the whole run:
  // log once, then index the RAW UTF-8 for that file (pre-Task-9 behaviour).
  if FPreprocessEnabled then
  begin
    try
      ParseBytes:= Preprocess(Utf8, FProfile);
    except
      on E: Exception do
      begin
        LogPreprocessFallbackOnce(AFilePath, E);
        ParseBytes:= Utf8;
      end;
    end;
  end
  else
    ParseBytes:= Utf8;
  ParseRes:= Parser.Parse(ParseBytes, AFilePath);
  // v0.16: scan doc-comment regions from the source text once per file
  // so we can associate them with symbols by line proximity below.
  // Decode from the bytes the PARSER ACTUALLY SAW (ParseBytes -- preprocessed
  // when enabled, else the transcoded UTF-8) so doc-comment text and symbol line
  // positions agree. Blanking preserves byte length + LF, so the line structure
  // is identical to the raw file; blanked regions carry no doc-comments. For
  // pure-ASCII files with preprocessing off this is the prior UTF-8 decode.
  SourceText:= TEncoding.UTF8.GetString(ParseBytes);
  DocRegions:= TDocCommentScanner.Scan(SourceText);
  try
    Token:= FStore.OpenFileTx(AFilePath, Mtime, Sha, Parser.LanguageName);
    // v0.16: clear stale doc rows for this file before emitting fresh ones
    // (OpenFileTx already cleared symbols and refs).
    FStore.DeleteFileDocs(Token.FileId);
    IdxToId:= TDictionary<Integer, Int64>.Create;
    try
      try
        // adp2-docregion-fix: every symbol's StartLine in this file, sorted
        // ascending, so FindDocRegionAbove can reject a doc region that
        // actually belongs to an INTERVENING declaration (see its header
        // comment). Built once per file, not once per symbol.
        SetLength(SymStartLines, Length(ParseRes.Symbols));
        for I:= 0 to High(ParseRes.Symbols) do
          SymStartLines[I]:= ParseRes.Symbols[I].StartLine;
        TArray.Sort<Integer>(SymStartLines);
        for I:= 0 to High(ParseRes.Symbols) do
        begin
          Sym:= ParseRes.Symbols[I];
          // Translate in-array parent index to actual DB id
          if (Sym.ParentId >= 0) and IdxToId.TryGetValue(Integer(Sym.ParentId), ResolvedParent) then Sym.ParentId:= ResolvedParent
          else Sym.ParentId:= -1;
          NewSymId:= FStore.UpsertSymbol(Token, Sym);
          IdxToId.Add(I, NewSymId);
          // v0.16: associate doc comment region to this symbol.
          // Task 13: AllowBlankLineGap and CaptureLooseComments come from
          // .drag-lint.json "docs" section via FDocConfig.
          DocRegion:= FindDocRegionAbove(DocRegions, Sym.StartLine, FDocConfig.AllowBlankLineGap, FDocConfig.CaptureLooseComments, SymStartLines);
          if DocRegion.Kind <> TDocCommentKind(-1) then
          begin
            ParsedDoc:= TDocCommentParser.Dispatch(DocRegion);
            if ParsedDoc.HasContent then FStore.UpsertSymbolDoc(Token, NewSymId, ParsedDoc);
          end;
        end; // for
        // v13 (v0.82): attribute each ref to the innermost routine whose impl
        // body contains its StartLine (0 when in no body). IdxToId is in scope
        // (symbols already inserted with real ids), so this is a pure in-memory
        // resolution -- no DB round-trips.
        for I:= 0 to High(ParseRes.References) do
        begin
          var Ref := ParseRes.References[I];
          Ref.EnclosingSymbolId:= ResolveEnclosingSymbolId(ParseRes.Symbols, IdxToId, Ref.StartLine);
          FStore.UpsertReference(Token, Ref);
        end;
        for I:= 0 to High(ParseRes.DiBindings) do FStore.UpsertDiBinding(Token, ParseRes.DiBindings[I]);
        { v0.40.4: wipe-and-rewrite uses for this file so we never carry
          stale rows. DeleteUnitUsesForFile must run inside the open
          transaction to ensure consistency on rollback. }
        FStore.DeleteUnitUsesForFile(Token.FileId);
        for I:= 0 to High(ParseRes.UsesEntries) do FStore.UpsertUnitUse(Token, ParseRes.UsesEntries[I]);
        // v10: text-content index. Resolve each literal's enclosing symbol by line,
        // then persist. Per-file delete keeps re-index idempotent (FTS cascades via triggers).
        FStore.DeleteStringLiteralsForFile(Token.FileId);
        for I:= 0 to High(ParseRes.Literals) do
        begin
          Lit:= ParseRes.Literals[I];
          Lit.FileId:= Token.FileId;
          Encl:= FStore.FindContainingSymbol(Token.FileId, Lit.StartLine);
          if Encl.Id > 0 then Lit.SymbolId:= Encl.Id;
          FStore.UpsertStringLiteral(Token, Lit);
        end;
        // v(ADP2 T2): index-time analysis facts -- one symbol_facts row per
        // routine-kind symbol that HAS a body (ImplStartLine > 0). Runs last
        // (after refs/di-bindings/uses/literals) but still inside the open
        // file transaction, so a facts-pass failure rolls back atomically
        // with the rest of the file instead of leaving a half-written row.
        // SourceLines is split ONCE per file (on #10 only, matching
        // TDocCommentScanner's own line-counting convention, so 1-based
        // ImplStartLine/ImplEndLine index it correctly) and reused for every
        // symbol -- no per-symbol re-parse, no per-symbol disk re-read.
        // Task 2 writes an EMPTY-but-Present row; Tasks 3-8 fill in each fact
        // field inside TSymbolFactsAnalyzer.Analyze. (ADP2 T4 fix wave: the
        // facts loop below is the one exception to "never touching this call
        // site" -- it now resolves each Sym's real Id/FileId/ParentId in
        // place, just before calling Analyze, so Analyze/AnalyzeReadsWrites no
        // longer re-resolve identity via 3 DB round-trips per routine; no
        // fact-computation logic changed -- see the comment at the mutation
        // site below.) Invalidation is automatic: OpenFileTx (above) already
        // DELETEd this file's OLD symbol rows, and symbol_facts.symbol_id
        // REFERENCES symbols(id) ON DELETE CASCADE with FK enforcement ON
        // (see TSQLiteSymbolStore.Create), so a stale facts row can never
        // outlive its symbol.
        SourceLines:= SourceText.Split([#10]);
        for I:= 0 to High(ParseRes.Symbols) do
        begin
          Sym:= ParseRes.Symbols[I];
          if not (Sym.Kind in [skFunction, skProcedure, skMethod, skConstructor, skDestructor]) then Continue;
          if Sym.ImplStartLine <= 0 then Continue;
          if not IdxToId.TryGetValue(I, NewSymId) then Continue;
          // v(ADP2 T4 fix wave): resolve Sym's real identity BEFORE handing it
          // to Analyze, root-causing the 3-DB-round-trip workaround
          // AnalyzeReadsWrites used to need (see its header comment, unit
          // DRagLint.Doc.SymbolFacts.pas). Sym is a RECORD (value type)
          // freshly reloaded from ParseRes.Symbols[I] two lines up, so
          // mutating it here only affects this local copy passed to Analyze --
          // it never writes back into ParseRes.Symbols and cannot corrupt any
          // other pass (the ref-resolution loop above already finished with
          // ParseRes.Symbols by this point). ParentId is translated from its
          // in-array index using the SAME pattern the symbols loop above uses
          // (IdxToId is fully populated by now, so this is a pure in-memory
          // lookup, never a DB round-trip) -- Tasks 5-8 can trust
          // Sym.Id/.FileId/.ParentId directly, the same way this fix lets T4
          // trust them.
          Sym.Id:= NewSymId;
          Sym.FileId:= Token.FileId;
          if (Sym.ParentId >= 0) and IdxToId.TryGetValue(Integer(Sym.ParentId), ResolvedParent) then Sym.ParentId:= ResolvedParent
          else Sym.ParentId:= -1;
          FactsBody:= SliceBodyLines(SourceLines, Sym.ImplStartLine, Sym.ImplEndLine);
          Facts:= TSymbolFactsAnalyzer.Analyze(Sym, AFilePath, FactsBody, FStore);
          Facts.SymbolId:= NewSymId;
          FStore.PutSymbolFacts(Facts);
        end;
        FStore.CommitFileTx(Token);
        ReportProgress(AFilePath, Length(ParseRes.Symbols), Length(ParseRes.References), Length(ParseRes.Diagnostics));
        for var Diag in ParseRes.Diagnostics do
          Writeln('    DIAG: ' + Diag);
      except
        on E: Exception do
        begin
          FStore.RollbackFileTx(Token);
          Writeln(Format('  ERROR indexing %s: %s', [AFilePath, E.Message]));
        end;
      end; // try
    finally
      // v(ADP2 T3): bound the AST-parse-cache's memory across a large corpus.
      // TSymbolFactsAnalyzer.Analyze (called once per routine, above) reads
      // AFilePath's tree via TAstParseCache.Get, which memoizes per file --
      // the FIRST routine in this file parses it, every later routine in the
      // SAME file reuses the cached tree (one parse per FILE, not per
      // routine). Clearing here, AFTER the facts loop has finished with every
      // routine in ParseRes.Symbols (success or rollback), releases that
      // tree before the walk moves to the next file, so a whole-tree index
      // run never accumulates one tree per file. Safe even on the exception
      // path above: Clear only frees cached trees, it does not touch FStore.
      TAstParseCache.Clear;
      IdxToId.Free;
    end; // try
  finally
    DocRegions.Free;
  end; // try
end; // procedure

// v0.42: SQL files are scanned only when they match the MS*.SQL convention
// (the Micronite Firebird DDL scripts) -- per user, those are the only SQL
// files worth indexing. Every other .sql is skipped so the index isn't
// polluted by ad-hoc query scripts. Non-.sql files always pass this gate.
// v0.45: gate is conditional on FWalkFilter.SqlOnlyMS; when False all SQL pass.
function TIndexer.SqlFileAllowedFilter(const APath: string): Boolean;
var
  Name: string;
begin
  if not SameText(ExtractFileExt(APath), '.sql') then Exit(True);
  if not FWalkFilter.SqlOnlyMS then Exit(True);
  Name:= ExtractFileName(APath);
  Result:= StartsText('MS', Name);
end;

function TIndexer.ShouldPruneDir(const ADir: string): Boolean;
{ v0.42: directory-level pruning -- decided BEFORE we descend, so an excluded
  subtree is never enumerated. This is what makes a full C:\Projects scan
  practical: __history / BACKUP_ALL / .git / node_modules / .scanignore'd and
  already-indexed (--exclude-under) trees are skipped wholesale rather than
  walked and then filtered file-by-file (which took ~8.7h over C:\Projects).
  v0.45: after built-in checks, also prune dirs whose base name matches any
  GlobalExclude or SectionExclude glob from the walk filter. }
const
  PRUNE_NAMES: array[0..5] of string = ( '__history', '__recovery', '.git', '.svn', '.hg', 'node_modules');
var
  Name: string;
  PN  : string;
begin
  Result:= True;
  Name:= LowerCase(ExtractFileName(ExcludeTrailingPathDelimiter(ADir)));
  for PN in PRUNE_NAMES do
    if Name = PN then Exit;
  if Pos('backup', Name) > 0 then Exit; { *BACKUP* folders }
  if IsUnderExcludeRoot(IncludeTrailingPathDelimiter(ADir)) then Exit;
  if TFile.Exists(TPath.Combine(ADir, '.scanignore')) then Exit; { marker file }
  { v0.45: glob-based directory exclusion (uses base name only, case-insensitive).
    Re-use Name (already lower-cased above); TGlob.MatchesAny is case-insensitive. }
  if TGlob.MatchesAny(Name, FWalkFilter.GlobalExclude ) then Exit;
  if TGlob.MatchesAny(Name, FWalkFilter.SectionExclude) then Exit;
  Result:= False;
end;

procedure TIndexer.WalkAndIndex(const ADir: string; ARecursive: Boolean);
{ v0.45: precedence order for filtering:
    1. Built-in dir prunes (ShouldPruneDir -- __history, .git, backup, etc.)
    2. GlobalExclude / SectionExclude globs on dir names (inside ShouldPruneDir)
    3. File-level glob excludes (GlobalExclude + SectionExclude on file base name)
    4. IncludeOnly allow-list on file base name
    5. .gitignore/.hgignore rules via FIgnoreStack (highest precedence)
  PushDir/PopDir symmetry: we ONLY push when we are about to descend
  (i.e. ShouldPruneDir returned False). Pruned dirs are never pushed. }
var
  Files    : TArray<string>;
  SubDirs  : TArray<string>;
  F        : string        ;
  D        : string        ;
  FBaseName: string        ;
  DBaseName: string        ;
begin
  if ShouldPruneDir(ADir) then Exit;

  { v0.45: load ignore files for this directory before listing its contents. }
  if FIgnoreStack <> nil then FIgnoreStack.PushDir(ADir);
  try
    { Files directly in this directory whose extension a parser handles. }
    try
      Files:= TDirectory.GetFiles(ADir, '*', TSearchOption.soTopDirectoryOnly);
    except
      SetLength(Files, 0);
    end;
    for F in Files do
    begin
      if ParserFor(ExtractFileExt(F)) = nil then Continue;
      if not SqlFileAllowedFilter(F) then Continue;
      FBaseName:= ExtractFileName(F);
      { v0.45: GlobalExclude + SectionExclude on file base name. }
      if TGlob.MatchesAny(FBaseName, FWalkFilter.GlobalExclude ) then Continue;
      if TGlob.MatchesAny(FBaseName, FWalkFilter.SectionExclude) then Continue;
      { v0.45: IncludeOnly allow-list -- skip if non-empty and no match. }
      if (Length(FWalkFilter.IncludeOnly) > 0) and (not TGlob.MatchesAny(FBaseName, FWalkFilter.IncludeOnly)) then Continue;
      { v0.45: ignore-file gate (highest precedence). }
      if (FIgnoreStack <> nil) and FIgnoreStack.IsIgnored(F, False) then Continue;
      try
        IndexFile(F);
      except
        on E: Exception do Writeln(Format('  SKIP %s: %s: %s', [F, E.ClassName, E.Message]));
      end;
    end; // for

    if not ARecursive then Exit;

    try
      SubDirs:= TDirectory.GetDirectories(ADir, '*', TSearchOption.soTopDirectoryOnly);
    except
      SetLength(SubDirs, 0);
    end;
    for D in SubDirs do
    begin
      { v0.45: ignore-file gate for dirs (before descending). }
      DBaseName:= ExtractFileName(ExcludeTrailingPathDelimiter(D));
      if (FIgnoreStack <> nil) and FIgnoreStack.IsIgnored(DBaseName, True) then Continue;
      WalkAndIndex(D, True); { ShouldPruneDir gate is applied per subdir }
    end;
  finally
    if FIgnoreStack <> nil then FIgnoreStack.PopDir;
  end; // try
end; // procedure

procedure TIndexer.IndexFolder(const APath: string; ARecursive: Boolean);
begin
  WalkAndIndex(APath, ARecursive);
end;

end.
