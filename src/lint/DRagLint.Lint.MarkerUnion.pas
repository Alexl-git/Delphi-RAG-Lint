unit DRagLint.Lint.MarkerUnion;

{ The marker evidence of `lint-all --shared-db`. A dl:shared unit is compiled by
  several projects, each with its own index, so a dl:ok for a closure-dependent rule
  can be live under a project the primary run knows nothing about. One index skips
  the verdict (YADF FP #5); --shared-db runs `lint-all` once per peer DB, each in its
  own process, and this unit carries what each run learned back to the primary.

  A child process, not a second pass in-process: the walk installs per-run globals
  (the preprocess profile, the target gate, the undecided-site list) and a peer is
  exactly "what `lint-all --db <peer>` would say" only if it runs alone. }

interface

uses
  System.SysUtils,
  System.Generics.Collections;

const
  /// <summary>Set by the primary for a peer's process: the file the peer writes its
  /// account to. Internal to --shared-db; a run without it writes nothing.</summary>
  MARKER_ACCOUNT_ENV = 'DRAGLINT_MARKER_ACCOUNT_OUT';

type
  /// <summary>A review-marker-stale hint a peer run emitted.</summary>
  TPeerStaleHint = record
    /// <summary>The file the hint is reported on, as the peer spelled it.</summary>
    FilePath: string;
    /// <summary>The line the hint is reported on.</summary>
    Line: Integer;
    /// <summary>The rule the stale marker reviews.</summary>
    MarkerRule: string;
    /// <summary>The peer's message.</summary>
    Message: string;
    /// <summary>Display name of the peer DB; empty until read back.</summary>
    PeerDb: string;
  end;

  /// <summary>What one lint-all run learned about review markers, as written by a
  /// peer and read by the primary.</summary>
  /// <remarks>Instance is owned by the verb that ran the peers; not thread-safe, used
  /// from the main thread only. Keys come from MarkerKey, so both ends agree on the
  /// spelling of a path.</remarks>
  TMarkerUnion = class
  strict private
    FLive: TDictionary<string, Boolean>;
    FUnjudged: TDictionary<string, Boolean>;
    FScanCount: TDictionary<string, Integer>;
    FStale: TList<TPeerStaleHint>;
    FPeers: Integer;
    FJudged: Integer;
    FLeftUnjudged: Integer;
    function GetStaleHints: TArray<TPeerStaleHint>;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>The normalised spelling of a source path: absolute, backslashes,
    /// lower case.</summary>
    /// <param name="AFile">The path; relative paths resolve against the process cwd.</param>
    /// <returns>The normalised path; '' for ''.</returns>
    class function NormalPath(const AFile: string): string; static;

    /// <summary>The join key of a marker and the findings it reviews.</summary>
    /// <param name="AFile">The file holding the marker.</param>
    /// <param name="ALine">The marker's own line.</param>
    /// <param name="ARule">The rule the marker names.</param>
    /// <returns>The key, comparable across processes that share a file tree.</returns>
    class function MarkerKey(const AFile: string; ALine: Integer; const ARule: string): string; static;

    /// <summary>Writes one run's account for the primary to read.</summary>
    /// <param name="APath">Target file; overwritten.</param>
    /// <param name="AScanned">Every file the run examined.</param>
    /// <param name="ALive">Keys of markers a finding of this run reached, fresh or stale.</param>
    /// <param name="AUnjudged">Keys of markers this run has no evidence about (a line the
    /// preprocessor blanked, an undecided shared-unit site).</param>
    /// <param name="AStale">The run's review-marker-stale hints.</param>
    /// <remarks>Ends with an END line; a file without it is read as no account at all.</remarks>
    class procedure WriteAccount(const APath: string; const AScanned, ALive, AUnjudged: TArray<string>;
      const AStale: TArray<TPeerStaleHint>); static;

    /// <summary>Merges one peer's account.</summary>
    /// <param name="APath">The file the peer wrote.</param>
    /// <param name="APeerDb">The peer's display name, for the hints read back.</param>
    /// <returns>False, merging nothing, when the file is missing or truncated: that peer
    /// did not take part.</returns>
    function AddPeerAccount(const APath, APeerDb: string): Boolean;

    /// <summary>How many merged peers scanned the file.</summary>
    /// <param name="AFile">Any spelling of the path.</param>
    /// <returns>The count; 0 when none did.</returns>
    function PeersScanning(const AFile: string): Integer;

    /// <summary>Did any merged peer produce a finding this marker reviews?</summary>
    /// <param name="AKey">A MarkerKey.</param>
    /// <returns>True when at least one did.</returns>
    function IsLive(const AKey: string): Boolean;

    /// <summary>Did any merged peer lack the evidence to judge this marker?</summary>
    /// <param name="AKey">A MarkerKey.</param>
    /// <returns>True when at least one did; the marker then keeps the skip.</returns>
    function IsUnjudged(const AKey: string): Boolean;

    /// <summary>Counts a marker the union gave a verdict.</summary>
    procedure NoteJudged;

    /// <summary>Counts a marker the union could not judge.</summary>
    procedure NoteLeftUnjudged;

    /// <summary>The merged peers' stale hints, in merge order.</summary>
    property StaleHints: TArray<TPeerStaleHint> read GetStaleHints;
    /// <summary>How many peers were merged.</summary>
    property Peers: Integer read FPeers;
    /// <summary>Markers judged so far.</summary>
    property Judged: Integer read FJudged;
    /// <summary>Markers left unjudged so far.</summary>
    property LeftUnjudged: Integer read FLeftUnjudged;
  end;

implementation

uses
  System.Classes,
  System.IOUtils;

const
  SEP = #9;
  KIND_SCANNED = 'S';
  KIND_LIVE = 'L';
  KIND_UNJUDGED = 'U';
  KIND_STALE = 'H';
  END_LINE = 'END';
  STALE_FIELD_LINE = 1;
  STALE_FIELD_RULE = 2;
  STALE_FIELD_FILE = 3;
  STALE_FIELD_MESSAGE = 4;
  STALE_FIELD_COUNT = 5;

{ TMarkerUnion }

constructor TMarkerUnion.Create;
begin
  inherited Create;
  FLive:= TDictionary<string, Boolean>.Create;
  FUnjudged:= TDictionary<string, Boolean>.Create;
  FScanCount:= TDictionary<string, Integer>.Create;
  FStale:= TList<TPeerStaleHint>.Create;
end;

destructor TMarkerUnion.Destroy;
begin
  FStale.Free;
  FScanCount.Free;
  FUnjudged.Free;
  FLive.Free;
  inherited Destroy;
end;

class function TMarkerUnion.NormalPath(const AFile: string): string;
begin
  Result:= StringReplace(AFile, '/', '\', [rfReplaceAll]);
  if Result <> '' then Result:= LowerCase(ExpandFileName(Result));
end;

class function TMarkerUnion.MarkerKey(const AFile: string; ALine: Integer; const ARule: string): string;
begin
  Result:= NormalPath(AFile) + '|' + IntToStr(ALine) + '|' + LowerCase(ARule);
end;

class procedure TMarkerUnion.WriteAccount(const APath: string; const AScanned, ALive, AUnjudged: TArray<string>;
  const AStale: TArray<TPeerStaleHint>);
var
  Lines: TStringList;
begin
  Lines:= TStringList.Create;
  try
    for var S: string in AScanned do Lines.Add(KIND_SCANNED + SEP + NormalPath(S));
    for var K: string in ALive do Lines.Add(KIND_LIVE + SEP + K);
    for var K: string in AUnjudged do Lines.Add(KIND_UNJUDGED + SEP + K);
    for var H: TPeerStaleHint in AStale do
      Lines.Add(KIND_STALE + SEP + IntToStr(H.Line) + SEP + H.MarkerRule + SEP + H.FilePath + SEP + H.Message);
    Lines.Add(END_LINE);
    Lines.SaveToFile(APath, TEncoding.UTF8);  // dl:ok taint-path-traversal@4285 -- the path is a temp file the parent engine chose for its own child, not user input
  finally
    Lines.Free;
  end;
end;

function TMarkerUnion.AddPeerAccount(const APath, APeerDb: string): Boolean;
var
  Lines: TArray<string>;
begin
  Result:= False;
  if not TFile.Exists(APath) then Exit;
  Lines:= TFile.ReadAllLines(APath, TEncoding.UTF8);
  if (Length(Lines) = 0) or (Lines[High(Lines)] <> END_LINE) then Exit;
  for var L: string in Lines do
  begin
    var Parts: TArray<string>:= L.Split([SEP]);
    if Length(Parts) < 2 then Continue;
    if Parts[0] = KIND_SCANNED then
    begin
      var N: Integer;
      if not FScanCount.TryGetValue(Parts[1], N) then N:= 0;
      FScanCount.AddOrSetValue(Parts[1], N + 1);
    end
    else if Parts[0] = KIND_LIVE then FLive.AddOrSetValue(Parts[1], True)
    else if Parts[0] = KIND_UNJUDGED then FUnjudged.AddOrSetValue(Parts[1], True)
    else if (Parts[0] = KIND_STALE) and (Length(Parts) = STALE_FIELD_COUNT) then
    begin
      var H: TPeerStaleHint:= Default(TPeerStaleHint);
      H.Line      := StrToIntDef(Parts[STALE_FIELD_LINE], 0);
      H.MarkerRule:= Parts[STALE_FIELD_RULE];
      H.FilePath  := Parts[STALE_FIELD_FILE];
      H.Message   := Parts[STALE_FIELD_MESSAGE];
      H.PeerDb    := APeerDb;
      FStale.Add(H);
    end;
  end;
  Inc(FPeers);
  Result:= True;
end;

function TMarkerUnion.PeersScanning(const AFile: string): Integer;
begin
  if not FScanCount.TryGetValue(NormalPath(AFile), Result) then Result:= 0;
end;

function TMarkerUnion.IsLive(const AKey: string): Boolean;
begin
  Result:= FLive.ContainsKey(AKey);
end;

function TMarkerUnion.IsUnjudged(const AKey: string): Boolean;
begin
  Result:= FUnjudged.ContainsKey(AKey);
end;

procedure TMarkerUnion.NoteJudged;
begin
  Inc(FJudged);
end;

procedure TMarkerUnion.NoteLeftUnjudged;
begin
  Inc(FLeftUnjudged);
end;

function TMarkerUnion.GetStaleHints: TArray<TPeerStaleHint>;
begin
  Result:= FStale.ToArray;
end;

end.
