unit DRagLint.CLI.LibraryReady;

/// <summary>Library readiness for library-first resolve (plan 2026-10-28, s.2.1 and s.2.2): can the
/// platform library DB be consulted by a project's call-resolve pass NOW, and which platform's
/// library does a project bind against.</summary>
/// <remarks>Class n: lives in src\cli, not under src\index, so it never moves the extractor hash.
/// Read-only: a probe opens the library with the read-only store and never writes it.
/// A library is never half readable at the SQLite level (WAL snapshots), so readiness is a STAMP
/// question: schema current, not rebuilding, a walk completed, extractor limb equal to this engine.
/// All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.</remarks>

interface

type
  /// <summary>Why a library can (lrReady) or cannot be consulted.</summary>
  /// <remarks>lrReady = schema current, not rebuilding, completed, extractor limb equal. lrMissing = no file or the other platform's DB. lrRebuilding = rebuild_in_progress=1 (B-23). lrStaleExtractor / lrNewerThanEngine = extractor limb older / newer than this engine. lrNeverCompleted = no completed-walk stamp.</remarks>
  TLibraryReadiness = (
    lrReady,
    lrMissing,
    lrUnreadable,
    lrSchemaOld,
    lrRebuilding,
    lrStaleExtractor,
    lrNewerThanEngine,
    lrNeverCompleted
  );

/// <summary>The outcome of evaluating the library an index run would consult (the readiness API
/// lf-marker, lf-order and the LSP read).</summary>
/// <remarks>Active = the run opted in (manifest libraryResolve, or an explicit --library-db) and the
/// library is not the DB being built. State/Why come from ProbeLibraryReadiness. Refuse = the run
/// must stop with exit 2 (--require-library and not ready). Explicit = the user named the store
/// with --library-db: printed, never waited on, never refused.</remarks>
type
  TLibraryGate = record
    Active        : Boolean;
    Explicit      : Boolean;
    Refuse        : Boolean;
    Platform      : string;
    PlatformSource: string;
    LibDb         : string;
    State         : TLibraryReadiness;
    Why           : string;
    StampFp       : string;
  end;

/// <summary>Short stable token for a state, as printed in notices and stored in the marker.</summary>
/// <param name="AState">The probe result.</param>
/// <returns>'ready', 'missing', 'unreadable', 'schema-old', 'rebuilding', 'stale-extractor',
/// 'newer-than-engine' or 'never-completed'.</returns>
function LibraryReadinessToken(AState: TLibraryReadiness): string;

/// <summary>Probes whether the library DB at ALibDb may be consulted for APlatform now.</summary>
/// <param name="ALibDb">Library DB path; '' or a missing file reads lrMissing.</param>
/// <param name="APlatform">Platform the project binds against ('Win64'); '' skips the platform check.</param>
/// <param name="AWhy">Human reason, filled for every state including lrReady (the completed-at stamp).</param>
/// <param name="AStampFp">The library's stored indexer_fingerprint ('' when absent).</param>
/// <returns>lrReady only when every stamp says the library finished a walk under this engine's extractor.</returns>
/// <remarks>Read-only (query_only handle, 5 s busy). A stale extractor counts as NOT ready (plan Q1
/// default): binding against an old parse would record a fingerprint the next `info` calls stale.</remarks>
function ProbeLibraryReadiness(const ALibDb, APlatform: string; out AWhy, AStampFp: string): TLibraryReadiness;

/// <summary>The same decision as ProbeLibraryReadiness over already-read stamps; pure, for tests and `info`.</summary>
/// <param name="AFingerprint">indexer_fingerprint value ('' = absent).</param>
/// <param name="AIndexedAt">indexed_at_unix value ('' = absent).</param>
/// <param name="ARebuilding">rebuild_in_progress = '1'.</param>
/// <param name="APlatform">Expected platform ('' = skip).</param>
/// <param name="AEngineExtractor">The engine's extractor version.</param>
/// <param name="AWhy">Human reason.</param>
/// <returns>The readiness; schema currency is the caller's check.</returns>
function ClassifyLibraryStamps(const AFingerprint, AIndexedAt: string; ARebuilding: Boolean;
  const APlatform, AEngineExtractor: string; out AWhy: string): TLibraryReadiness;

/// <summary>One limb of a stored fingerprint: the text after APrefix up to the next ';'.</summary>
/// <param name="AFingerprint">E.g. 'v=1.26.0-alpha;schema=23;pp=1;plat=win64'.</param>
/// <param name="APrefix">E.g. 'plat=' (matched at a limb start).</param>
/// <returns>The limb value, or '' when absent.</returns>
function FingerprintLimbValue(const AFingerprint, APrefix: string): string;

/// <summary>The platform a project binds its library against, project-authoritative (plan s.2.1).</summary>
/// <param name="APlatformArg">--platform, wins when given.</param>
/// <param name="AProjectFingerprint">The project DB's own indexer_fingerprint ('' when never completed).</param>
/// <param name="ADproj">The project's .dproj (or .dpr); '' skips the dproj step.</param>
/// <param name="ADefaultPlatform">Manifest default platform, the last resort.</param>
/// <param name="ASource">Out: 'arg', 'db-fingerprint', 'dproj' or 'default'.</param>
/// <returns>A platform token such as 'Win64'.</returns>
function ChooseLibraryPlatform(const APlatformArg, AProjectFingerprint, ADproj, ADefaultPlatform: string;
  out ASource: string): string;

/// <summary>The first Win32/Win64 token of a .dproj's `Platform Condition=` element.</summary>
/// <param name="ADproj">Path of the .dproj (a .dpr is mapped to its sibling .dproj).</param>
/// <returns>'Win32', 'Win64' or '' (no file, no element).</returns>
function PlatformOfDproj(const ADproj: string): string;

implementation

uses
    System.SysUtils
  , System.DateUtils
  , System.IOUtils
  , DRagLint.Core.Interfaces
  , DRagLint.Core.Model
  , DRagLint.Core.Versions
  , DRagLint.Index.Freshness
  , DRagLint.Storage.SQLite
  ;

function LibraryReadinessToken(AState: TLibraryReadiness): string;
begin
  case AState of
    lrReady          : Result:= 'ready';
    lrMissing        : Result:= 'missing';
    lrUnreadable     : Result:= 'unreadable';
    lrSchemaOld      : Result:= 'schema-old';
    lrRebuilding     : Result:= 'rebuilding';
    lrStaleExtractor : Result:= 'stale-extractor';
    lrNewerThanEngine: Result:= 'newer-than-engine';
  else                 Result:= 'never-completed';
  end;
end;

function FingerprintLimbValue(const AFingerprint, APrefix: string): string;
begin
  Result:= '';
  var Limbs: TArray<string>:= AFingerprint.Split([';']);
  for var L: string in Limbs do
    if L.StartsWith(APrefix) then Exit(Copy(L, Length(APrefix) + 1, MaxInt));
end;

function ClassifyLibraryStamps(const AFingerprint, AIndexedAt: string; ARebuilding: Boolean;
  const APlatform, AEngineExtractor: string; out AWhy: string): TLibraryReadiness;
begin
  AWhy:= '';
  if ARebuilding then
  begin
    AWhy:= 'rebuild in progress (rebuild_in_progress=1)';
    Exit(lrRebuilding);
  end;
  if (AFingerprint = '') or (AIndexedAt = '') then
  begin
    AWhy:= 'no completed walk stamped (killed first index run?)';
    Exit(lrNeverCompleted);
  end;
  var Plat: string:= FingerprintLimbValue(AFingerprint, 'plat=');
  if (APlatform <> '') and (Plat <> '') and not SameText(Plat, APlatform) then
  begin
    AWhy:= 'this is the ' + Plat + ' library, not ' + APlatform;
    Exit(lrMissing);
  end;
  var Ver: string:= FingerprintLimbValue(AFingerprint, 'v=');
  var Cmp: Integer:= CompareDottedVersions(Ver, AEngineExtractor);
  if Cmp < 0 then
  begin
    AWhy:= Format('stale-extractor (v=%s, engine %s)', [Ver, AEngineExtractor]);
    Exit(lrStaleExtractor);
  end;
  if Cmp > 0 then
  begin
    AWhy:= Format('built by a newer extractor (v=%s, engine %s)', [Ver, AEngineExtractor]);
    Exit(lrNewerThanEngine);
  end;
  var Unix: Int64:= StrToInt64Def(AIndexedAt, 0);
  AWhy:= 'v=' + Ver;
  if Unix > 0 then AWhy:= AWhy + ', completed ' + FormatDateTime('yyyy-mm-dd hh:nn', UnixToDateTime(Unix, False));
  Result:= lrReady;
end;

function ProbeLibraryReadiness(const ALibDb, APlatform: string; out AWhy, AStampFp: string): TLibraryReadiness;
var
  Store: ISymbolStore;
  Found: Integer;
  Need : Integer;
begin
  AStampFp:= '';
  AWhy    := '';
  if (ALibDb = '') or not TFile.Exists(ALibDb) then
  begin
    AWhy:= 'no library index file';
    Exit(lrMissing);
  end;
  try
    Store:= TSQLiteSymbolStore.Create(ALibDb, {AReadOnly=}True);
    if not Store.IsSchemaCurrent(Found, Need) then
    begin
      AWhy:= Format('schema v%d, this engine needs v%d', [Found, Need]);
      Exit(lrSchemaOld);
    end;
    AStampFp:= Store.GetMetaValue(INDEXER_FINGERPRINT_META_KEY);
    Result  := ClassifyLibraryStamps(AStampFp, Store.GetMetaValue(INDEXED_AT_KEY),
      Store.GetMetaValue(REBUILD_IN_PROGRESS_META_KEY) = '1', APlatform, DRAGLINT_EXTRACTOR_VERSION, AWhy);
  except
    on E: Exception do
    begin
      AWhy  := E.ClassName + ': ' + E.Message;
      Result:= lrUnreadable;
    end;
  end;
end;

function PlatformOfDproj(const ADproj: string): string;
begin
  Result:= '';
  var Path: string:= ADproj;
  if SameText(ExtractFileExt(Path), '.dpr') then Path:= ChangeFileExt(Path, '.dproj');
  if (Path = '') or not TFile.Exists(Path) then Exit;
  var Xml: string:= '';
  try
    Xml:= TFile.ReadAllText(Path);
  except
    on E: Exception do Xml:= '';
  end;
  var P1: Integer:= Pos('<Platform Condition=', Xml);
  while P1 > 0 do
  begin
    P1:= Pos('>', Xml, P1);
    if P1 = 0 then Break;
    var P2: Integer:= Pos('<', Xml, P1 + 1);
    if P2 = 0 then Break;
    var Tok: string:= Trim(Copy(Xml, P1 + 1, P2 - P1 - 1));
    if (Tok = 'Win32') or (Tok = 'Win64') then Exit(Tok);
    P1:= Pos('<Platform Condition=', Xml, P2);
  end;
end;

function ChooseLibraryPlatform(const APlatformArg, AProjectFingerprint, ADproj, ADefaultPlatform: string;
  out ASource: string): string;
begin
  if APlatformArg <> '' then
  begin
    ASource:= 'arg';
    Exit(APlatformArg);
  end;
  var Plat: string:= FingerprintLimbValue(AProjectFingerprint, 'plat=');
  if SameText(Plat, 'win64') then
  begin
    ASource:= 'db-fingerprint';
    Exit('Win64');
  end;
  if SameText(Plat, 'win32') then
  begin
    ASource:= 'db-fingerprint';
    Exit('Win32');
  end;
  Plat:= PlatformOfDproj(ADproj);
  if Plat <> '' then
  begin
    ASource:= 'dproj';
    Exit(Plat);
  end;
  ASource:= 'default';
  Result := ADefaultPlatform;
end;

end.
