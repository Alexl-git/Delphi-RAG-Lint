unit DRagLint.Core.Indexer;

interface

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.IOUtils,
  System.Hash,
  System.DateUtils,
  System.Generics.Collections,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces,
  DRagLint.Index.Glob,
  DRagLint.Index.IgnoreFiles,
  DRagLint.Parser.DocComments;

type
  TIndexer = class(TInterfacedObject, IIndexer)
  strict private
    FStore: ISymbolStore;
    FParsers: TList<IParser>;
    FSkippedUpToDate: Integer;
    FDocConfig: TDocConfig;
    FExcludeRoots: TList<string>;   { v0.42: normalized lowercase, trailing-sep }
    FWalkFilter: TWalkFilter;       { v0.45: glob/ignore filtering }
    FIgnoreStack: TIgnoreStack;     { v0.45: .gitignore/.hgignore stack; nil when not UseIgnoreFiles }
    function ParserFor(const AExtension: string): IParser;
    procedure ReportProgress(const APath: string; ASymbols, ARefs, AErrors: Integer);
    function IsUnderExcludeRoot(const APath: string): Boolean;
    function ShouldPruneDir(const ADir: string): Boolean;
    function SqlFileAllowedFilter(const APath: string): Boolean;
    procedure WalkAndIndex(const ADir: string; ARecursive: Boolean);
  public
    constructor Create(const AStore: ISymbolStore;
      const AParsers: TArray<IParser>;
      const ADocConfig: TDocConfig); overload;
    constructor Create(const AStore: ISymbolStore;
      const AParsers: TArray<IParser>); overload;
    destructor Destroy; override;
    procedure IndexFolder(const APath: string;
      ARecursive: Boolean = True);
    procedure IndexFile(const AFilePath: string);
    function SkippedUpToDate: Integer;
    procedure AddExcludeRoot(const APath: string);
    procedure SetWalkFilter(const AFilter: TWalkFilter);
  end;

implementation

constructor TIndexer.Create(const AStore: ISymbolStore;
  const AParsers: TArray<IParser>;
  const ADocConfig: TDocConfig);
var
  P: IParser;
begin
  inherited Create;
  FStore := AStore;
  FDocConfig := ADocConfig;
  FParsers := TList<IParser>.Create;
  FExcludeRoots := TList<string>.Create;
  FIgnoreStack := nil;
  { v0.45: default filter preserves prior behaviour -- only MS*.SQL indexed. }
  FWalkFilter := TWalkFilter.Create;
  for P in AParsers do
    FParsers.Add(P);
end;

constructor TIndexer.Create(const AStore: ISymbolStore;
  const AParsers: TArray<IParser>);
begin
  Create(AStore, AParsers, DefaultDocConfig);
end;

destructor TIndexer.Destroy;
begin
  FParsers.Free;
  FExcludeRoots.Free;
  FIgnoreStack.Free;
  FStore := nil;
  inherited;
end;

function TIndexer.SkippedUpToDate: Integer;
begin
  Result := FSkippedUpToDate;
end;

procedure TIndexer.AddExcludeRoot(const APath: string);
var
  Norm: string;
begin
  if APath = '' then Exit;
  Norm := LowerCase(IncludeTrailingPathDelimiter(
    ExcludeTrailingPathDelimiter(APath)));
  if not FExcludeRoots.Contains(Norm) then
    FExcludeRoots.Add(Norm);
end;

function TIndexer.IsUnderExcludeRoot(const APath: string): Boolean;
var
  L, Root: string;
begin
  Result := False;
  if FExcludeRoots.Count = 0 then Exit;
  L := LowerCase(APath);
  for Root in FExcludeRoots do
    if StartsStr(Root, L) then Exit(True);
end;

procedure TIndexer.SetWalkFilter(const AFilter: TWalkFilter);
begin
  FWalkFilter := AFilter;
  { (Re)create the ignore stack when UseIgnoreFiles is toggled. }
  FreeAndNil(FIgnoreStack);
  if FWalkFilter.UseIgnoreFiles then
    FIgnoreStack := TIgnoreStack.Create;
end;

function TIndexer.ParserFor(const AExtension: string): IParser;
var
  P: IParser;
  E: string;
  Lower: string;
begin
  Lower := LowerCase(AExtension);
  for P in FParsers do
    for E in P.FileExtensions do
      if SameText(E, Lower) then
        Exit(P);
  Result := nil;
end;

procedure TIndexer.ReportProgress(const APath: string;
  ASymbols, ARefs, AErrors: Integer);
begin
  Writeln(Format('  %s -> %d symbols, %d refs, %d errors',
    [APath, ASymbols, ARefs, AErrors]));
end;

// Returns the TDocCommentRegion immediately preceding ASymStartLine
// (EndLine in [SymStartLine - 1 - AllowGap, SymStartLine - 1]).
// When ACaptureLoose is False, regions with Kind in [dckLooseLine, dckLooseBlock]
// are skipped entirely.
// Sentinel: Result.Kind = TDocCommentKind(-1) means no region found.
function FindDocRegionAbove(ADocRegions: TList<TDocCommentRegion>;
  ASymStartLine: Integer; AAllowGap: Integer;
  ACaptureLoose: Boolean): TDocCommentRegion;
var
  I: Integer;
  Best: TDocCommentRegion;
  HasBest: Boolean;
begin
  HasBest := False;
  // ADocRegions is sorted by StartLine ascending.
  for I := 0 to ADocRegions.Count - 1 do
  begin
    // Skip loose regions when captureLooseComments is disabled.
    if (not ACaptureLoose) and
       (ADocRegions[I].Kind in [dckLooseLine, dckLooseBlock]) then
      Continue;
    if (ADocRegions[I].EndLine >= ASymStartLine - 1 - AAllowGap) and
       (ADocRegions[I].EndLine <= ASymStartLine - 1) then
    begin
      Best := ADocRegions[I];
      HasBest := True;
    end;
    if ADocRegions[I].StartLine > ASymStartLine then
      Break;
  end;
  if HasBest then
    Result := Best
  else
  begin
    FillChar(Result, SizeOf(Result), 0);
    Result.Kind := TDocCommentKind(-1);
  end;
end;

procedure TIndexer.IndexFile(const AFilePath: string);
var
  Parser: IParser;
  Source: TBytes;
  SourceText: string;
  Sha: string;
  Mtime: Int64;
  ParseRes: TParseResult;
  Token: TFileTxToken;
  Sym: TSymbol;
  IdxToId: TDictionary<Integer, Int64>;
  i: Integer;
  ResolvedParent: Int64;
  NewSymId: Int64;
  DocRegions: TList<TDocCommentRegion>;
  DocRegion: TDocCommentRegion;
  ParsedDoc: TParsedDoc;
begin
  Parser := ParserFor(ExtractFileExt(AFilePath));
  if Parser = nil then
    Exit;
  { v0.46: file-size guard -- skip files that would overflow the tree-sitter
    native stack. The segfault is not catchable by Delphi (it is a native
    stack overflow, not an OS exception the RTL wraps). Default: 2048 KB.
    0 = unlimited (caller explicitly opted out). }
  if FWalkFilter.MaxFileKB > 0 then
  begin
    var FileSize: Int64;
    try
      FileSize := TFile.GetSize(AFilePath);
    except
      FileSize := 0;
    end;
    if FileSize > Int64(FWalkFilter.MaxFileKB) * 1024 then
    begin
      Writeln(Format('  SKIP %s: %d KB exceeds parse limit (%d KB)',
        [AFilePath, FileSize div 1024, FWalkFilter.MaxFileKB]));
      Exit;
    end;
  end;
  Source := TFile.ReadAllBytes(AFilePath);
  Sha := THashSHA2.GetHashString(TEncoding.ANSI.GetString(Source));
  Mtime := DateTimeToUnix(TFile.GetLastWriteTime(AFilePath), False);
  // v0.4: incremental skip. If the file's already in the DB with the same
  // mtime and sha256, nothing to do - the parser would emit the same
  // symbols. Saves a parse + the per-file transaction.
  if FStore.FileIsUpToDate(AFilePath, Mtime, Sha) then
  begin
    Inc(FSkippedUpToDate);
    Exit;
  end;
  ParseRes := Parser.Parse(Source, AFilePath);
  // v0.16: scan doc-comment regions from the source text once per file
  // so we can associate them with symbols by line proximity below.
  SourceText := TEncoding.ANSI.GetString(Source);
  DocRegions := TDocCommentScanner.Scan(SourceText);
  try
    Token := FStore.OpenFileTx(AFilePath, Mtime, Sha, Parser.LanguageName);
    // v0.16: clear stale doc rows for this file before emitting fresh ones
    // (OpenFileTx already cleared symbols and refs).
    FStore.DeleteFileDocs(Token.FileId);
    IdxToId := TDictionary<Integer, Int64>.Create;
    try
      try
        for i := 0 to High(ParseRes.Symbols) do
        begin
          Sym := ParseRes.Symbols[i];
          // Translate in-array parent index to actual DB id
          if (Sym.ParentId >= 0) and IdxToId.TryGetValue(Integer(Sym.ParentId),
            ResolvedParent) then
            Sym.ParentId := ResolvedParent
          else
            Sym.ParentId := -1;
          NewSymId := FStore.UpsertSymbol(Token, Sym);
          IdxToId.Add(i, NewSymId);
          // v0.16: associate doc comment region to this symbol.
          // Task 13: AllowBlankLineGap and CaptureLooseComments come from
          // .drag-lint.json "docs" section via FDocConfig.
          DocRegion := FindDocRegionAbove(DocRegions, Sym.StartLine,
            FDocConfig.AllowBlankLineGap, FDocConfig.CaptureLooseComments);
          if DocRegion.Kind <> TDocCommentKind(-1) then
          begin
            ParsedDoc := TDocCommentParser.Dispatch(DocRegion);
            if ParsedDoc.HasContent then
              FStore.UpsertSymbolDoc(Token, NewSymId, ParsedDoc);
          end;
        end;
        for i := 0 to High(ParseRes.References) do
          FStore.UpsertReference(Token, ParseRes.References[i]);
        { v0.40.4: wipe-and-rewrite uses for this file so we never carry
          stale rows. DeleteUnitUsesForFile must run inside the open
          transaction to ensure consistency on rollback. }
        FStore.DeleteUnitUsesForFile(Token.FileId);
        for i := 0 to High(ParseRes.UsesEntries) do
          FStore.UpsertUnitUse(Token, ParseRes.UsesEntries[i]);
        FStore.CommitFileTx(Token);
        ReportProgress(AFilePath, Length(ParseRes.Symbols),
          Length(ParseRes.References),
          Length(ParseRes.Diagnostics));
      except
        on E: Exception do
        begin
          FStore.RollbackFileTx(Token);
          Writeln(Format('  ERROR indexing %s: %s', [AFilePath, E.Message]));
        end;
      end;
    finally
      IdxToId.Free;
    end;
  finally
    DocRegions.Free;
  end;
end;

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
  Name := ExtractFileName(APath);
  Result := StartsText('MS', Name);
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
  PRUNE_NAMES: array[0..5] of string = (
    '__history', '__recovery', '.git', '.svn', '.hg', 'node_modules');
var
  Name, PN: string;
begin
  Result := True;
  Name := LowerCase(ExtractFileName(ExcludeTrailingPathDelimiter(ADir)));
  for PN in PRUNE_NAMES do
    if Name = PN then Exit;
  if Pos('backup', Name) > 0 then Exit;                    { *BACKUP* folders }
  if IsUnderExcludeRoot(IncludeTrailingPathDelimiter(ADir)) then Exit;
  if TFile.Exists(TPath.Combine(ADir, '.scanignore')) then Exit;  { marker file }
  { v0.45: glob-based directory exclusion (uses base name only, case-insensitive).
    Re-use Name (already lower-cased above); TGlob.MatchesAny is case-insensitive. }
  if TGlob.MatchesAny(Name, FWalkFilter.GlobalExclude) then Exit;
  if TGlob.MatchesAny(Name, FWalkFilter.SectionExclude) then Exit;
  Result := False;
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
  Files, SubDirs: TArray<string>;
  F, D:      string;
  FBaseName: string;
  DBaseName: string;
begin
  if ShouldPruneDir(ADir) then Exit;

  { v0.45: load ignore files for this directory before listing its contents. }
  if FIgnoreStack <> nil then
    FIgnoreStack.PushDir(ADir);
  try
    { Files directly in this directory whose extension a parser handles. }
    try
      Files := TDirectory.GetFiles(ADir, '*', TSearchOption.soTopDirectoryOnly);
    except
      SetLength(Files, 0);
    end;
    for F in Files do
    begin
      if ParserFor(ExtractFileExt(F)) = nil then Continue;
      if not SqlFileAllowedFilter(F) then Continue;
      FBaseName := ExtractFileName(F);
      { v0.45: GlobalExclude + SectionExclude on file base name. }
      if TGlob.MatchesAny(FBaseName, FWalkFilter.GlobalExclude) then Continue;
      if TGlob.MatchesAny(FBaseName, FWalkFilter.SectionExclude) then Continue;
      { v0.45: IncludeOnly allow-list -- skip if non-empty and no match. }
      if (Length(FWalkFilter.IncludeOnly) > 0) and
         (not TGlob.MatchesAny(FBaseName, FWalkFilter.IncludeOnly)) then Continue;
      { v0.45: ignore-file gate (highest precedence). }
      if (FIgnoreStack <> nil) and FIgnoreStack.IsIgnored(F, False) then Continue;
      try
        IndexFile(F);
      except
        on E: Exception do
          Writeln(Format('  SKIP %s: %s: %s', [F, E.ClassName, E.Message]));
      end;
    end;

    if not ARecursive then Exit;

    try
      SubDirs := TDirectory.GetDirectories(ADir, '*', TSearchOption.soTopDirectoryOnly);
    except
      SetLength(SubDirs, 0);
    end;
    for D in SubDirs do
    begin
      { v0.45: ignore-file gate for dirs (before descending). }
      DBaseName := ExtractFileName(ExcludeTrailingPathDelimiter(D));
      if (FIgnoreStack <> nil) and FIgnoreStack.IsIgnored(DBaseName, True) then Continue;
      WalkAndIndex(D, True);      { ShouldPruneDir gate is applied per subdir }
    end;
  finally
    if FIgnoreStack <> nil then
      FIgnoreStack.PopDir;
  end;
end;

procedure TIndexer.IndexFolder(const APath: string; ARecursive: Boolean);
begin
  WalkAndIndex(APath, ARecursive);
end;

end.
