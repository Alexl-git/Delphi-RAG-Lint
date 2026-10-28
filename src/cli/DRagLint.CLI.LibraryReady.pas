unit DRagLint.CLI.LibraryReady;

/// <summary>Library readiness probe: is a platform library index COMPLETE and current enough
/// that a project resolve pass may bind against it? (library-first resolve plan s.2.2.)</summary>
/// <remarks>Read-only: the library is opened with the read-only store and never written.
/// Lives under src\cli, not src\index, so it does not move the extractor hash.
/// All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.</remarks>

interface

type
  /// <summary>Why a library is, or is not, ready to bind against.</summary>
  TLibraryReadiness = (lrReady, lrMissing, lrUnreadable, lrSchemaOld, lrRebuilding,
                       lrStaleExtractor, lrNewerThanEngine, lrNeverCompleted);

/// <summary>Probes one library index file for readiness.</summary>
/// <param name="ALibDb">Path of the library sqlite file; '' reads as missing.</param>
/// <param name="APlatform">Expected platform token (Win32/Win64); '' skips the platform check.</param>
/// <param name="AWhy">Out: a short human reason; '' when ready.</param>
/// <param name="AStampFp">Out: the library's stored indexer_fingerprint ('' when unreadable).</param>
/// <returns>lrReady only when the schema is current, no rebuild is in progress, a walk completed,
/// and the extractor limb equals this engine's.</returns>
/// <remarks>Never raises; every failure maps to a state. Never writes the library.</remarks>
function ProbeLibraryReadiness(const ALibDb, APlatform: string; out AWhy, AStampFp: string): TLibraryReadiness;

/// <summary>Short stable token for a state.</summary>
/// <param name="AState">The state.</param>
/// <returns>For example 'rebuilding' or 'stale-extractor'.</returns>
function LibraryReadinessToken(AState: TLibraryReadiness): string;

implementation

uses
  System.SysUtils, System.IOUtils,
  DRagLint.Core.Interfaces, DRagLint.Core.Model, DRagLint.Core.Versions,
  DRagLint.Index.Freshness, DRagLint.Storage.SQLite;

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
    lrNeverCompleted : Result:= 'never-completed';
  else
    Result:= 'unknown';
  end;
end;

{ The text between APrefix and the next ';' of a fingerprint ('' when absent). }
function FpLimb(const AFingerprint, APrefix: string): string;
begin
  Result:= '';
  var P: Integer:= Pos(';' + APrefix, ';' + AFingerprint);
  if P = 0 then Exit;
  var Rest: string:= Copy(AFingerprint, P + Length(APrefix), MaxInt);
  var Semi: Integer:= Pos(';', Rest);
  Result:= if Semi > 0 then Copy(Rest, 1, Semi - 1) else Rest;
end;

function ProbeLibraryReadiness(const ALibDb, APlatform: string; out AWhy, AStampFp: string): TLibraryReadiness;
var
  Found, Expected: Integer;
  Store          : ISymbolStore;
begin
  AWhy    := '';
  AStampFp:= '';
  if (ALibDb = '') or not TFile.Exists(ALibDb) then
  begin
    AWhy:= 'library index not found';
    Exit(lrMissing);
  end;
  Result:= lrReady;
  try
    Store:= TSQLiteSymbolStore.Create(ALibDb, {AReadOnly=}True);
    AStampFp:= Store.GetMetaValue(INDEXER_FINGERPRINT_META_KEY);
    var Plat: string:= FpLimb(AStampFp, 'plat=');
    var Ver : string:= FpLimb(AStampFp, 'v=');
    var Cmp : Integer:= CompareDottedVersions(Ver, DRAGLINT_EXTRACTOR_VERSION);
    if not Store.IsSchemaCurrent(Found, Expected) then
    begin
      AWhy:= Format('schema v%d, this engine needs v%d', [Found, Expected]);
      Result:= lrSchemaOld;
    end
    else if Store.GetMetaValue(REBUILD_IN_PROGRESS_META_KEY) = '1' then
    begin
      AWhy:= 'rebuild in progress (rebuild_in_progress=1)';
      Result:= lrRebuilding;
    end
    else if (AStampFp = '') or (Store.GetMetaValue(INDEXED_AT_KEY) = '') then
    begin
      AWhy:= 'no completed walk recorded';
      Result:= lrNeverCompleted;
    end
    else if (APlatform <> '') and (Plat <> '') and not SameText(Plat, APlatform) then
    begin
      AWhy:= Format('library is the %s platform, wanted %s', [Plat, APlatform]);
      Result:= lrMissing;
    end
    else if (Ver = '') or (Cmp < 0) then
    begin
      AWhy:= Format('stale-extractor (v=%s, engine %s)', [Ver, DRAGLINT_EXTRACTOR_VERSION]);
      Result:= lrStaleExtractor;
    end
    else if Cmp > 0 then
    begin
      AWhy:= Format('newer than this engine (v=%s, engine %s)', [Ver, DRAGLINT_EXTRACTOR_VERSION]);
      Result:= lrNewerThanEngine;
    end;
  except
    on E: Exception do
    begin
      AWhy:= 'unreadable: ' + E.Message;
      Result:= lrUnreadable;
    end;
  end;
end;

end.
