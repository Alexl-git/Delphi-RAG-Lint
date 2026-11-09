unit DRagLint.CLI.UsesRecover;

{ Lane 148-HP: the `uses-recover` verb (spec docs\superpowers\specs\2026-11-08-uses-recover.md).
  Recovers the uses edges of units that have NO source in an index, from the C++Builder .hpp
  headers a vendor ships and, optionally, a dcc map file. Owner ruling x2: no .dcu is read.
  Parses its own flags (like syntax-count): the CLI dispatches here before ParseArgs, so the
  verb adds no field to TArgs. Every DB is opened READ-ONLY; nothing is written. }

interface

/// <summary>Runs `drag-lint uses-recover` from the process command line (ParamStr(2) onwards).</summary>
/// <returns>0 = report printed (zero sourceless units included); 2 = no --db or no --hpp-dir, or a
/// DB, header directory or map that is missing or unreadable; 3 = an unknown flag
/// (error[unknown-flag] on stderr).</returns>
/// <remarks>
/// A unit is sourceless when a unit_uses row of --db names it and no .pas/.dpr/.dpk of --db or of
/// any --library-db has its name (file base name, case-insensitive; Delphi's default unit scopes
/// are tried for a bare name). Its header's #include lines are its interface uses; sourceless
/// targets with a header are followed breadth-first. --map adds in_map per unit and map_only (the
/// linked units no header reaches). Not thread-safe; writes stdout / stderr only.
/// </remarks>
function RunUsesRecoverVerb: Integer;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Generics.Collections,
  System.Generics.Defaults, System.RegularExpressions, FireDAC.Comp.Client,
  DRagLint.Core.CliError, DRagLint.Storage.SQLite, DRagLint.CLI.HelpText;

const
  CVerb = 'uses-recover';
  CExitOk = 0;
  CExitUsage = 2;
  CExitUnknownFlag = 3;
  CFirstArg = 2; // ParamStr(1) is the verb
  CStatusIndexed = 'indexed';
  CStatusLibrary = 'library';
  CStatusSourceless = 'sourceless';
  CReachDirect = 'direct';
  CReachHeader = 'header';
  CHppMask = '*.hpp';
  /// <summary>Delphi's default project unit-scope list, tried in order for a bare unit name.</summary>
  DEFAULT_UNIT_SCOPES: array[0..18] of string = ('Winapi', 'System.Win', 'Data.Win', 'Datasnap.Win',
    'Web.Win', 'Soap.Win', 'Xml.Win', 'Bde', 'System', 'Xml', 'Data', 'Datasnap', 'Web', 'Soap', 'Vcl',
    'Vcl.Imaging', 'Vcl.Touch', 'Vcl.Samples', 'Vcl.Shell');

type
  /// <summary>The flags uses-recover accepts.</summary>
  TUsesRecoverFlag = (urfDb, urfHppDir, urfLibraryDb, urfMap, urfJson, urfHelp, urfOutputEncoding);

const
  /// <summary>The spelling of each flag. tests\autotest\run_docs_sync_guard.ps1 reads this
  /// table as the verb's accepted-flag set (as it reads SYNTAX_COUNT_FLAG_NAMES): rename it there too.</summary>
  USES_RECOVER_FLAG_NAMES: array[TUsesRecoverFlag] of string = ('--db', '--hpp-dir', '--library-db',
    '--map', '--json', '--help', '--output-encoding');
  /// <summary>The flags that take the next token as their value.</summary>
  USES_RECOVER_VALUE_FLAGS = [urfDb, urfHppDir, urfLibraryDb, urfMap, urfOutputEncoding];

type
  /// <summary>The parsed flags of one uses-recover run.</summary>
  TUsesRecoverOptions = record
    DbPath    : string;
    HppDirs   : TArray<string>;
    LibraryDbs: TArray<string>;
    MapPath   : string;
    AsJson    : Boolean;
    ShowHelp  : Boolean;
  end;

  /// <summary>One recovered edge: a unit a header includes, and what the indexes know of it.</summary>
  TRecoveredEdge = record
    UnitName: string;
    Status  : string;
  end;

  /// <summary>One sourceless unit of the report. Owned by TUsesRecoverRun.Units.</summary>
  TRecoveredUnit = class
  private
    FName  : string;
    FReach : string;
    FHeader: string;
    FUsedBy: TList<string>;
    FEdges : TList<TRecoveredEdge>;
  public
    constructor Create(const pName, pReach, pHeader: string);
    destructor Destroy; override;
    procedure AddUser(const pUser: string);
    property Name: string read FName;
    property Reach: string read FReach;
    property Header: string read FHeader;
    property UsedBy: TList<string> read FUsedBy;
    property Edges: TList<TRecoveredEdge> read FEdges;
  end;

  /// <summary>The state of one run: name sets read from the DBs, the header index, the result.</summary>
  TUsesRecoverRun = class
  private
    FIndexed : TDictionary<string, Boolean>;
    FLibrary : TDictionary<string, Boolean>;
    FHeaders : TDictionary<string, string>;
    FMap     : TDictionary<string, Boolean>;
    FMapOrder: TArray<string>;
    FSeen    : TDictionary<string, TRecoveredUnit>;
    FOpts    : TUsesRecoverOptions;
    FHasMap  : Boolean;
    FUnits   : TObjectList<TRecoveredUnit>;
    FNoHeader: TObjectList<TRecoveredUnit>;
    FMapOnly : TArray<string>;
    function InSet(const pSet: TDictionary<string, Boolean>; const pName: string): Boolean;
    function Classify(const pName: string): string;
    function FindHeader(const pName: string; out pCanonical: string): string;
  public
    constructor Create(const pOpts: TUsesRecoverOptions);
    destructor Destroy; override;
    function Load(out pError: string): Boolean;
    procedure Recover(const pDirect: TDictionary<string, TList<string>>);
    function InMap(const pName: string): Boolean;
    function HeaderCount: Integer;
    property Opts: TUsesRecoverOptions read FOpts;
    property HasMap: Boolean read FHasMap;
    property Units: TObjectList<TRecoveredUnit> read FUnits;
    property NoHeader: TObjectList<TRecoveredUnit> read FNoHeader;
    property MapOnly: TArray<string> read FMapOnly;
  end;

/// <summary>The unit names a C++Builder header includes, in file order.</summary>
/// <param name="pText">The whole .hpp text.</param>
/// <returns>One name per `#include &lt;X.hpp&gt;` or `#include "X.hpp"` line (X as written);
/// other includes are skipped. No #if evaluation.</returns>
function ParseHppIncludes(const pText: string): TArray<string>;
var
  LMatch: TMatch;
begin
  Result:= nil;
  for LMatch in TRegEx.Matches(pText, '^[ \t]*#include[ \t]*[<"]([^<>"]+)\.hpp[>"]',
    [roMultiLine, roIgnoreCase]) do
    Result:= Result + [LMatch.Groups[1].Value];
end;

/// <summary>The unit names of a dcc map file's segment rows, first occurrence order, no repeats.</summary>
/// <param name="pText">The whole .map text (-GS or -GD).</param>
/// <returns>Every distinct `M=&lt;unit&gt;` value. A unit with no code or data segment has none.</returns>
function ParseMapUnits(const pText: string): TArray<string>;
var
  LMatch: TMatch;
  LSeen: TDictionary<string, Boolean>;
  LName: string;
begin
  Result:= nil;
  LSeen:= TDictionary<string, Boolean>.Create;
  try
    for LMatch in TRegEx.Matches(pText, '\sM=(\S+)') do
    begin
      LName:= LMatch.Groups[1].Value;
      if not LSeen.ContainsKey(LowerCase(LName)) then
      begin
        LSeen.Add(LowerCase(LName), True);
        Result:= Result + [LName];
      end;
    end;
  finally
    LSeen.Free;
  end;
end;

function IsImplicitUnit(const pName: string): Boolean;
begin
  Result:= SameText(pName, 'System') or SameText(pName, 'SysInit');
end;

function IsSourcePath(const pPath: string): Boolean;
var
  LExt: string;
begin
  LExt:= LowerCase(ExtractFileExt(pPath));
  Result:= (LExt = '.pas') or (LExt = '.dpr') or (LExt = '.dpk');
end;

{ TRecoveredUnit }

constructor TRecoveredUnit.Create(const pName, pReach, pHeader: string);
begin
  inherited Create;
  FName:= pName;
  FReach:= pReach;
  FHeader:= pHeader;
  FUsedBy:= TList<string>.Create;
  FEdges:= TList<TRecoveredEdge>.Create;
end;

destructor TRecoveredUnit.Destroy;
begin
  FEdges.Free;
  FUsedBy.Free;
  inherited Destroy;
end;

procedure TRecoveredUnit.AddUser(const pUser: string);
begin
  if not UsedBy.Contains(pUser) then
    UsedBy.Add(pUser);
end;

{ TUsesRecoverRun }

constructor TUsesRecoverRun.Create(const pOpts: TUsesRecoverOptions);
begin
  inherited Create;
  FOpts:= pOpts;
  FIndexed:= TDictionary<string, Boolean>.Create;
  FLibrary:= TDictionary<string, Boolean>.Create;
  FHeaders:= TDictionary<string, string>.Create;
  FMap:= TDictionary<string, Boolean>.Create;
  FSeen:= TDictionary<string, TRecoveredUnit>.Create;
  FUnits:= TObjectList<TRecoveredUnit>.Create(True);
  FNoHeader:= TObjectList<TRecoveredUnit>.Create(True);
end;

destructor TUsesRecoverRun.Destroy;
begin
  FNoHeader.Free;
  FUnits.Free;
  FSeen.Free;
  FMap.Free;
  FHeaders.Free;
  FLibrary.Free;
  FIndexed.Free;
  inherited Destroy;
end;

function TUsesRecoverRun.InSet(const pSet: TDictionary<string, Boolean>; const pName: string): Boolean;
var
  LScope: string;
begin
  Result:= pSet.ContainsKey(LowerCase(pName));
  if not Result then
    for LScope in DEFAULT_UNIT_SCOPES do
      if pSet.ContainsKey(LowerCase(LScope + '.' + pName)) then
        Exit(True);
end;

function TUsesRecoverRun.Classify(const pName: string): string;
begin
  Result:= if InSet(FIndexed, pName) then CStatusIndexed
    else if InSet(FLibrary, pName) then CStatusLibrary
    else CStatusSourceless;
end;

function TUsesRecoverRun.FindHeader(const pName: string; out pCanonical: string): string;
var
  LScope: string;
begin
  pCanonical:= pName;
  if FHeaders.TryGetValue(LowerCase(pName), Result) then
  begin
    pCanonical:= TPath.GetFileNameWithoutExtension(Result);
    Exit;
  end;
  for LScope in DEFAULT_UNIT_SCOPES do
    if FHeaders.TryGetValue(LowerCase(LScope + '.' + pName), Result) then
    begin
      pCanonical:= TPath.GetFileNameWithoutExtension(Result);
      Exit;
    end;
  Result:= '';
end;

function TUsesRecoverRun.InMap(const pName: string): Boolean;
begin
  Result:= InSet(FMap, pName);
end;

function TUsesRecoverRun.HeaderCount: Integer;
begin
  Result:= FHeaders.Count;
end;

const
  SQL_SOURCE_FILES = 'select path from files';
  SQL_UNRESOLVED_USES = 'select u.unit_name, f.path from unit_uses u join files f on f.id = u.file_id where u.target_file_id is null';

{ The lower-cased base name of every .pas/.dpr/.dpk row of pQuery's connection, into pSet. }
procedure ReadSourceNames(const pQuery: TFDQuery; const pSet: TDictionary<string, Boolean>);
begin
  pQuery.Open(SQL_SOURCE_FILES);
  try
    while not pQuery.Eof do
    begin
      if IsSourcePath(pQuery.Fields[0].AsString) then
        pSet.AddOrSetValue(LowerCase(TPath.GetFileNameWithoutExtension(pQuery.Fields[0].AsString)), True);
      pQuery.Next;
    end;
  finally
    pQuery.Close;
  end;
end;

{ Every unit_uses name with no target file, mapped to the distinct file names that use it.
  pDirect owns the lists it is given. }
procedure ReadUnresolvedUses(const pQuery: TFDQuery; const pDirect: TDictionary<string, TList<string>>);
var
  LKey, LUser: string;
  LUsers: TList<string>;
begin
  pQuery.Open(SQL_UNRESOLVED_USES);
  try
    while not pQuery.Eof do
    begin
      LKey:= pQuery.Fields[0].AsString;
      LUser:= ExtractFileName(pQuery.Fields[1].AsString);
      if not pDirect.TryGetValue(LKey, LUsers) then
      begin
        LUsers:= TList<string>.Create;
        pDirect.Add(LKey, LUsers);
      end;
      if not LUsers.Contains(LUser) then
        LUsers.Add(LUser);
      pQuery.Next;
    end;
  finally
    pQuery.Close;
  end;
end;

{ The base names of every source file of one index, into pSet, and (when pDirect is assigned)
  its unresolved uses. Read-only open; False with pError set on any failure. }
function LoadSourceNames(const pDbPath: string; const pSet: TDictionary<string, Boolean>;
  const pDirect: TDictionary<string, TList<string>>; out pError: string): Boolean;
var
  LStore: TSQLiteSymbolStore;
  LQuery: TFDQuery;
begin
  pError:= '';
  if not FileExists(pDbPath) then
  begin
    pError:= 'index not found: ' + pDbPath;
    Exit(False);
  end;
  try
    LStore:= TSQLiteSymbolStore.Create(pDbPath, {AReadOnly=}True);
    try
      LQuery:= TFDQuery.Create(nil);
      try
        LQuery.Connection:= LStore.GetConnection;
        ReadSourceNames(LQuery, pSet);
        if Assigned(pDirect) then
          ReadUnresolvedUses(LQuery, pDirect);
      finally
        LQuery.Free;
      end;
    finally
      LStore.Free;
    end;
    Result:= True;
  except
    on E: Exception do
    begin
      pError:= 'cannot read index ' + pDbPath + ': ' + E.Message;
      Result:= False;
    end;
  end;
end;

function TUsesRecoverRun.Load(out pError: string): Boolean;
var
  LDir, LFile, LLib, LName: string;
begin
  pError:= '';
  for LDir in Opts.HppDirs do
  begin
    if not TDirectory.Exists(LDir) then
    begin
      pError:= 'header directory not found: ' + LDir;
      Exit(False);
    end;
    for LFile in TDirectory.GetFiles(LDir, CHppMask) do
      if not FHeaders.ContainsKey(LowerCase(TPath.GetFileNameWithoutExtension(LFile))) then
        FHeaders.Add(LowerCase(TPath.GetFileNameWithoutExtension(LFile)), LFile);
  end;
  for LLib in Opts.LibraryDbs do
    if not LoadSourceNames(LLib, FLibrary, nil, pError) then
      Exit(False);
  FHasMap:= Opts.MapPath <> '';
  if HasMap then
  begin
    if not FileExists(Opts.MapPath) then
    begin
      pError:= 'map file not found: ' + Opts.MapPath;
      Exit(False);
    end;
    FMapOrder:= ParseMapUnits(TFile.ReadAllText(Opts.MapPath));
    for LName in FMapOrder do
      FMap.AddOrSetValue(LowerCase(LName), True);
  end;
  Result:= True;
end;

procedure TUsesRecoverRun.Recover(const pDirect: TDictionary<string, TList<string>>);
var
  LQueue: TQueue<TRecoveredUnit>;
  LNames: TArray<string>;
  LName, LCanon, LHeader, LUser, LInc: string;
  LUnit, LOther: TRecoveredUnit;
  LEdge: TRecoveredEdge;

  { Records pName (reached from pUser) as a unit to follow, or as having no header. }
  procedure Reach(const pName, pReach, pUser: string);
  begin
    LHeader:= FindHeader(pName, LCanon);
    if FSeen.TryGetValue(LowerCase(LCanon), LOther) then
    begin
      LOther.AddUser(pUser);
      Exit;
    end;
    LOther:= TRecoveredUnit.Create(LCanon, pReach, LHeader);
    LOther.AddUser(pUser);
    FSeen.Add(LowerCase(LCanon), LOther);
    if LHeader = '' then
      NoHeader.Add(LOther)
    else
    begin
      Units.Add(LOther);
      LQueue.Enqueue(LOther);
    end;
  end;

begin
  LQueue:= TQueue<TRecoveredUnit>.Create;
  try
    LNames:= pDirect.Keys.ToArray;
    TArray.Sort<string>(LNames, TStringComparer.Ordinal);
    for LName in LNames do
      if Classify(LName) = CStatusSourceless then
        for LUser in pDirect[LName] do
          Reach(LName, CReachDirect, LUser);
    while LQueue.Count > 0 do
    begin
      LUnit:= LQueue.Dequeue;
      for LInc in ParseHppIncludes(TFile.ReadAllText(LUnit.Header)) do
      begin
        if IsImplicitUnit(LInc) or SameText(LInc, LUnit.Name) then
          Continue;
        LEdge.UnitName:= LInc;
        LEdge.Status:= Classify(LInc);
        LUnit.Edges.Add(LEdge);
        if LEdge.Status = CStatusSourceless then
          Reach(LInc, CReachHeader, LUnit.Name);
      end;
    end;
  finally
    LQueue.Free;
  end;
  FMapOnly:= nil;
  for LName in FMapOrder do
    if (not IsImplicitUnit(LName)) and (Classify(LName) = CStatusSourceless)
      and (not FSeen.ContainsKey(LowerCase(LName))) then
      FMapOnly:= FMapOnly + [LName];
end;

function ParseUsesRecoverArgs(const pArgs: TArray<string>; out pOpts: TUsesRecoverOptions;
  out pError, pBadFlag: string): Boolean;
var
  I: Integer;
  LTok, LValue: string;
  LFlag: TUsesRecoverFlag;
  LKnown: Boolean;
begin
  pOpts:= Default(TUsesRecoverOptions);
  pError:= '';
  pBadFlag:= '';
  I:= 0;
  while I <= High(pArgs) do
  begin
    LTok:= pArgs[I];
    LKnown:= False;
    LFlag:= Low(TUsesRecoverFlag);
    for var F:= Low(TUsesRecoverFlag) to High(TUsesRecoverFlag) do
      if LTok = USES_RECOVER_FLAG_NAMES[F] then
      begin
        LFlag:= F;
        LKnown:= True;
      end;
    if (not LKnown) and ((LTok = '-h') or (LTok = '/?')) then
    begin
      LFlag:= urfHelp;
      LKnown:= True;
    end;
    if not LKnown then
    begin
      pBadFlag:= LTok;
      pError:= 'Unknown argument: ' + LTok;
      Exit(False);
    end;
    LValue:= '';
    if LFlag in USES_RECOVER_VALUE_FLAGS then
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
      urfDb       : pOpts.DbPath:= ExpandFileName(LValue);
      urfHppDir   : pOpts.HppDirs:= pOpts.HppDirs + [ExpandFileName(LValue)];
      urfLibraryDb: pOpts.LibraryDbs:= pOpts.LibraryDbs + [ExpandFileName(LValue)];
      urfMap      : pOpts.MapPath:= ExpandFileName(LValue);
      urfJson     : pOpts.AsJson:= True;
      urfHelp     : pOpts.ShowHelp:= True;
      urfOutputEncoding: ; { consumed by Run before the dispatch; accepted so it is not "unknown" }
    end;
    Inc(I);
  end;
  Result:= True;
end;

function StrArray(const pItems: TArray<string>): TJSONArray;
var
  LItem: string;
begin
  Result:= TJSONArray.Create;
  for LItem in pItems do
    Result.Add(LItem);
end;

function UnitJson(const pRun: TUsesRecoverRun; const pUnit: TRecoveredUnit): TJSONObject;
var
  LEdges: TJSONArray;
  LEdge: TRecoveredEdge;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('unit', pUnit.Name);
  Result.AddPair('reach', pUnit.Reach);
  Result.AddPair('used_by', StrArray(pUnit.UsedBy.ToArray));
  if pUnit.Header = '' then
    Result.AddPair('header', TJSONNull.Create)
  else
    Result.AddPair('header', pUnit.Header);
  if pRun.HasMap then
    Result.AddPair('in_map', TJSONBool.Create(pRun.InMap(pUnit.Name)))
  else
    Result.AddPair('in_map', TJSONNull.Create);
  if pUnit.Header <> '' then
  begin
    LEdges:= TJSONArray.Create;
    for LEdge in pUnit.Edges do
      LEdges.AddElement(TJSONObject.Create.AddPair('unit', LEdge.UnitName).AddPair('status', LEdge.Status));
    Result.AddPair('uses', LEdges);
  end;
end;

procedure WriteJson(const pRun: TUsesRecoverRun);
var
  LRoot: TJSONObject;
  LArr: TJSONArray;
  LUnit: TRecoveredUnit;
begin
  LRoot:= TJSONObject.Create;
  try
    LRoot.AddPair('db', pRun.Opts.DbPath);
    LRoot.AddPair('hpp_dirs', StrArray(pRun.Opts.HppDirs));
    LRoot.AddPair('library_dbs', StrArray(pRun.Opts.LibraryDbs));
    if pRun.HasMap then
      LRoot.AddPair('map', pRun.Opts.MapPath)
    else
      LRoot.AddPair('map', TJSONNull.Create);
    LRoot.AddPair('headers_found', TJSONNumber.Create(pRun.HeaderCount));
    LArr:= TJSONArray.Create;
    for LUnit in pRun.Units do
      LArr.AddElement(UnitJson(pRun, LUnit));
    LRoot.AddPair('units', LArr);
    LArr:= TJSONArray.Create;
    for LUnit in pRun.NoHeader do
      LArr.AddElement(UnitJson(pRun, LUnit));
    LRoot.AddPair('no_header', LArr);
    LRoot.AddPair('map_only', StrArray(pRun.MapOnly));
    Writeln(LRoot.ToJSON);
  finally
    LRoot.Free;
  end;
end;

procedure WriteText(const pRun: TUsesRecoverRun);
var
  LUnit: TRecoveredUnit;
  LEdge: TRecoveredEdge;
  LMap: string;
begin
  Writeln(Format('uses-recover: %d sourceless unit(s) recovered, %d with no header; %d header(s) in %d dir(s)',
    [pRun.Units.Count, pRun.NoHeader.Count, pRun.HeaderCount, Length(pRun.Opts.HppDirs)]));
  for LUnit in pRun.Units do
  begin
    LMap:= if not pRun.HasMap then '' else if pRun.InMap(LUnit.Name) then ', in map' else ', not seen in map';
    Writeln(Format('  %s  [%s%s]  used by %s', [LUnit.Name, LUnit.Reach, LMap,
      string.Join(', ', LUnit.UsedBy.ToArray)]));
    Writeln('    header ' + LUnit.Header);
    for LEdge in LUnit.Edges do
      Writeln(Format('    -> %s  %s', [LEdge.UnitName, LEdge.Status]));
  end;
  for LUnit in pRun.NoHeader do
    Writeln(Format('  no header: %s  used by %s', [LUnit.Name, string.Join(', ', LUnit.UsedBy.ToArray)]));
  if pRun.HasMap then
    Writeln(Format('map: linked but reached by no header (implementation uses?): %s',
      [if Length(pRun.MapOnly) = 0 then '(none)' else string.Join(', ', pRun.MapOnly)]));
end;

function Usage(const pWhy: string; pAsJson: Boolean): Integer;
begin
  Writeln(ErrOutput, CVerb + ': ' + pWhy);
  if not pAsJson then
    Writeln(ErrOutput, 'usage: drag-lint uses-recover --db <db> --hpp-dir <dir>... [--library-db <db>...] [--map <file.map>] [--json]');
  Result:= CExitUsage;
end;

function Execute(const pOpts: TUsesRecoverOptions): Integer;
var
  LRun: TUsesRecoverRun;
  LDirect: TObjectDictionary<string, TList<string>>;
  LIndexed: TDictionary<string, Boolean>;
  LError: string;
begin
  LRun:= TUsesRecoverRun.Create(pOpts);
  LDirect:= TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  try
    if not LRun.Load(LError) then
      Exit(Usage(LError, pOpts.AsJson));
    LIndexed:= LRun.FIndexed;
    if not LoadSourceNames(pOpts.DbPath, LIndexed, LDirect, LError) then
      Exit(Usage(LError, pOpts.AsJson));
    LRun.Recover(LDirect);
    if pOpts.AsJson then
      WriteJson(LRun)
    else
      WriteText(LRun);
    Result:= CExitOk;
  finally
    LDirect.Free;
    LRun.Free;
  end;
end;

function RunUsesRecoverVerb: Integer;
var
  LArgs: TArray<string>;
  LOpts: TUsesRecoverOptions;
  LError, LBadFlag: string;
  I: Integer;
begin
  LArgs:= nil;
  for I:= CFirstArg to ParamCount do
    LArgs:= LArgs + [ParamStr(I)];
  if not ParseUsesRecoverArgs(LArgs, LOpts, LError, LBadFlag) then
  begin
    if LBadFlag <> '' then
    begin
      WriteCliError(CLI_ERR_UNKNOWN_FLAG, LError, CommandLineWantsJson, 'flag', LBadFlag);
      Result:= CExitUnknownFlag;
    end
    else
      Result:= Usage(LError, CommandLineWantsJson);
  end
  else if LOpts.ShowHelp then
  begin
    WriteVerbHelp(CVerb);
    Result:= CExitOk;
  end
  else
    Result:= if LOpts.DbPath = '' then Usage('give --db <file.sqlite>', LOpts.AsJson)
      else if Length(LOpts.HppDirs) = 0 then Usage('give at least one --hpp-dir <dir>', LOpts.AsJson)
      else Execute(LOpts);
end;

end.
