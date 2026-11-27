unit DRagLint.CLI.RepoWiki;

{ drag-lint 1.56 -- lane WIKIGEN: `repo gen-wiki` writes the generated concept pages (one page per table, one
  section per field; --per-field: one page per field). The pages come from DRagLint.FieldRepo.WikiGen; this unit
  reads the flags, opens the repository (read only) and the project index (read only), and writes the files.
  Spec: three-place search / caption concepts design, section 2.9 (CC-3). `index` never writes a page.
  DRagLint.CLI.Repo resolves the repository path and dispatches here in ONE line. }

interface

const
  /// <summary>This unit's part of the `repo` sub-verb list in the "use one of" message.</summary>
  /// <remarks>Empty = none; otherwise starts with ', ' (', name').</remarks>
  REPO_WIKI_SUBS = ', gen-wiki';

/// <summary>True for a sub-verb this unit runs.</summary>
/// <param name="pSub">The `repo` sub-verb.</param>
/// <returns>True for gen-wiki.</returns>
function IsRepoWikiSub(const pSub: string): Boolean;

/// <summary>Runs `drag-lint repo gen-wiki`: writes the concept pages of a repository into a folder.</summary>
/// <param name="pSub">The sub-verb, IsRepoWikiSub(pSub) is True.</param>
/// <param name="pPath">The repository file (already resolved from --repo / --project).</param>
/// <param name="pJson">--json: print one JSON object (written, unchanged, stale pages, pages) instead of text.</param>
/// <returns>0 = written or unchanged (also --dry-run); 1 = the repository is not readable or a page cannot be
/// written; 2 = usage (no --out).</returns>
/// <remarks>
/// Flags read from the command line here: --out (or --output) DIR, --per-field, --table T[,T...] (default all),
/// --db FILE (the project index; else _D-RAG\NAME.sqlite beside --project when it exists), --dry-run. Without a
/// project index the pages carry no "Shown in / Edited in / Used by code" sections and one note line says so. A page
/// whose bytes are unchanged is not rewritten. Never deletes: a generated page of a table that left the repository
/// is listed as `stale page: FILE` (not checked when --table narrows the run). Not thread-safe; main thread only.
/// </remarks>
function RunRepoWikiVerb(const pSub, pPath: string; pJson: Boolean): Integer;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Hash,
  System.DateUtils,
  System.Generics.Collections,
  FireDAC.Comp.Client,
  DRagLint.Storage.SQLite,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepo.WikiGen; // dl:unit DRagLint.FieldRepo.WikiGen accepted -- wiki_page_mark is the marker line of a generated page; the verb must recognise exactly what the generator writes

const
  EXIT_OK    = 0;
  EXIT_FAIL  = 1;
  EXIT_USAGE = 2;
  SUB_VERB   = 'gen-wiki';
  PAGE_EXT   = '*.md';
  DRAG_DIR   = '_D-RAG';
  DB_EXT     = '.sqlite';

type
  TWikiRun = record
    Written, Unchanged: Integer;
    Pages: TArray<string>;
    Stale: TArray<string>;
    Refused: TArray<string>; // hand-written pages of a generated name: left untouched
  end;

function IsRepoWikiSub(const pSub: string): Boolean;
begin
  Result := SameText(pSub, SUB_VERB);
end;

function FlagGiven(const pFlag: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if SameText(ParamStr(I), pFlag) then Exit(True);
end;

function FlagValue(const pFlag: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to ParamCount - 1 do
    if SameText(ParamStr(I), pFlag) then Exit(ParamStr(I + 1));
end;

function SplitTables(const pList: string): TArray<string>;
var
  VName: string;
  VOut: TList<string>;
begin
  VOut := TList<string>.Create;
  try
    for VName in pList.Split([',']) do
      if Trim(VName) <> '' then VOut.Add(UpperCase(Trim(VName)));
    Result := VOut.ToArray;
  finally
    VOut.Free;
  end;
end;

{ --db, else the project's own index beside the project file; '' = none. }
function ProjectDbPath: string;
var
  VProject: string;
begin
  Result := FlagValue('--db');
  if Result <> '' then Exit;
  VProject := FlagValue('--project');
  if VProject = '' then Exit;
  Result := TPath.Combine(TPath.Combine(ExtractFilePath(ExpandFileName(VProject)), DRAG_DIR),
    ChangeFileExt(ExtractFileName(VProject), DB_EXT));
  if not FileExists(Result) then Result := '';
end;

function FileSha(const pFile: string): string;
begin
  Result := THashSHA2.GetHashStringFromFile(pFile);
end;

function UnixDate(pUnix: Int64): string;
begin
  Result := FormatDateTime('yyyy-mm-dd hh:nn', UnixToDateTime(pUnix, True)) + ' UTC';
end;

{ Fills the project sections; prints the notes of section 2.9. }
procedure AttachProject(const pRepoPath: string; var pTables: TArray<TWikiTable>);
var
  VDb, VSha: string;
  VStore: TSQLiteSymbolStore;
  VCopiedAt: Int64;
begin
  VDb := ProjectDbPath;
  if (VDb = '') or not FileExists(VDb) then
  begin
    Writeln('note: no project index; pages carry no "shown / edited / used" sections');
    Exit;
  end;
  VStore := TSQLiteSymbolStore.Create(VDb, True);
  try
    if not WikiProjectHasConcepts(VStore.GetConnection) then
    begin
      Writeln('note: no project index; pages carry no "shown / edited / used" sections');
      Exit;
    end;
    if WikiRepoCopyState(VStore.GetConnection, VSha, VCopiedAt) and (VSha <> '')
      and not SameText(VSha, FileSha(pRepoPath)) then
      Writeln('note: the index copy is older than the repository; "where" sections come from the index of ',
        UnixDate(VCopiedAt));
    AttachWikiProject(VStore.GetConnection, pTables);
  finally
    VStore.Free;
  end;
end;

function SameBytes(const pLeft, pRight: TBytes): Boolean;
begin
  Result := (Length(pLeft) = Length(pRight)) and ((Length(pLeft) = 0) or CompareMem(@pLeft[0], @pRight[0], Length(pLeft)));
end;

{ Writes ASCII bytes only when they differ from the file on disk. }
function WriteIfChanged(const pFile, pText: string; pDry: Boolean): Boolean;
var
  VBytes: TBytes;
begin
  VBytes := TEncoding.ASCII.GetBytes(pText);
  Result := not (TFile.Exists(pFile) and SameBytes(TFile.ReadAllBytes(pFile), VBytes));
  if Result and not pDry then TFile.WriteAllBytes(pFile, VBytes);
end;

function IsGeneratedPage(const pFile: string): Boolean;
var
  VReader: TStreamReader;
begin
  VReader := TStreamReader.Create(pFile, TEncoding.ASCII);
  try
    Result := VReader.ReadLine.StartsWith(WIKI_PAGE_MARK);
  finally
    VReader.Free;
  end;
end;

procedure FindStale(const pOut: string; const pPages: TArray<TWikiPage>; var pRun: TWikiRun);
var
  VFile: string;
  VPage: TWikiPage;
  VKnown: Boolean;
begin
  for VFile in TDirectory.GetFiles(pOut, PAGE_EXT) do
  begin
    VKnown := False;
    for VPage in pPages do
      if SameText(VPage.FileName, ExtractFileName(VFile)) then VKnown := True;
    if not VKnown and IsGeneratedPage(VFile) then
      pRun.Stale := pRun.Stale + [ExtractFileName(VFile)];
  end;
  TArray.Sort<string>(pRun.Stale);
end;

function JsonStr(const pText: string): string;
begin
  Result := '"' + pText.Replace('\', '\\').Replace('"', '\"') + '"';
end;

function JsonList(const pItems: TArray<string>): string;
var
  VParts: TArray<string>;
  I: Integer;
begin
  SetLength(VParts, Length(pItems));
  for I := 0 to High(pItems) do VParts[I] := JsonStr(pItems[I]);
  Result := '[' + string.Join(',', VParts) + ']';
end;

procedure Report(const pRun: TWikiRun; pDry, pJson: Boolean);
var
  VFile: string;
begin
  if pJson then
  begin
    Writeln('{"dryRun":', LowerCase(BoolToStr(pDry, True)), ',"written":', pRun.Written, ',"unchanged":', pRun.Unchanged,
      ',"stale":', JsonList(pRun.Stale), ',"refused":', JsonList(pRun.Refused), ',"pages":', JsonList(pRun.Pages), '}');
    Exit;
  end;
  for VFile in pRun.Stale do Writeln('stale page: ', VFile);
  for VFile in pRun.Refused do
    Writeln('refused page: ', VFile, ' (not written: the existing file is not a generated page -- it has no ', WIKI_PAGE_MARK,
      '... first line; move it or choose another --out)');
  Writeln(if pDry then 'dry run: ' else '', pRun.Written, if pDry then ' would be written, ' else ' written, ',
    pRun.Unchanged, ' unchanged');
end;

function Generate(const pRepoPath, pOut: string; pJson: Boolean): Integer;
var
  VConn: TFDConnection;
  VTables: TArray<TWikiTable>;
  VPages: TArray<TWikiPage>;
  VPage: TWikiPage;
  VOnly: TArray<string>;
  VRun: TWikiRun;
  VDry: Boolean;
  VFile: string;
begin
  VDry := FlagGiven('--dry-run');
  VOnly := SplitTables(FlagValue('--table'));
  VConn := OpenRepository(pRepoPath, True);
  try
    VTables := LoadWikiTables(VConn, VOnly);
  finally
    VConn.Free;
  end;
  AttachProject(pRepoPath, VTables);
  VPages := BuildWikiPages(VTables, FlagGiven('--per-field'));
  VRun := Default(TWikiRun);
  if not VDry then TDirectory.CreateDirectory(pOut);
  for VPage in VPages do
  begin
    VRun.Pages := VRun.Pages + [VPage.FileName];
    VFile := TPath.Combine(pOut, VPage.FileName);
    // only a page this verb generated (marker on its first line) is overwritten; a hand-written one survives
    if TFile.Exists(VFile) and not IsGeneratedPage(VFile) then VRun.Refused := VRun.Refused + [VPage.FileName]
    else if WriteIfChanged(VFile, VPage.Text, VDry) then Inc(VRun.Written)
    else Inc(VRun.Unchanged);
  end;
  if (Length(VOnly) = 0) and TDirectory.Exists(pOut) then FindStale(pOut, VPages, VRun);
  Report(VRun, VDry, pJson);
  Result := EXIT_OK;
end;

function RunRepoWikiVerb(const pSub, pPath: string; pJson: Boolean): Integer;
var
  VOut: string;
begin
  VOut := FlagValue('--out');
  if VOut = '' then VOut := FlagValue('--output');
  if VOut = '' then
  begin
    Writeln(ErrOutput, 'repo ', pSub, ': give --out <folder>');
    Exit(EXIT_USAGE);
  end;
  try
    Result := Generate(pPath, ExpandFileName(VOut), pJson);
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, 'repo ', pSub, ': ', E.Message);
      Result := EXIT_FAIL;
    end;
  end;
end;

end.
