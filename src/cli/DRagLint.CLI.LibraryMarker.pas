unit DRagLint.CLI.LibraryMarker;

/// <summary>The project-DB "needs library re-resolve" marker (schema_meta key
/// LIBRARY_RESOLVE_STATE_META_KEY): its JSON form, the pure decision table that says whether a
/// writer must re-run the resolve pass, and the notice text.</summary>
/// <remarks>No schema bump: one schema_meta key holding a small JSON object. Pure logic here;
/// the CLI reads and writes the key through ISymbolStore.Get/SetMetaValue.
/// All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.</remarks>

interface

const
  /// <summary>Marker state: the section opted in but the pass ran without a ready library.</summary>
  LIBSTATE_PENDING = 'pending';
  /// <summary>Marker state: the pass ran against a ready library (external_stores is the evidence).</summary>
  LIBSTATE_BOUND   = 'bound';

type
  /// <summary>Parsed marker. State = '' means no marker.</summary>
  TLibraryMarker = record
    State        : string;
    Platform     : string;
    LibraryDb    : string;
    Reason       : string;
    FpSeen       : string;
    Engine       : string;
    SinceUnix    : Int64;
    LastCheckUnix: Int64;
  end;

  /// <summary>What a writer must do about the library this run.</summary>
  TLibraryDecision = record
    /// <summary>True: re-run the whole resolve pass (the --resolve-only path) with the library.</summary>
    RunPass : Boolean;
    /// <summary>The state the marker holds afterwards ('' = delete the marker).</summary>
    NewState: string;
  end;

/// <summary>Serialises a marker to its schema_meta JSON text.</summary>
/// <param name="AMarker">The marker.</param>
/// <returns>JSON object text: state, platform, library, reason, library_fingerprint_seen, engine, since_unix, last_check_unix.</returns>
function LibraryMarkerToJson(const AMarker: TLibraryMarker): string;

/// <summary>Parses the schema_meta text.</summary>
/// <param name="AText">Stored value; '' or malformed reads as no marker.</param>
/// <returns>The marker; State = '' when absent or unparseable.</returns>
function LibraryMarkerFromJson(const AText: string): TLibraryMarker;

/// <summary>The decision table: opt-in x marker x readiness -> run the pass?</summary>
/// <param name="AWanted">The section opted in (libraryResolve) and no explicit --library-db named a store.</param>
/// <param name="AOldState">The stored marker state ('' when none).</param>
/// <param name="AHasBound">schema_meta external_stores is present (an earlier pass bound a library).</param>
/// <param name="AReady">The probe says the library is ready.</param>
/// <returns>RunPass is the extra RanCalls term; NewState is the state the marker takes if the pass then gets a library.</returns>
function DecideLibraryResolve(AWanted: Boolean; const AOldState: string; AHasBound, AReady: Boolean): TLibraryDecision;

/// <summary>The user notice for a pending marker.</summary>
/// <param name="AMarker">A pending marker.</param>
/// <param name="ADb">The project DB path.</param>
/// <param name="ARemedy">The exact command that re-resolves it.</param>
/// <returns>A NOTE line saying the result is incomplete and how to repair it.</returns>
function LibraryPendingNote(const AMarker: TLibraryMarker; const ADb, ARemedy: string): string;

implementation

uses
  System.SysUtils, System.DateUtils, System.JSON;

function LibraryMarkerToJson(const AMarker: TLibraryMarker): string;
begin
  var J: TJSONObject:= TJSONObject.Create;
  try
    J.AddPair('state', AMarker.State);
    J.AddPair('platform', AMarker.Platform);
    J.AddPair('library', AMarker.LibraryDb);
    J.AddPair('reason', AMarker.Reason);
    J.AddPair('library_fingerprint_seen', AMarker.FpSeen);
    J.AddPair('engine', AMarker.Engine);
    J.AddPair('since_unix', TJSONNumber.Create(AMarker.SinceUnix));
    J.AddPair('last_check_unix', TJSONNumber.Create(AMarker.LastCheckUnix));
    Result:= J.ToJSON;
  finally
    J.Free;
  end;
end;

function LibraryMarkerFromJson(const AText: string): TLibraryMarker;
begin
  Result:= Default(TLibraryMarker);
  if AText = '' then Exit;
  var V: TJSONValue;
  try
    V:= TJSONObject.ParseJSONValue(AText);
  except
    on E: Exception do V:= nil;
  end;
  try
    if not (V is TJSONObject) then Exit;
    var J: TJSONObject:= TJSONObject(V);
    Result.State        := J.GetValue<string>('state', '');
    Result.Platform     := J.GetValue<string>('platform', '');
    Result.LibraryDb    := J.GetValue<string>('library', '');
    Result.Reason       := J.GetValue<string>('reason', '');
    Result.FpSeen       := J.GetValue<string>('library_fingerprint_seen', '');
    Result.Engine       := J.GetValue<string>('engine', '');
    Result.SinceUnix    := J.GetValue<Int64>('since_unix', 0);
    Result.LastCheckUnix:= J.GetValue<Int64>('last_check_unix', 0);
  finally
    V.Free;
  end;
end;

function DecideLibraryResolve(AWanted: Boolean; const AOldState: string; AHasBound, AReady: Boolean): TLibraryDecision;
begin
  Result:= Default(TLibraryDecision);
  if not AWanted then Exit; { RunPass False, NewState '' : the marker is deleted }
  if not AReady then
  begin
    Result.NewState:= LIBSTATE_PENDING; { delay again: the pass cannot bind now }
    Exit;
  end;
  Result.NewState:= LIBSTATE_BOUND;
  { A ready library and a DB that never bound one (pending, or no marker and no external_stores). }
  Result.RunPass:= (AOldState = LIBSTATE_PENDING) or ((AOldState <> LIBSTATE_BOUND) and not AHasBound);
end;

function LibraryPendingNote(const AMarker: TLibraryMarker; const ADb, ARemedy: string): string;
begin
  var Since: string:= '';
  if AMarker.SinceUnix > 0 then
    Since:= ', since ' + FormatDateTime('yyyy-mm-dd hh:nn', UnixToDateTime(AMarker.SinceUnix, False));
  Result:= Format('NOTE: %s: library-bound edges pending (%s%s) -- this answer is INCOMPLETE: callers/callees into the platform ' +
    'library may be missing; remedy: %s', [ADb, AMarker.Reason, Since, ARemedy]);
end;

end.
