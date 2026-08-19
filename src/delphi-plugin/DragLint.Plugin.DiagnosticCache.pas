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

  TDragLintDiagnosticCache = class
    strict private
      FByFile: TDictionary<string, TArray<TDragLintDiagnostic>>;
      { v0.47: compiler findings from "Compile && Diagnose" live in a SEPARATE
      overlay so the per-keystroke live runner (which overwrites FByFile every
      tick) cannot clobber them. GetForFile returns the union of both. }
      FCompilerByFile: TDictionary<string, TArray<TDragLintDiagnostic>>;
      FLock          : TCriticalSection                                ;
    public
      constructor Create;
      destructor Destroy; override;
      /// <summary>Replaces the live-lint diagnostics for AFilePath from an LSP
      /// publishDiagnostics params object. Thread-safe.</summary>
      procedure Update(const AFilePath: string; AParams: TJSONValue);
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
  FLock:= TCriticalSection.Create;
end;

destructor TDragLintDiagnosticCache.Destroy;
begin
  FLock.Free;
  FCompilerByFile.Free;
  FByFile.Free;
  inherited;
end;

procedure TDragLintDiagnosticCache.Update(const AFilePath: string; AParams: TJSONValue);
var
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
    FByFile.AddOrSetValue(LowerCase(AFilePath), Arr);
  finally
    FLock.Leave;
  end;
  DLT('cache', Format('Update %s -> %d diag(s) [key=%s]', [ExtractFileName(AFilePath), Length(Arr), LowerCase(AFilePath)]));
end; // procedure

procedure TDragLintDiagnosticCache.SetCompilerFindings(const AFilePath: string; const ADiags: TArray<TDragLintDiagnostic>);
begin
  FLock.Enter;
  try
    if Length(ADiags) = 0 then FCompilerByFile.Remove(LowerCase(AFilePath))
    else FCompilerByFile.AddOrSetValue(LowerCase(AFilePath), ADiags);
  finally
    FLock.Leave;
  end;
  DLT('cache', Format('SetCompilerFindings %s -> %d', [ExtractFileName(AFilePath), Length(ADiags)]));
end;

procedure TDragLintDiagnosticCache.ClearAllCompilerFindings;
begin
  FLock.Enter;
  try
    FCompilerByFile.Clear;
  finally
    FLock.Leave;
  end;
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
    if not FByFile        .TryGetValue(Key, LintArr) then LintArr:= nil;
    if not FCompilerByFile.TryGetValue(Key, CompArr) then CompArr:= nil;
    if Length(CompArr)      = 0 then Result:= LintArr
    else if Length(LintArr) = 0 then Result:= CompArr
    else Result:= LintArr + CompArr; { union: live-lint + compiler overlay }
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
    FCompilerByFile.Clear;
  finally
    FLock.Leave;
  end;
end;

initialization

finalization
FreeAndNil(GCache);

end.
