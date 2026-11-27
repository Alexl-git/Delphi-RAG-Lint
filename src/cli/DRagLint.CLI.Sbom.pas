unit DRagLint.CLI.Sbom;

{ drag-lint 1.56 -- lane SBOM-1: the `sbom` verb.
  G-49, v1 slice: `sbom --project X.dproj [--out F] [--exe F] [--app-version V] [--db D] [--library-db D]...
  [--catalogue F] [--map F.map] [--bsi [--creator N] [--creator-email A]]` writes a CycloneDX 1.6 JSON document
  (DRagLint.Report.CycloneDx). --map (lane SBOM-2) marks which units of the closure the linker really linked
  (DRagLint.Report.MapFile); --bsi adds the BSI TR-03183-2 fields and names, never invents, what it cannot fill.
  Parses its own flags (like uses-recover and syntax-count): DRagLint.CLI.ParseArgs returns before its flag loop
  for this verb, so the flags, the database resolution and the usage text all live here. The accepted flags are
  in ONE table named SBOM_FLAG_NAMES, so the docs-sync guard (check 9) can read it once INT teaches it this unit.
  DRagLint.CLI.Run dispatches here in one line.

  WHAT IS READ. Every source unit of the project index is in the closure (the index IS the compile closure).
  Each uses row is followed: to a project unit, else to a unit of a library index (and from there
  transitively through that library's own uses rows), else it is a unit without source. A bare name is tried
  with the default unit aliases and then with the project's unit-scope names (DCC_Namespace). Every unit
  also uses System and SysInit, which no uses clause names. Read-only: no index is written.

  WHAT IS NOT READ: no VEX. Without --map the document is the source closure only and says so; with --map it
  still cannot list a DLL or a runtime package, and states that. }

interface

/// <summary>Runs the `sbom` verb from the process command line.</summary>
/// <returns>0 = document written; 1 = failure (an index, the catalogue or the executable cannot be read,
/// the output cannot be written); 2 = usage error or refusal (no --project, no index for it); 3 = unknown flag.</returns>
/// <remarks>Reads ParamStr(2..ParamCount) itself. The document goes to --out, else to stdout; notes and
/// errors go to stderr. Read-only for every index.</remarks>
function RunSbomVerb: Integer;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash, System.DateUtils,
  System.Generics.Collections, System.RegularExpressions, FireDAC.Comp.Client,
  DRagLint.Core.CliError, // dl:unit DRagLint.Core.CliError accepted -- the verb reports an unknown flag with the shared cli_err_unknown_flag text every verb uses; the other CliError consts are other verbs' errors
  DRagLint.Core.Model, // dl:unit DRagLint.Core.Model accepted -- draglint_version is the tool version the SBOM metadata names as its creator; the model unit owns that constant
  DRagLint.Storage.SQLite,
  DRagLint.Storage.Schema, DRagLint.Index.Manifest, DRagLint.CLI.Common, DRagLint.CLI.HelpText,
  DRagLint.CLI.LibraryReady,
  DRagLint.Report.CycloneDx, // dl:unit DRagLint.Report.CycloneDx accepted -- sbom_spec_version / sbom_unknown_supplier are the document-format values the renderer owns; the verb checks and prints the same values
  DRagLint.Report.MapFile;

const
  CVerb = 'sbom';
  CExitOk = 0;
  CExitFail = 1;
  CExitUsage = 2;
  CExitUnknownFlag = 3;
  CFirstArg = 2; // ParamStr(1) is the verb
  CProjectDb = 0; // index of the project index in TSbomRun.FIndexes
  CNoFile = 0; // a NULL target_file_id
  CNoLibrary = 'none';
  CCatalogueFile = 'rules\sbom-libraries.json';
  CJsonIndent = 2;
  CDprojMemberPattern = '<DCCReference\s+Include="([^"]+)"';
  CTimestampFormat = 'yyyy"-"mm"-"dd"T"hh":"nn":"ss"Z"';
  CEmailPattern = '^[^@\s]+@[^@\s]+\.[^@\s]+$';
  CPeMagic: array[0..1] of Byte = (Ord('M'), Ord('Z'));
  CUsage = 'usage: drag-lint sbom --project <x.dproj> [--output <file.cdx.json>] [--exe <delivered.exe>] ' +
    '[--app-version <v>] [--db <project.sqlite>] [--library-db <db>|none]... [--catalogue <file.json>] ' +
    '[--map <file.map>] [--bsi] [--creator <name>] [--creator-email <address>]';
  SQL_FILES = 'select id, path from files';
  SQL_USES = 'select file_id, unit_name, target_file_id from unit_uses order by file_id, start_line, start_col';
  SQL_NAMESPACES = 'select distinct value from project_settings where setting = ''DCC_Namespace'' order by ordinal';
  SQL_FINGERPRINT = 'select value from schema_meta where key = ''indexer_fingerprint'''; // the key is DRagLint.Core.Versions.INDEXER_FINGERPRINT_META_KEY
  /// <summary>The units every Delphi unit uses without naming them.</summary>
  IMPLICIT_UNITS: array[0..1] of string = ('System', 'SysInit');
  /// <summary>File extensions that are units of a closure; every other files row (.inc, .dfm, .hpp) is skipped.</summary>
  UNIT_EXTENSIONS: array[0..3] of string = ('.pas', '.dpr', '.dpk', '.pp');
  /// <summary>Delphi's default project unit-scope list, tried in order when the index stores none.</summary>
  DEFAULT_UNIT_SCOPES: array[0..18] of string = ('Winapi', 'System.Win', 'Data.Win', 'Datasnap.Win',
    'Web.Win', 'Soap.Win', 'Xml.Win', 'Bde', 'System', 'Xml', 'Data', 'Datasnap', 'Web', 'Soap', 'Vcl',
    'Vcl.Imaging', 'Vcl.Touch', 'Vcl.Samples', 'Vcl.Shell');
  /// <summary>The unit aliases the Delphi targets add on Windows (CodeGear.Common.Targets, Studio 37.0), alias then target.</summary>
  DEFAULT_UNIT_ALIASES: array[0..6, 0..1] of string = (
    ('Generics.Collections', 'System.Generics.Collections'), ('Generics.Defaults', 'System.Generics.Defaults'),
    ('WinTypes', 'Winapi.Windows'), ('WinProcs', 'Winapi.Windows'),
    ('DbiTypes', 'BDE'), ('DbiProcs', 'BDE'), ('DbiErrs', 'BDE'));

type
  /// <summary>The flags sbom accepts.</summary>
  TSbomFlag = (sfProject, sfOut, sfExe, sfAppVersion, sfDb, sfLibraryDb, sfCatalogue, sfMap, sfBsi, sfCreator,
    sfCreatorEmail, sfHelp, sfOutputEncoding, sfOutput);

const
  /// <summary>The spelling of each flag: the verb's whole accepted-flag set (docs-sync check 9 reads this table).</summary>
  SBOM_FLAG_NAMES: array[TSbomFlag] of string = ('--project', '--out', '--exe', '--app-version', '--db',
    '--library-db', '--catalogue', '--map', '--bsi', '--creator', '--creator-email', '--help', '--output-encoding', '--output');
  /// <summary>The flags that take the next token as their value.</summary>
  SBOM_VALUE_FLAGS = [sfProject, sfOut, sfExe, sfAppVersion, sfDb, sfLibraryDb, sfCatalogue, sfMap, sfCreator,
    sfCreatorEmail, sfOutputEncoding, sfOutput];

type
  /// <summary>The parsed flags of one sbom run.</summary>
  TSbomOptions = record
    Project   : string;
    OutPath   : string;
    ExePath   : string;
    AppVersion: string;
    DbPath    : string;
    LibraryDbs: TArray<string>;
    NoLibrary : Boolean;
    Catalogue : string;
    MapPath   : string;
    Bsi       : Boolean;
    Creator   : string;
    CreatorEmail: string;
    ShowHelp  : Boolean;
  end;

  /// <summary>One uses row: the name as written and the file it is bound to (CNoFile = unbound).</summary>
  TUseRow = record
    Name  : string;
    Target: Int64;
  end;

  /// <summary>The unit files and uses rows of one index, read once.</summary>
  TSbomIndex = class
  private
    FDbPath     : string;
    FFingerprint: string;
    FPaths      : TDictionary<Int64, string>;
    FNames      : TDictionary<string, Int64>;
    FUseRows    : TObjectDictionary<Int64, TList<TUseRow>>;
    FNamespaces : TArray<string>;
  public
    constructor Create(const pDbPath: string);
    destructor Destroy; override;
    /// <summary>The index file this was read from.</summary>
    property DbPath: string read FDbPath;
    /// <summary>The indexer fingerprint (names the platform), '' when the index stores none.</summary>
    property Fingerprint: string read FFingerprint write FFingerprint;
    /// <summary>Unit file id to full path.</summary>
    property Paths: TDictionary<Int64, string> read FPaths;
    /// <summary>Lower-cased unit name to file id; the first file of a name wins.</summary>
    property Names: TDictionary<string, Int64> read FNames;
    /// <summary>Unit file id to its uses rows, in source order. Owns the lists.</summary>
    property UseRows: TObjectDictionary<Int64, TList<TUseRow>> read FUseRows;
    /// <summary>The project's unit-scope names (DCC_Namespace), in order.</summary>
    property Namespaces: TArray<string> read FNamespaces write FNamespaces;
  end;

  /// <summary>A unit waiting for its uses rows to be followed.</summary>
  TPending = record
    Index : Integer;
    FileId: Int64;
    UnitNo: Integer;
  end;

  /// <summary>The state of one run: the indexes read, and the model being filled.</summary>
  TSbomRun = class
  private
    FOpts      : TSbomOptions;
    FIndexes   : TObjectList<TSbomIndex>;
    FModel     : TSbomModel;
    FKnown     : TDictionary<string, Integer>;
    FQueue     : TQueue<TPending>;
    FScopes    : TArray<string>;
    FProjectDir: string;
    FMembers   : TDictionary<string, Boolean>;
    function IsFirstParty(const pPath: string): Boolean;
    function FileUnit(pIndex: Integer; pFileId: Int64): Integer;
    function SourcelessUnit(const pName: string): Integer;
    function FindByName(pOwnIndex: Integer; const pName: string; out pIndex: Integer; out pFileId: Int64): Boolean;
    function ResolveName(pOwnIndex: Integer; const pName: string): Integer;
    procedure Follow(const pNode: TPending);
    procedure ReadMembers;
  public
    constructor Create(const pOpts: TSbomOptions);
    destructor Destroy; override;
    function LoadIndex(const pDbPath: string; out pError: string): Boolean;
    procedure Walk;
    property Model: TSbomModel read FModel;
    property Indexes: TObjectList<TSbomIndex> read FIndexes;
  end;

constructor TSbomIndex.Create(const pDbPath: string);
begin
  inherited Create;
  FDbPath:= pDbPath;
  FPaths:= TDictionary<Int64, string>.Create;
  FNames:= TDictionary<string, Int64>.Create;
  FUseRows:= TObjectDictionary<Int64, TList<TUseRow>>.Create([doOwnsValues]);
end;

destructor TSbomIndex.Destroy;
begin
  FUseRows.Free;
  FNames.Free;
  FPaths.Free;
  inherited;
end;

function IsUnitPath(const pPath: string): Boolean;
var
  LExt, LKnown: string;
begin
  LExt:= LowerCase(ExtractFileExt(pPath));
  for LKnown in UNIT_EXTENSIONS do
    if LExt = LKnown then
      Exit(True);
  Result:= False;
end;

{ Opens pSql on pQuery, calls pOnRow once per row, and closes the dataset whatever happens. }
procedure ReadRows(const pQuery: TFDQuery; const pSql: string; const pOnRow: TProc);
begin
  pQuery.Open(pSql);
  try
    while not pQuery.Eof do
    begin
      pOnRow();
      pQuery.Next;
    end;
  finally
    pQuery.Close;
  end;
end;

{ The unit files, uses rows, unit-scope names and fingerprint of pQuery's connection, into pIndex. }
procedure ReadIndexRows(const pQuery: TFDQuery; const pIndex: TSbomIndex);
begin
  ReadRows(pQuery, SQL_FILES,
    procedure
    var
      LName: string;
    begin
      if not IsUnitPath(pQuery.Fields[1].AsString) then
        Exit;
      pIndex.Paths.AddOrSetValue(pQuery.Fields[0].AsLargeInt, pQuery.Fields[1].AsString);
      LName:= LowerCase(TPath.GetFileNameWithoutExtension(pQuery.Fields[1].AsString));
      if not pIndex.Names.ContainsKey(LName) then
        pIndex.Names.Add(LName, pQuery.Fields[0].AsLargeInt);
    end);
  ReadRows(pQuery, SQL_USES,
    procedure
    var
      LRow: TUseRow;
      LFileId: Int64;
      LList: TList<TUseRow>;
    begin
      LFileId:= pQuery.Fields[0].AsLargeInt;
      if not pIndex.Paths.ContainsKey(LFileId) then
        Exit;
      if not pIndex.UseRows.TryGetValue(LFileId, LList) then
      begin
        LList:= TList<TUseRow>.Create;
        pIndex.UseRows.Add(LFileId, LList);
      end;
      LRow.Name:= pQuery.Fields[1].AsString;
      LRow.Target:= if pQuery.Fields[2].IsNull then CNoFile else pQuery.Fields[2].AsLargeInt;
      LList.Add(LRow);
    end);
  ReadRows(pQuery, SQL_NAMESPACES,
    procedure
    begin
      pIndex.Namespaces:= pIndex.Namespaces + [pQuery.Fields[0].AsString];
    end);
  ReadRows(pQuery, SQL_FINGERPRINT,
    procedure
    begin
      pIndex.Fingerprint:= pQuery.Fields[0].AsString;
    end);
end;

constructor TSbomRun.Create(const pOpts: TSbomOptions);
begin
  inherited Create;
  FOpts:= pOpts;
  FIndexes:= TObjectList<TSbomIndex>.Create(True);
  FModel:= TSbomModel.Create;
  FKnown:= TDictionary<string, Integer>.Create;
  FQueue:= TQueue<TPending>.Create;
  FMembers:= TDictionary<string, Boolean>.Create;
  FProjectDir:= IncludeTrailingPathDelimiter(ExtractFileDir(pOpts.Project));
end;

destructor TSbomRun.Destroy;
begin
  FMembers.Free;
  FQueue.Free;
  FKnown.Free;
  FModel.Free;
  FIndexes.Free;
  inherited;
end;

function TSbomRun.LoadIndex(const pDbPath: string; out pError: string): Boolean;
var
  LStore: TSQLiteSymbolStore;
  LQuery: TFDQuery;
  LIndex: TSbomIndex;
  LFound, LExpected: Integer;
begin
  pError:= '';
  if not FileExists(pDbPath) then
  begin
    pError:= 'index not found: ' + pDbPath;
    Exit(False);
  end;
  LIndex:= TSbomIndex.Create(pDbPath);
  try
    try
      LStore:= TSQLiteSymbolStore.Create(pDbPath, {AReadOnly=}True);
      try
        LStore.IsSchemaCurrent(LFound, LExpected);
        if not IsSchemaReadable(LFound) then
        begin
          pError:= 'cannot read index ' + pDbPath + ': ' + SchemaUnreadableReason(LFound);
          Exit(False);
        end;
        LQuery:= TFDQuery.Create(nil);
        try
          LQuery.Connection:= LStore.GetConnection;
          ReadIndexRows(LQuery, LIndex);
        finally
          LQuery.Free;
        end;
      finally
        LStore.Free;
      end;
      FIndexes.Add(LIndex);
      LIndex:= nil; { owned by FIndexes now }
      Result:= True;
    except
      on E: Exception do
      begin
        pError:= 'cannot read index ' + pDbPath + ': ' + E.Message;
        Result:= False;
      end;
    end;
  finally
    LIndex.Free;
  end;
end;

{ The files the .dproj lists (DCCReference), as lower-cased full paths: first-party wherever they lie. }
procedure TSbomRun.ReadMembers;
var
  LMatch: TMatch;
begin
  for LMatch in TRegEx.Matches(TFile.ReadAllText(FOpts.Project), CDprojMemberPattern, [roIgnoreCase]) do
    FMembers.AddOrSetValue(LowerCase(ExpandFileName(FProjectDir + LMatch.Groups[1].Value)), True);
end;

function TSbomRun.IsFirstParty(const pPath: string): Boolean;
begin
  Result:= pPath.StartsWith(FProjectDir, True) or FMembers.ContainsKey(LowerCase(pPath));
end;

function TSbomRun.FileUnit(pIndex: Integer; pFileId: Int64): Integer;
var
  LKey, LPath: string;
  LNode: TPending;
begin
  LKey:= Format('%d:%d', [pIndex, pFileId]);
  if FKnown.TryGetValue(LKey, Result) then
    Exit;
  LPath:= FIndexes[pIndex].Paths[pFileId];
  Result:= if pIndex = CProjectDb
    then FModel.AddUnit(TPath.GetFileNameWithoutExtension(LPath), LPath, suoProject, IsFirstParty(LPath))
    else FModel.AddUnit(TPath.GetFileNameWithoutExtension(LPath), LPath, suoLibrary, False);
  FKnown.Add(LKey, Result);
  LNode.Index:= pIndex;
  LNode.FileId:= pFileId;
  LNode.UnitNo:= Result;
  FQueue.Enqueue(LNode);
end;

function TSbomRun.SourcelessUnit(const pName: string): Integer;
var
  LKey: string;
begin
  LKey:= 's:' + LowerCase(pName);
  if not FKnown.TryGetValue(LKey, Result) then
  begin
    Result:= FModel.AddUnit(pName, '', suoSourceless, False);
    FKnown.Add(LKey, Result);
  end;
end;

{ A unit file named pName: in the index that asks first, then in the project index, then in the libraries. }
function TSbomRun.FindByName(pOwnIndex: Integer; const pName: string; out pIndex: Integer;
  out pFileId: Int64): Boolean;
var
  I: Integer;
  LKey: string;
begin
  LKey:= LowerCase(pName);
  pIndex:= pOwnIndex;
  if FIndexes[pOwnIndex].Names.TryGetValue(LKey, pFileId) then
    Exit(True);
  for I:= 0 to FIndexes.Count - 1 do
    if (I <> pOwnIndex) and FIndexes[I].Names.TryGetValue(LKey, pFileId) then
    begin
      pIndex:= I;
      Exit(True);
    end;
  Result:= False;
end;

function TSbomRun.ResolveName(pOwnIndex: Integer; const pName: string): Integer;
var
  I, LIndex: Integer;
  LFileId: Int64;
  LName, LScope: string;
begin
  LName:= pName;
  for I:= Low(DEFAULT_UNIT_ALIASES) to High(DEFAULT_UNIT_ALIASES) do
    if SameText(DEFAULT_UNIT_ALIASES[I, 0], pName) then
      LName:= DEFAULT_UNIT_ALIASES[I, 1];
  if FindByName(pOwnIndex, LName, LIndex, LFileId) then
    Exit(FileUnit(LIndex, LFileId));
  for LScope in FScopes do
    if FindByName(pOwnIndex, LScope + '.' + LName, LIndex, LFileId) then
      Exit(FileUnit(LIndex, LFileId));
  Result:= SourcelessUnit(LName);
end;

procedure TSbomRun.Follow(const pNode: TPending);
var
  LIndex: TSbomIndex;
  LList: TList<TUseRow>;
  LRow: TUseRow;
  LTarget: Integer;
  LImplicit: string;
begin
  LIndex:= FIndexes[pNode.Index];
  if LIndex.UseRows.TryGetValue(pNode.FileId, LList) then
    for LRow in LList do
    begin
      LTarget:= if (LRow.Target <> CNoFile) and LIndex.Paths.ContainsKey(LRow.Target)
        then FileUnit(pNode.Index, LRow.Target)
        else ResolveName(pNode.Index, LRow.Name);
      if LTarget <> pNode.UnitNo then
        FModel.AddEdge(pNode.UnitNo, LTarget);
    end;
  for LImplicit in IMPLICIT_UNITS do
  begin
    LTarget:= ResolveName(pNode.Index, LImplicit);
    if LTarget <> pNode.UnitNo then
      FModel.AddEdge(pNode.UnitNo, LTarget);
  end;
end;

procedure TSbomRun.Walk;
var
  LFileId: Int64;
  LIds: TArray<Int64>;
  LScope: string;
begin
  ReadMembers;
  FScopes:= FIndexes[CProjectDb].Namespaces;
  if Length(FScopes) = 0 then
    for LScope in DEFAULT_UNIT_SCOPES do
      FScopes:= FScopes + [LScope];
  { Every unit file of the project index is in the closure; ascending id = a stable unit order. }
  LIds:= FIndexes[CProjectDb].Paths.Keys.ToArray;
  TArray.Sort<Int64>(LIds);
  for LFileId in LIds do
    FileUnit(CProjectDb, LFileId);
  while FQueue.Count > 0 do
    Follow(FQueue.Dequeue);
end;

{ ---- the verb ---- }

function ParseSbomArgs(const pArgs: TArray<string>; out pOpts: TSbomOptions; out pError, pBadFlag: string): Boolean;
var
  I: Integer;
  LTok, LValue: string;
  LFlag: TSbomFlag;
  LKnown: Boolean;
begin
  pOpts:= Default(TSbomOptions);
  pError:= '';
  pBadFlag:= '';
  I:= 0;
  while I <= High(pArgs) do
  begin
    LTok:= pArgs[I];
    LKnown:= False;
    LFlag:= Low(TSbomFlag);
    for var F:= Low(TSbomFlag) to High(TSbomFlag) do
      if LTok = SBOM_FLAG_NAMES[F] then
      begin
        LFlag:= F;
        LKnown:= True;
      end;
    if (not LKnown) and ((LTok = '-h') or (LTok = '/?')) then
    begin
      LFlag:= sfHelp;
      LKnown:= True;
    end;
    if not LKnown then
    begin
      pBadFlag:= LTok;
      pError:= 'Unknown argument: ' + LTok;
      Exit(False);
    end;
    LValue:= '';
    if LFlag in SBOM_VALUE_FLAGS then
    begin
      if (I + 1 > High(pArgs)) or pArgs[I + 1].StartsWith('--') then
      begin
        pError:= LTok + ' needs a value';
        Exit(False);
      end;
      Inc(I);
      LValue:= pArgs[I];
    end;
    case LFlag of
      sfProject   : pOpts.Project:= ExpandFileName(LValue);
      sfOut, sfOutput: pOpts.OutPath:= ExpandFileName(LValue); { --output is canonical, --out the alias }
      sfExe       : pOpts.ExePath:= ExpandFileName(LValue);
      sfAppVersion: pOpts.AppVersion:= LValue;
      sfDb        : pOpts.DbPath:= ExpandFileName(LValue);
      sfLibraryDb :
        if SameText(LValue, CNoLibrary) then
          pOpts.NoLibrary:= True
        else
          pOpts.LibraryDbs:= pOpts.LibraryDbs + [ExpandFileName(LValue)];
      sfCatalogue : pOpts.Catalogue:= ExpandFileName(LValue);
      sfMap       : pOpts.MapPath:= ExpandFileName(LValue);
      sfBsi       : pOpts.Bsi:= True;
      sfCreator   : pOpts.Creator:= LValue;
      sfCreatorEmail: pOpts.CreatorEmail:= LValue;
      sfHelp      : pOpts.ShowHelp:= True;
      sfOutputEncoding: ; { consumed by Run before the dispatch; accepted so it is not "unknown" }
    end;
    Inc(I);
  end;
  Result:= True;
end;

function Usage(const pWhy: string): Integer;
begin
  Writeln(ErrOutput, CVerb + ': ' + pWhy);
  Writeln(ErrOutput, CUsage);
  Result:= CExitUsage;
end;

function Fail(const pWhy: string): Integer;
begin
  Writeln(ErrOutput, 'ERROR: ' + CVerb + ': ' + pWhy);
  Result:= CExitFail;
end;

function LoadManifest(out pManifest: TIndexManifest): Boolean;
begin
  try
    pManifest:= TManifestIO.Load(ExtractFilePath(ParamStr(0)), GetCurrentDir);
    Result:= True;
  except
    on E: Exception do
    begin
      pManifest:= Default(TIndexManifest);
      Result:= False;
    end;
  end;
end;

{ The project index of pOpts.Project: --db, else the manifest section that owns the project, else the
  _D-RAG default. False (refusal already written) when two sections claim the project. }
function ResolveProjectIndex(var pOpts: TSbomOptions; const pManifest: TIndexManifest): Boolean;
var
  LClaimants: TArray<string>;
begin
  Result:= True;
  if pOpts.DbPath <> '' then
    Exit;
  if ResolveOwnProjectDb(pManifest, pOpts.Project, pOpts.DbPath, LClaimants) = pdmAmbiguous then
  begin
    ReportAmbiguousProject(CVerb, pOpts.Project, LClaimants);
    Result:= False;
  end;
end;

{ The manifest's library index for the platform the project index was built for; '' when there is none. }
function DefaultLibraryDb(const pManifest: TIndexManifest; const pFingerprint, pProjectDb: string): string;
var
  LSource, LPlatform, LListed: string;
  LSection, LLibrary: TIndexSection;
begin
  Result:= '';
  LPlatform:= ChooseLibraryPlatform('', pFingerprint, '', pManifest.Settings.DefaultPlatform, LSource);
  if LPlatform = '' then
    Exit;
  for LSection in pManifest.Sections do
    if SameText(LSection.Source, 'registry-libraries') then
      for LListed in LSection.Platforms do
        if (LListed = '*') or SameText(LListed, LPlatform) then
        begin
          LLibrary:= LSection;
          if LLibrary.Db = '' then
            LLibrary.Db:= LSection.Name + '-{platform}.sqlite';
          Result:= StringReplace(ExpandSectionDb(pManifest, LLibrary), '{platform}', LPlatform,
            [rfReplaceAll, rfIgnoreCase]);
          if SameText(Result, pProjectDb) or not FileExists(Result) then
            Result:= '';
          Exit;
        end;
end;

function WriteDocument(const pText, pOutPath: string): Integer;
var
  LEncoding: TEncoding;
begin
  if pOutPath = '' then
  begin
    Writeln(pText);
    Exit(CExitOk);
  end;
  LEncoding:= TUTF8Encoding.Create(False);
  try
    try
      TFile.WriteAllText(pOutPath, pText + sLineBreak, LEncoding);
      Result:= CExitOk;
    except
      on E: Exception do
        Result:= Fail('cannot write ' + pOutPath + ': ' + E.Message);
    end;
  finally
    LEncoding.Free;
  end;
end;

{ True when the file starts with the PE "MZ" header. }
function HasPeHeader(const pPath: string): Boolean;
var
  LStream: TFileStream;
  LHead: array[0..1] of Byte;
begin
  LStream:= TFileStream.Create(pPath, fmOpenRead or fmShareDenyNone);
  try
    Result:= (LStream.Read(LHead, SizeOf(LHead)) = SizeOf(LHead)) and (LHead[0] = CPeMagic[0]) and (LHead[1] = CPeMagic[1]);
  finally
    LStream.Free;
  end;
end;

{ Reads --map into the model. False (pError set) when the map cannot be used. }
function LoadMap(const pOpts: TSbomOptions; const pModel: TSbomModel; out pError: string): Boolean;
begin
  pError:= '';
  if pOpts.MapPath = '' then
    Exit(True);
  Result:= ReadLinkerMap(pOpts.MapPath, pModel.LinkedUnits, pError);
  if Result then
    pModel.MapFile:= ExtractFileName(pOpts.MapPath);
end;

{ Writes the stderr notes for --map: how many closure units the MAP does not link. }
procedure NoteMap(const pModel: TSbomModel);
var
  LUnit: TSbomUnit;
  LNotLinked, LNotInClosure: Integer;
  LClosure: TStringList;
  LName: string;
begin
  LNotLinked:= 0;
  LNotInClosure:= 0;
  LClosure:= TStringList.Create;
  try
    LClosure.CaseSensitive:= False;
    for LUnit in pModel.Units do
    begin
      LClosure.Add(LUnit.Name);
      if pModel.LinkedUnits.IndexOf(LUnit.Name) < 0 then
        Inc(LNotLinked);
    end;
    for LName in pModel.LinkedUnits do
      if LClosure.IndexOf(LName) < 0 then
        Inc(LNotInClosure);
  finally
    LClosure.Free;
  end;
  Writeln(ErrOutput, Format('NOTE: %s: --map %s: %d of %d unit(s) of the closure are not linked (drag-lint:notLinkedUnit, ' +
    'components kept); %d unit(s) the MAP links are in no indexed source (sbom:mapUnitNotInClosure)',
    [CVerb, pModel.MapFile, LNotLinked, pModel.Units.Count, LNotInClosure]));
end;

{ Writes the stderr note for --bsi: how many fields stayed unfilled, per field name. }
procedure NoteBsi(const pUnfilled: TArray<string>);
var
  LCounts: TStringList;
  LLine, LField, LSummary: string;
  I: Integer;
begin
  LCounts:= TStringList.Create;
  try
    LCounts.Sorted:= True;
    for LLine in pUnfilled do
    begin
      LField:= LLine.Substring(LLine.IndexOf(#9) + 1);
      LField:= LField.Substring(0, LField.IndexOf(':'));
      I:= LCounts.IndexOf(LField);
      if I < 0 then
        LCounts.AddObject(LField, TObject(1))
      else
        LCounts.Objects[I]:= TObject(NativeInt(LCounts.Objects[I]) + 1);
    end;
    LSummary:= '';
    for I:= 0 to LCounts.Count - 1 do
      LSummary:= LSummary + (if LSummary = '' then '' else ', ') + LCounts[I] + ' x' + IntToStr(NativeInt(LCounts.Objects[I]));
  finally
    LCounts.Free;
  end;
  Writeln(ErrOutput, Format('NOTE: %s: BSI TR-03183-2: %d field(s) unfilled, named per component as ' +
    'drag-lint:bsi:unfilled (nothing was invented): %s', [CVerb, Length(pUnfilled), LSummary]));
end;

{ Fills the model's document fields. False (pError set) when --exe cannot be hashed. }
function FillHeader(const pOpts: TSbomOptions; const pModel: TSbomModel; out pError: string): Boolean;
begin
  pError:= '';
  pModel.AppName:= TPath.GetFileNameWithoutExtension(pOpts.Project);
  pModel.AppVersion:= pOpts.AppVersion;
  pModel.Bsi:= pOpts.Bsi;
  pModel.CreatorName:= pOpts.Creator;
  pModel.CreatorEmail:= pOpts.CreatorEmail;
  pModel.ToolVersion:= DRAGLINT_VERSION;
  pModel.Timestamp:= FormatDateTime(CTimestampFormat, TTimeZone.Local.ToUniversalTime(Now));
  pModel.SerialNumber:= 'urn:uuid:' + LowerCase(TGUID.NewGuid.ToString.Trim(['{', '}']));
  if pOpts.ExePath = '' then
    Exit(True);
  if not FileExists(pOpts.ExePath) then
  begin
    pError:= '--exe file not found: ' + pOpts.ExePath;
    Exit(False);
  end;
  try
    pModel.ExeSha512:= LowerCase(THashSHA2.GetHashStringFromFile(pOpts.ExePath, THashSHA2.TSHA2Version.SHA512));
    pModel.ExeName:= ExtractFileName(pOpts.ExePath);
    pModel.ExeIsPe:= HasPeHeader(pOpts.ExePath);
    Result:= True;
  except
    on E: Exception do
    begin
      pError:= 'cannot hash ' + pOpts.ExePath + ': ' + E.Message;
      Result:= False;
    end;
  end;
end;

{ Reads the library indexes: the ones given, else the manifest's for the project's platform. A missing
  or unreadable library index that was GIVEN is a failure; none at all is a NOTE and a narrower document. }
function LoadLibraries(const pRun: TSbomRun; const pOpts: TSbomOptions; const pManifest: TIndexManifest;
  pHasManifest: Boolean; out pError: string): Boolean;
var
  LDbs: TArray<string>;
  LDb, LDefault: string;
begin
  pError:= '';
  LDbs:= pOpts.LibraryDbs;
  if (Length(LDbs) = 0) and (not pOpts.NoLibrary) and pHasManifest then
  begin
    LDefault:= DefaultLibraryDb(pManifest, pRun.Indexes[CProjectDb].Fingerprint, pOpts.DbPath);
    if LDefault <> '' then
      LDbs:= [LDefault];
  end;
  for LDb in LDbs do
    if not pRun.LoadIndex(LDb, pError) then  // dl:ok query-in-loop@ecb4 -- LINTFIX-A: one iteration per --library-db (a handful); each LoadIndex opens a DIFFERENT database, so the schema check cannot be batched
      Exit(False);
  pRun.Model.LibraryIndexUsed:= Length(LDbs) > 0;
  if Length(LDbs) = 0 then
    Writeln(ErrOutput, 'NOTE: ' + CVerb + ': no library index was read: library units are attributed by name ' +
      'only and their own uses are not walked. Pass --library-db <db> for the transitive closure.');
  Result:= True;
end;

{ Why the flags cannot be used before any index is read; '' when they can. }
function OptionsProblem(const pOpts: TSbomOptions): string;
begin
  if not FileExists(pOpts.Project) then
    Result:= 'project file not found: ' + pOpts.Project
  else if (pOpts.CreatorEmail <> '') and not TRegEx.IsMatch(pOpts.CreatorEmail, CEmailPattern) then
    Result:= '--creator-email is not an e-mail address: ' + pOpts.CreatorEmail
  else
    Result:= '';
end;

function Execute(var pOpts: TSbomOptions): Integer;
var
  LRun: TSbomRun;
  LCatalogue: TSbomCatalogue;
  LManifest: TIndexManifest;
  LHasManifest: Boolean;
  LError, LLine: string;
  LUnknown, LUnfilled: TArray<string>;
  LDoc: TJSONObject;
begin
  LError:= OptionsProblem(pOpts);
  if LError <> '' then
    Exit(Usage(LError));
  LHasManifest:= LoadManifest(LManifest);
  if not ResolveProjectIndex(pOpts, LManifest) then
    Exit(CExitUsage);
  if not FileExists(pOpts.DbPath) then
    Exit(Usage('no index for this project: ' + pOpts.DbPath + ' -- run: drag-lint index --project ' +
      pOpts.Project + ', or pass --db'));
  if pOpts.Catalogue = '' then
    pOpts.Catalogue:= ExtractFilePath(ParamStr(0)) + CCatalogueFile;
  LCatalogue:= TSbomCatalogue.Create;
  LRun:= TSbomRun.Create(pOpts);
  try
    if not LCatalogue.LoadFromFile(pOpts.Catalogue, LError) then
      Exit(Fail(LError + ' (pass --catalogue <file.json>)'));
    if not (LRun.LoadIndex(pOpts.DbPath, LError) and LoadLibraries(LRun, pOpts, LManifest, LHasManifest, LError)
      and FillHeader(pOpts, LRun.Model, LError) and LoadMap(pOpts, LRun.Model, LError)) then
      Exit(Fail(LError));
    LRun.Walk;
    LDoc:= BuildCycloneDx(LRun.Model, LCatalogue, LUnknown, LUnfilled);
    try
      Result:= WriteDocument(LDoc.Format(CJsonIndent), pOpts.OutPath);
    finally
      LDoc.Free;
    end;
    if pOpts.MapPath <> '' then
      NoteMap(LRun.Model);
    if pOpts.Bsi then
      NoteBsi(LUnfilled);
    for LLine in LUnknown do
      Writeln(ErrOutput, 'NOTE: ' + CVerb + ': no catalogue row (listed as "' + SBOM_UNKNOWN_SUPPLIER + '"): ' +
        LLine.Replace(#9, '  '));
    if (Result = CExitOk) and (pOpts.OutPath <> '') then
      Writeln(Format('%s: CycloneDX %s written to %s -- %d unit(s), %d without a catalogue row', [CVerb,
        SBOM_SPEC_VERSION, pOpts.OutPath, LRun.Model.Units.Count, Length(LUnknown)]));
  finally
    LRun.Free;
    LCatalogue.Free;
  end;
end;

function RunSbomVerb: Integer;
var
  LArgs: TArray<string>;
  LOpts: TSbomOptions;
  LError, LBadFlag: string;
  I: Integer;
begin
  LArgs:= nil;
  for I:= CFirstArg to ParamCount do
    LArgs:= LArgs + [ParamStr(I)];
  if not ParseSbomArgs(LArgs, LOpts, LError, LBadFlag) then
  begin
    if LBadFlag <> '' then
    begin
      WriteCliError(CLI_ERR_UNKNOWN_FLAG, LError, CommandLineWantsJson, 'flag', LBadFlag);
      Result:= CExitUnknownFlag;
    end
    else
      Result:= Usage(LError);
  end
  else if LOpts.ShowHelp then
  begin
    WriteVerbHelp(CVerb);
    Result:= CExitOk;
  end
  else
    Result:= if LOpts.Project = '' then Usage('give --project <x.dproj>') else Execute(LOpts);
end;

end.
