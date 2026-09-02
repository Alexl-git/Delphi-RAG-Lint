unit DragLint.Plugin.DiagnosticCache;

interface

uses
  System.SysUtils
  , System.Classes
  , System.JSON
  , System.Generics.Collections
  , System.SyncObjs
  , DragLint.Plugin.Telemetry
  ; { TEMP debug telemetry }

type
  TDragLintSeverity = (dlsError, dlsWarning, dlsHint, dlsInfo);

  TDragLintDiagnostic = record
    Line    : Integer          ;
    StartCol: Integer          ;
    EndCol  : Integer          ;
    Severity: TDragLintSeverity;
    Source  : string           ;
    Code    : string           ;
    Message : string           ;
  end;

  { WHICH PRODUCER a diagnostic set came from. Two of them publish lint
    findings and they do NOT agree: the LSP's BuildDiagnostics composes the
    .scm rules plus exactly three built-ins, while the out-of-process live
    runner runs the whole scan list. Measured on DataCopy's uFileUtils.pas --
    LSP 11, live runner 45. }
  TDragLintDiagProducer = (dlpLive, dlpLsp);

  TDragLintDiagnosticCache = class
    strict private
      { The LIVE runner's set. }
      FByFile: TDictionary<string, TArray<TDragLintDiagnostic>>;
      { v0.47: compiler findings from "Compile && Diagnose" live in a SEPARATE
      overlay so the per-keystroke live runner (which overwrites FByFile every
      tick) cannot clobber them. GetForFile returns the union of both. }
      FCompilerByFile: TDictionary<string, TArray<TDragLintDiagnostic>>;
      { v1.9: the LSP's publishDiagnostics set, in its OWN overlay.

        WHY. Both producers used to write FByFile, and Update REPLACES it, so
        whichever published last won. The owner saw exactly that and reported it
        as flapping: "at first no icons, then it showed more diagnostics and
        icons appeared, then after refresh it again shows very little". That is
        45 being overwritten by 11.

        Separating them is the same move FCompilerByFile already made, for the
        same reason. It also makes the two sets comparable in the telemetry
        instead of one silently erasing the other. }
      FLspByFile: TDictionary<string, TArray<TDragLintDiagnostic>>;
      FLock     : TCriticalSection                                ;
    public
      constructor Create;
      destructor Destroy; override;
      /// <summary>Replaces ONE PRODUCER'S lint diagnostics for AFilePath from a
      /// publishDiagnostics-shaped params object. Thread-safe.</summary>
      /// <param name="AProducer">Which set to replace. The two producers keep
      /// separate overlays, so an LSP publish can no longer discard the live
      /// runner's richer set (or the reverse).</param>
      procedure Update(const AFilePath: string; AParams: TJSONValue;
        AProducer: TDragLintDiagProducer = dlpLive);
      /// <summary>Replaces the compiler-findings overlay for AFilePath (from
      /// "Compile &amp;&amp; Diagnose"). These persist across live-lint ticks until the
      /// next compile. Thread-safe.</summary>
      procedure SetCompilerFindings(const AFilePath: string; const ADiags: TArray<TDragLintDiagnostic>);
      /// <summary>Clears the entire compiler-findings overlay (every file). Call
      /// before pushing a fresh compile so resolved errors disappear. Thread-safe.</summary>
      procedure ClearAllCompilerFindings;
      /// <summary>Drops every ERROR-severity compiler finding, for every file,
      /// keeping warnings and hints.</summary>
      /// <returns>How many findings were dropped.</returns>
      /// <remarks>
      /// <para>Called when a build completes reporting ZERO errors. That is
      /// proof no unit has a compile error, which is exactly the fact the
      /// overlay cannot otherwise learn: SetCompilerFindings is only called for
      /// files that PRODUCED findings, so a file that was broken, then fixed,
      /// then recompiled CLEAN is absent from the output and keeps its stale
      /// error for the rest of the session.</para>
      /// <para>Reported 2026-08-19: a mistyped unit name in a uses clause left
      /// "Unit 'System.Actitimerons' not found. [F2613]" in the list after the
      /// name had been corrected back to System.Actions.</para>
      /// <para>Warnings and hints are deliberately KEPT. An incremental build
      /// skips units that are up to date and says nothing about them, so
      /// clearing those would erase real findings that nothing has disproved.
      /// A zero-error build disproves errors and nothing else.</para>
      /// </remarks>
      function DropCompilerErrors: Integer;
      /// <summary>All diagnostics for AFilePath: live-lint findings UNION the
      /// compiler-findings overlay. Thread-safe.</summary>
      function GetForFile(const AFilePath: string): TArray<TDragLintDiagnostic>                ;
      function GetForLine(const AFilePath: string; ALine: Integer): TArray<TDragLintDiagnostic>;
      procedure Clear;
  end;

function Cache: TDragLintDiagnosticCache;

implementation

{ E/W/H/I counts for one set. Every cache log line carries this, because
  "12 diagnostics" does not say whether any of them can REACH the gutter -- the
  inline severity filters decide that, and info alone is ~83% of findings. A
  count that shrinks and a count that is merely filtered look identical without
  the breakdown. }
function SevHistogram(const ADiags: TArray<TDragLintDiagnostic>): string;
var
  D                : TDragLintDiagnostic;
  nE, nW, nH, nI   : Integer            ;
begin
  nE:= 0; nW:= 0; nH:= 0; nI:= 0;
  for D in ADiags do
    case D.Severity of
      dlsError  : Inc(nE);
      dlsWarning: Inc(nW);
      dlsHint   : Inc(nH);
      else        Inc(nI);
    end;
  Result:= Format('E%d W%d H%d I%d', [nE, nW, nH, nI]);
end;

function BoolLabel(ACond: Boolean; const AYes, ANo: string): string;
begin
  if ACond then Result:= AYes else Result:= ANo;
end;

var
  GCache: TDragLintDiagnosticCache = nil;

function Cache: TDragLintDiagnosticCache;
begin
  if GCache = nil then GCache:= TDragLintDiagnosticCache.Create;
  Result:= GCache;
end;

constructor TDragLintDiagnosticCache.Create;
begin
  inherited Create;
  FByFile        := TDictionary<string, TArray<TDragLintDiagnostic>>.Create;
  FCompilerByFile:= TDictionary<string, TArray<TDragLintDiagnostic>>.Create;
  FLspByFile     := TDictionary<string, TArray<TDragLintDiagnostic>>.Create;
  FLock:= TCriticalSection.Create;
end;

destructor TDragLintDiagnosticCache.Destroy;
begin
  FLock.Free;
  FLspByFile.Free;
  FCompilerByFile.Free;
  FByFile.Free;
  inherited;
end;

procedure TDragLintDiagnosticCache.Update(const AFilePath: string; AParams: TJSONValue;
  AProducer: TDragLintDiagProducer);
var
  Target  : TDictionary<string, TArray<TDragLintDiagnostic>>;
  Arr     : TArray<TDragLintDiagnostic>;
  D       : TDragLintDiagnostic        ;
  DiagsArr: TJSONArray                 ;
  i       : Integer                    ;
  Obj     : TJSONObject                ;
  RangeObj: TJSONObject                ;
  StartObj: TJSONObject                ;
  EndObj  : TJSONObject                ;
  SevInt  : Integer                    ;
  List    : TList<TDragLintDiagnostic> ;
  Prev    : TArray<TDragLintDiagnostic>;
begin
  if not (AParams is TJSONObject) then Exit;
  if not (AParams as TJSONObject).TryGetValue<TJSONArray>('diagnostics', DiagsArr) then Exit;

  List:= TList<TDragLintDiagnostic>.Create;
  try
    for i:= 0 to DiagsArr.Count - 1 do
    begin
      if not (DiagsArr.Items[i] is TJSONObject) then Continue;
      Obj:= DiagsArr.Items[i] as TJSONObject;

      D.Line    := 0;
      D.StartCol:= 0;
      D.EndCol  := 0;
      D.Severity:= dlsInfo;
      D.Source  := '';
      D.Code    := '';
      D.Message := '';

      if Obj.TryGetValue<TJSONObject>('range', RangeObj) then
      begin
        if RangeObj.TryGetValue<TJSONObject>('start', StartObj) then
        begin
          StartObj.TryGetValue<Integer>('line'     , D.Line    );
          StartObj.TryGetValue<Integer>('character', D.StartCol);
        end;
        if RangeObj.TryGetValue<TJSONObject>('end', EndObj) then EndObj.TryGetValue<Integer>('character', D.EndCol);
      end;

      SevInt:= 4;
      if Obj.TryGetValue<Integer>('severity', SevInt) then
      case SevInt of
        1: D.Severity:= dlsError;
        2: D.Severity:= dlsWarning;
        3: D.Severity:= dlsInfo;
        4: D.Severity:= dlsHint;
      end;

      Obj.TryGetValue<string>('source' , D.Source );
      Obj.TryGetValue<string>('code'   , D.Code   );
      Obj.TryGetValue<string>('message', D.Message);

      if D.EndCol <= D.StartCol then D.EndCol:= D.StartCol + 1;

      List.Add(D);
    end; // for
    Arr:= List.ToArray;
  finally
    List.Free;
  end; // try

  FLock.Enter;
  try
    { WHAT IS BEING REPLACED is the fact this log was missing. Update REPLACES
      the live set wholesale, so a thin publish silently discards a rich one and
      the only visible effect is marks vanishing. Reported 2026-09-01: "at first
      again no icons, then it showed more diagnostic and icon appeared, then
      after refresh it again shows very little messages and no icons". A count
      alone could not distinguish that from a file genuinely having few
      findings -- the BEFORE number is what makes a clobber legible. }
    if AProducer = dlpLsp then Target:= FLspByFile else Target:= FByFile;
    if not Target.TryGetValue(LowerCase(AFilePath), Prev) then Prev:= nil;
    Target.AddOrSetValue(LowerCase(AFilePath), Arr);
  finally
    FLock.Leave;
  end;
  { The SHRANK flag now means what it says. It used to fire whenever the two
    producers took turns, which is not a clobber but two different sets -- and
    that noise is what made the real clobber hard to see. Each producer is now
    compared only against its own previous set. }
  DLT('cache', Format('Update[%s] %s: %d -> %d diag(s)   was[%s] now[%s]%s', [
    BoolLabel(AProducer = dlpLsp, 'lsp', 'live'),
    ExtractFileName(AFilePath), Length(Prev), Length(Arr),
    SevHistogram(Prev), SevHistogram(Arr),
    BoolLabel(Length(Arr) < Length(Prev), '   *** SHRANK -- previous set discarded ***', '')]));
end; // procedure

procedure TDragLintDiagnosticCache.SetCompilerFindings(const AFilePath: string; const ADiags: TArray<TDragLintDiagnostic>);
var
  Prev: TArray<TDragLintDiagnostic>;
begin
  FLock.Enter;
  try
    if not FCompilerByFile.TryGetValue(LowerCase(AFilePath), Prev) then Prev:= nil;
    if Length(ADiags) = 0 then FCompilerByFile.Remove(LowerCase(AFilePath))
    else FCompilerByFile.AddOrSetValue(LowerCase(AFilePath), ADiags);
  finally
    FLock.Leave;
  end;
  DLT('cache', Format('SetCompilerFindings %s: %d -> %d   was[%s] now[%s]', [
    ExtractFileName(AFilePath), Length(Prev), Length(ADiags),
    SevHistogram(Prev), SevHistogram(ADiags)]));
end;

procedure TDragLintDiagnosticCache.ClearAllCompilerFindings;
var
  N: Integer;
begin
  FLock.Enter;
  try
    N:= FCompilerByFile.Count;
    FCompilerByFile.Clear;
  finally
    FLock.Leave;
  end;
  { Logged because this wipes an overlay for EVERY file at once. It was the one
    cache mutation with no telemetry at all, so a compile that cleared the
    overlay and then repopulated only some files looked, in the log, like
    nothing had happened. }
  DLT('cache', Format('ClearAllCompilerFindings -> dropped the overlay for %d file(s)', [N]));
end;

function TDragLintDiagnosticCache.DropCompilerErrors: Integer;
var
  Keys: TArray<string>;
  Key : string        ;
  Arr : TArray<TDragLintDiagnostic>;
  Kept: TArray<TDragLintDiagnostic>;
  D   : TDragLintDiagnostic        ;
begin
  Result:= 0;
  FLock.Enter;
  try
    { Snapshot the keys: the loop reassigns and removes entries, and mutating a
      TDictionary while enumerating it invalidates the enumerator. }
    Keys:= FCompilerByFile.Keys.ToArray;
    for Key in Keys do
    begin
      if not FCompilerByFile.TryGetValue(Key, Arr) then Continue;
      SetLength(Kept, 0);
      for D in Arr do
        if D.Severity = dlsError then Inc(Result)
        else Kept:= Kept + [D];
      if Length(Kept) = Length(Arr) then Continue;   { nothing dropped for this file }
      if Length(Kept) = 0 then FCompilerByFile.Remove(Key)
      else FCompilerByFile.AddOrSetValue(Key, Kept);
    end;
  finally
    FLock.Leave;
  end;
  if Result > 0 then DLT('cache', Format('DropCompilerErrors -> %d dropped (build reported 0 errors)', [Result]));
end;

function TDragLintDiagnosticCache.GetForFile( const AFilePath: string): TArray<TDragLintDiagnostic>;
var
  Key    : string                     ;
  LintArr: TArray<TDragLintDiagnostic>;
  CompArr: TArray<TDragLintDiagnostic>;
begin
  FLock.Enter;
  try
    Key:= LowerCase(AFilePath);
    if not FCompilerByFile.TryGetValue(Key, CompArr) then CompArr:= nil;

    { ONE OWNER FOR THE GUTTER'S LINT CONTENT, and it is the LIVE RUNNER.

      The two lint producers are not peers. The live runner runs the whole scan
      list; the LSP's BuildDiagnostics runs the .scm rules plus three built-ins,
      so its set is a SUBSET -- 11 against 45 on the file this was measured on.
      Unioning them would therefore report the same finding twice wherever they
      overlap, and dropping to the LSP's set whenever it published last is the
      flapping the owner reported.

      So: once the live runner has published for a file, its set IS the lint
      content and the LSP's is ignored. ContainsKey, not Length -- a file the
      live runner found CLEAN is a real answer of zero, and falling back to the
      LSP there would resurrect findings the runner had cleared.

      The LSP set still serves every file the runner has not reached yet, which
      is what keeps marks present at startup instead of blank until the first
      debounce fires. }
    if not FByFile.ContainsKey(Key) then
    begin
      if not FLspByFile.TryGetValue(Key, LintArr) then LintArr:= nil;
    end
    else if not FByFile.TryGetValue(Key, LintArr) then LintArr:= nil;

    if Length(CompArr)      = 0 then Result:= LintArr
    else if Length(LintArr) = 0 then Result:= CompArr
    else Result:= LintArr + CompArr; { union: lint + compiler overlay }
  finally
    FLock.Leave;
  end;
end; // function

function TDragLintDiagnosticCache.GetForLine(const AFilePath: string; ALine: Integer): TArray<TDragLintDiagnostic>;
var
  All : TArray<TDragLintDiagnostic>;
  D   : TDragLintDiagnostic        ;
  List: TList<TDragLintDiagnostic> ;
begin
  All:= GetForFile(AFilePath);
  List:= TList<TDragLintDiagnostic>.Create;
  try
    for D in All do
      if D.Line = ALine then List.Add(D);
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end;

procedure TDragLintDiagnosticCache.Clear;
begin
  FLock.Enter;
  try
    FByFile.Clear;
    FLspByFile.Clear;
    FCompilerByFile.Clear;
  finally
    FLock.Leave;
  end;
end;

initialization

finalization
FreeAndNil(GCache);

end.
