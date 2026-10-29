unit DRagLint.Lint.RuleCache;

{ The on-disk cache of the whole-graph project rules that read ONLY the indexes
  (spec docs\superpowers\specs\2026-10-14-whole-graph-rule-cache.md).

  `lint <file> --db` is spawned by the IDE on every tab switch, edit and save,
  and three of its project rules -- circular-uses, enum-helper-separate-units,
  duplicate-global-decl -- answer the same thing for every file until an index
  changes. Each lint is a fresh process, so the reuse has to be on disk.

  THE KEY IS THE INDEX FILES' STATS, not the index's own stamps: every SQLite
  writer changes the size or last-write time of the .sqlite or its -wal, so an
  older engine, another team's pinned engine, a one-file reindex or a resolver
  pass all invalidate an entry -- while `indexed_at_unix` is not written by
  every path. The price is an occasional false invalidation (a checkpoint that
  changed nothing), i.e. one slow lint.

  repeated-type-switch is deliberately NOT cacheable: it parses the SOURCE
  files (TAstParseCache), so its answer moves with edits no index stat sees. }

interface

uses
  System.SysUtils
  , DRagLint.Core.Model
  ;

const
  /// <summary>The rules whose answer depends only on the project and library
  /// indexes, and so may be served from this cache.</summary>
  CACHED_RULES: array[0..2] of string = ('circular-uses', 'enum-helper-separate-units', 'duplicate-global-decl');

type
  /// <summary>What an entry is valid for: the engine build, the project index and
  /// the library index (or none), each as a path plus file-stat signature.</summary>
  /// <remarks>Two keys are the same only when all three parts are identical.</remarks>
  TRuleCacheKey = record
    /// <summary>DRAGLINT_VERSION plus the running exe's size and last-write time,
    /// so a rebuilt engine with changed rule code never reads an old entry.</summary>
    Engine : string;
    /// <summary>Normalised project-index path plus the .sqlite and -wal signatures.</summary>
    Project: string;
    /// <summary>'' when no library index was used; otherwise its path plus signatures.</summary>
    LibraryDb: string;
    /// <summary>Reads the key for the indexes as they are on disk now.</summary>
    /// <param name="AProjectDb">The project index the run reads.</param>
    /// <param name="ALibraryDbUsed">The library index actually OPENED for the run, or ''
    /// when none was (missing, stale or not wanted) -- the answer differs, so the key must.</param>
    /// <returns>The key. Never raises; an unreadable file contributes '-'.</returns>
    class function Take(const AProjectDb, ALibraryDbUsed: string): TRuleCacheKey; static;
    /// <summary>True when every part of the two keys is identical.</summary>
    /// <param name="AOther">The key to compare with.</param>
    /// <returns>True on an exact match.</returns>
    function SameAs(const AOther: TRuleCacheKey): Boolean;
  end;

  /// <summary>One cached answer: its key, the rule ids it holds, and their findings
  /// over the WHOLE project index.</summary>
  TRuleCacheEntry = record
    /// <summary>What the entry is valid for.</summary>
    Key     : TRuleCacheKey;
    /// <summary>The rules computed into this entry (a subset of CACHED_RULES).</summary>
    RuleIds : TArray<string>;
    /// <summary>Every finding of those rules, every field preserved.</summary>
    Findings: TArray<TLintFinding>;
    /// <summary>True when the entry was computed with ARuleId (case-insensitive).</summary>
    /// <param name="ARuleId">A rule id.</param>
    /// <returns>True when held.</returns>
    function Holds(const ARuleId: string): Boolean;
    /// <summary>The entry's findings of one rule, in their stored order.</summary>
    /// <param name="ARuleId">A rule id.</param>
    /// <returns>The findings; empty when none or not held.</returns>
    function FindingsFor(const ARuleId: string): TArray<TLintFinding>;
  end;

  /// <summary>Location, load and atomic save of rule-cache entries.</summary>
  /// <remarks>Stateless. The directory is DRAGLINT_RULE_CACHE_DIR when set, else
  /// %LOCALAPPDATA%\drag-lint\cache. DRAGLINT_RULE_CACHE=0 turns the cache off for
  /// readers and writers alike.</remarks>
  TRuleCache = class
  public
    /// <summary>False when DRAGLINT_RULE_CACHE is '0'.</summary>
    /// <returns>Whether the cache may be read or written.</returns>
    class function Enabled: Boolean; static;
    /// <summary>The entry file for a project index (one entry per index path).</summary>
    /// <param name="AProjectDb">The project index path.</param>
    /// <returns>The full path of its cache file; '' when no directory can be determined.</returns>
    class function PathFor(const AProjectDb: string): string; static;
    /// <summary>Loads the entry for AProjectDb.</summary>
    /// <param name="AProjectDb">The project index path.</param>
    /// <param name="AEntry">The entry, when the result is True.</param>
    /// <param name="AWhy">Why there is no entry, when the result is False.</param>
    /// <returns>True when a well-formed entry was read. The caller still compares keys.</returns>
    /// <remarks>Never raises: a missing, truncated or malformed file is a miss.</remarks>
    class function TryLoad(const AProjectDb: string; out AEntry: TRuleCacheEntry; out AWhy: string): Boolean; static;
    /// <summary>Writes AEntry for AProjectDb atomically (temp file, then rename over).</summary>
    /// <param name="AProjectDb">The project index path.</param>
    /// <param name="AEntry">The entry to store.</param>
    /// <param name="AWhy">Why nothing was written, when the result is False.</param>
    /// <returns>True when the entry is on disk. Never raises.</returns>
    class function Save(const AProjectDb: string; const AEntry: TRuleCacheEntry; out AWhy: string): Boolean; static;
  end;

implementation

uses
  Winapi.Windows
  , System.IOUtils
  , System.JSON
  , System.Hash
  , System.StrUtils
  ;

const
  CACHE_FORMAT = 1;
  DWORD_BITS   = 32; { a FILETIME / file size arrives as two DWORD halves }
  HASH_HEX_CHARS = 16; { enough to keep index paths apart; the key still names the full path }

{ size:lastwrite-FILETIME of one file, or '-' when it does not exist or cannot be read.

  READ THROUGH A HANDLE, not GetFileAttributesEx: for a file another process holds
  open and is writing -- exactly an index mid-reindex -- the attribute query can
  report a lagging size / last-write time, and a key that does not move is a
  cache that serves an old answer (whole-branch review). A handle opened for
  attributes only, sharing everything, reads the live values and blocks no one. }
function StatSig(const APath: string): string;
var
  H   : THandle;
  Info: TByHandleFileInformation;
begin
  Result:= '-';
  if APath = '' then Exit;
  H:= CreateFile(PChar(APath), FILE_READ_ATTRIBUTES,
                 FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
                 nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if H = INVALID_HANDLE_VALUE then Exit;
  try
    if not GetFileInformationByHandle(H, Info) then Exit;
    Result:= Format('%d:%d', [(Int64(Info.nFileSizeHigh) shl DWORD_BITS) or Info.nFileSizeLow,
                              (Int64(Info.ftLastWriteTime.dwHighDateTime) shl DWORD_BITS) or Info.ftLastWriteTime.dwLowDateTime]);
  finally
    CloseHandle(H);
  end;
end;

{ The -wal as part of the key -- but only when it HOLDS something. SQLite creates
  an empty -wal for every connection, readers included, and deletes it again on
  close, so its last-write time is a per-run timestamp: keyed raw, no two runs
  ever matched (measured: run 2 always `miss (key)`). An empty -wal carries no
  data; a non-empty one holds real uncheckpointed writes and stays in the key. }
function WalSig(const ADb: string): string;
begin
  Result:= StatSig(ADb + '-wal');
  if StartsStr('0:', Result) then Result:= '-';
end;

function IndexSig(const ADb: string): string;
begin
  Result:= LowerCase(ExpandFileName(ADb)) + '|' + StatSig(ADb) + '|' + WalSig(ADb);
end;

class function TRuleCacheKey.Take(const AProjectDb, ALibraryDbUsed: string): TRuleCacheKey;
begin
  Result.Engine := DRAGLINT_VERSION + '|' + StatSig(ParamStr(0));
  Result.Project:= IndexSig(AProjectDb);
  Result.LibraryDb:= if ALibraryDbUsed = '' then '' else IndexSig(ALibraryDbUsed);
end;

function TRuleCacheKey.SameAs(const AOther: TRuleCacheKey): Boolean;
begin
  Result:= (Engine = AOther.Engine) and (Project = AOther.Project) and (LibraryDb = AOther.LibraryDb);
end;

function TRuleCacheEntry.Holds(const ARuleId: string): Boolean;
begin
  Result:= MatchText(ARuleId, RuleIds);
end;

function TRuleCacheEntry.FindingsFor(const ARuleId: string): TArray<TLintFinding>;
begin
  Result:= nil;
  for var F: TLintFinding in Findings do
    if SameText(F.RuleId, ARuleId) then Result:= Result + [F];
end;

class function TRuleCache.Enabled: Boolean;
begin
  Result:= GetEnvironmentVariable('DRAGLINT_RULE_CACHE') <> '0';
end;

class function TRuleCache.PathFor(const AProjectDb: string): string;
begin
  var Dir: string:= GetEnvironmentVariable('DRAGLINT_RULE_CACHE_DIR');
  if Dir = '' then
  begin
    var Local: string:= GetEnvironmentVariable('LOCALAPPDATA');
    if Local = '' then Exit('');
    Dir:= TPath.Combine(Local, 'drag-lint\cache');
  end;
  var H: string:= THashSHA2.GetHashString(LowerCase(ExpandFileName(AProjectDb)));
  Result:= TPath.Combine(Dir, 'rules-' + Copy(H, 1, HASH_HEX_CHARS) + '.json');
end;

function FindingToJson(const F: TLintFinding): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('id'          , TJSONNumber.Create(F.Id));
  Result.AddPair('rule'        , F.RuleId);
  Result.AddPair('file_id'     , TJSONNumber.Create(F.FileId));
  Result.AddPair('file_path'   , F.FilePath);
  Result.AddPair('start_line'  , TJSONNumber.Create(F.StartLine));
  Result.AddPair('start_col'   , TJSONNumber.Create(F.StartCol));
  Result.AddPair('end_line'    , TJSONNumber.Create(F.EndLine));
  Result.AddPair('end_col'     , TJSONNumber.Create(F.EndCol));
  Result.AddPair('severity'    , F.Severity);
  Result.AddPair('message'     , F.Message);
  Result.AddPair('symbol_name' , F.SymbolName);
  Result.AddPair('metric'      , TJSONNumber.Create(F.Metric));
  Result.AddPair('related_file', F.RelatedFile);
  Result.AddPair('related_line', TJSONNumber.Create(F.RelatedLine));
  Result.AddPair('scope_file'  , F.ScopeFile);
  Result.AddPair('scope_line'  , TJSONNumber.Create(F.ScopeLine));
end;

{ Every field is REQUIRED: GetValue<T> raises on a missing one, and TryLoad turns
  that into a miss rather than serving a finding with a silently zeroed field. }
function FindingFromJson(const O: TJSONObject): TLintFinding;
begin
  Result:= Default(TLintFinding);
  Result.Id         := O.GetValue<Int64  >('id'          );
  Result.RuleId     := O.GetValue<string >('rule'        );
  Result.FileId     := O.GetValue<Int64  >('file_id'     );
  Result.FilePath   := O.GetValue<string >('file_path'   );
  Result.StartLine  := O.GetValue<Integer>('start_line'  );
  Result.StartCol   := O.GetValue<Integer>('start_col'   );
  Result.EndLine    := O.GetValue<Integer>('end_line'    );
  Result.EndCol     := O.GetValue<Integer>('end_col'     );
  Result.Severity   := O.GetValue<string >('severity'    );
  Result.Message    := O.GetValue<string >('message'     );
  Result.SymbolName := O.GetValue<string >('symbol_name' );
  Result.Metric     := O.GetValue<Integer>('metric'      );
  Result.RelatedFile:= O.GetValue<string >('related_file');
  Result.RelatedLine:= O.GetValue<Integer>('related_line');
  Result.ScopeFile  := O.GetValue<string >('scope_file'  );
  Result.ScopeLine  := O.GetValue<Integer>('scope_line'  );
end;

class function TRuleCache.TryLoad(const AProjectDb: string; out AEntry: TRuleCacheEntry; out AWhy: string): Boolean;
begin
  Result:= False;
  AEntry:= Default(TRuleCacheEntry);
  AWhy  := '';
  var Path: string:= PathFor(AProjectDb);
  if (Path = '') or not TFile.Exists(Path) then
  begin
    AWhy:= 'none';
    Exit;
  end;
  var Root: TJSONValue:= nil;
  try
    try
      Root:= TJSONObject.ParseJSONValue(TFile.ReadAllText(Path, TEncoding.UTF8), False, True);
      var O: TJSONObject:= Root as TJSONObject;
      if O.GetValue<Integer>('format') <> CACHE_FORMAT then
      begin
        AWhy:= 'format';
        Exit;
      end;
      var K: TJSONObject:= O.GetValue<TJSONObject>('key');
      AEntry.Key.Engine := K.GetValue<string>('engine');
      AEntry.Key.Project:= K.GetValue<string>('project');
      AEntry.Key.LibraryDb:= K.GetValue<string>('library');
      for var R: TJSONValue in O.GetValue<TJSONArray>('rules') do
        AEntry.RuleIds:= AEntry.RuleIds + [R.Value];
      for var V: TJSONValue in O.GetValue<TJSONArray>('findings') do
        AEntry.Findings:= AEntry.Findings + [FindingFromJson(V as TJSONObject)];
      Result:= True;
    except
      { A cache that cannot be read is a MISS by contract (AC8), never an error:
        the run computes live and the next write replaces the file. The reason
        reaches the user through the caller's `rule-cache: miss (<why>)` line. }
      on E: Exception do
      begin
        AEntry:= Default(TRuleCacheEntry);
        AWhy  := 'unreadable: ' + E.ClassName;
        Result:= False;
      end;
    end;
  finally
    Root.Free;
  end;
end;

class function TRuleCache.Save(const AProjectDb: string; const AEntry: TRuleCacheEntry; out AWhy: string): Boolean;
begin
  Result:= False;
  AWhy  := '';
  var Path: string:= PathFor(AProjectDb);
  if Path = '' then
  begin
    AWhy:= 'no cache directory (LOCALAPPDATA unset)';
    Exit;
  end;
  var O: TJSONObject:= TJSONObject.Create;
  try
    O.AddPair('format', TJSONNumber.Create(CACHE_FORMAT));
    var K: TJSONObject:= TJSONObject.Create;
    O.AddPair('key', K);
    K.AddPair('engine' , AEntry.Key.Engine );
    K.AddPair('project', AEntry.Key.Project);
    K.AddPair('library', AEntry.Key.LibraryDb);
    var R: TJSONArray:= TJSONArray.Create;
    O.AddPair('rules', R);
    for var Id: string in AEntry.RuleIds do R.Add(Id);
    var A: TJSONArray:= TJSONArray.Create;
    O.AddPair('findings', A);
    for var F: TLintFinding in AEntry.Findings do A.AddElement(FindingToJson(F));
    { ATOMIC: a concurrent reader sees the old complete file or the new complete
      file, never half of one (AC15). Two racing writers are harmless -- each
      verified its key before writing, and the last rename wins. }
    var Tmp: string:= Path + '.tmp-' + IntToStr(GetCurrentProcessId);
    try
      TDirectory.CreateDirectory(ExtractFileDir(Path));
      TFile.WriteAllText(Tmp, O.ToJSON, TEncoding.UTF8);
      if not MoveFileEx(PChar(Tmp), PChar(Path), MOVEFILE_REPLACE_EXISTING) then
      begin
        AWhy:= 'rename failed: ' + SysErrorMessage(GetLastError);
        DeleteFile(PChar(Tmp));
        Exit;
      end;
      Result:= True;
    except
      { Not writing a cache costs one slow lint later and nothing else; the
        caller prints AWhy as `rule-cache: skipped (<why>)`. }
      on E: Exception do
      begin
        AWhy:= 'write failed: ' + E.Message;
        DeleteFile(PChar(Tmp));
        Result:= False;
      end;
    end;
  finally
    O.Free;
  end;
end;

end.
