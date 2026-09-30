unit ConvRules.EngineProgress;

{ Pure helpers for a LONG engine call: the engine's stderr progress protocol
  (engine 1.20.6, capability progress_lines), the cancel token shared by the UI
  thread and a worker, and the callback types that let ConvRules.Engine hand a
  call to a progress window without knowing about VCL. No VCL, no process
  spawn -- the model tests link this unit directly. }

interface

uses
  System.SysUtils
  ;

const
  /// <summary>Editor-side exit code: the engine call exceeded its watchdog.</summary>
  ENGINE_EXIT_TIMEOUT = 3;
  /// <summary>Editor-side exit code: the user cancelled; the engine was terminated.</summary>
  ENGINE_EXIT_CANCELLED = 4;
  /// <summary>Seconds between progress lines requested with --progress-interval.</summary>
  PROGRESS_INTERVAL_S = 2;

type
  /// <summary>One parsed `{"progress":{...}}` stderr line.</summary>
  /// <remarks>Expansion runs level by level, so ClassesDone / (ClassesDone +
  /// ClassesQueued) is an honest fraction within the current Depth.</remarks>
  TEngineProgress = record
    /// <summary>elapsed_s.</summary>
    ElapsedS     : Integer;
    /// <summary>verb (proptree / convert-scaffold).</summary>
    Verb         : string;
    /// <summary>class -- the unit-qualified root class.</summary>
    QName        : string;
    /// <summary>depth -- the level being expanded now.</summary>
    Depth        : Integer;
    /// <summary>max_depth -- the depth the call was asked for.</summary>
    MaxDepth     : Integer;
    /// <summary>classes_done.</summary>
    ClassesDone  : Integer;
    /// <summary>classes_queued.</summary>
    ClassesQueued: Integer;
    /// <summary>nodes.</summary>
    Nodes        : Integer;
  end;

  /// <summary>One-way cancel flag shared by the UI thread and a worker thread.</summary>
  /// <remarks>Thread-safe (interlocked); once set it stays set.</remarks>
  TCancelToken = class
    private
      FCancelled: Integer;
    public
      /// <summary>Request cancellation. Idempotent.</summary>
      procedure Cancel;
      /// <summary>True once Cancel has been called on any thread.</summary>
      /// <returns>The flag.</returns>
      function IsCancelled: Boolean;
  end;

  /// <summary>Receives progress. Called on the thread that runs the engine call.</summary>
  TProgressProc = reference to procedure(const AProgress: TEngineProgress);

  /// <summary>A long engine call: runs to completion and returns the exit code;
  /// reports progress through AOnProgress (may be nil) and polls ACancel (may be nil).</summary>
  TStreamingWork = reference to function(const AOnProgress: TProgressProc; const ACancel: TCancelToken): Integer;

  /// <summary>Runs a TStreamingWork, typically behind a progress window; returns its result.</summary>
  TLongCallRunner = reference to function(const ATitle: string; const AWork: TStreamingWork): Integer;

  /// <summary>Accumulates text chunks and hands back complete lines.</summary>
  /// <remarks>A line ends at LF; a CR before it is dropped. A chunk may end mid-line:
  /// the tail is held until the next Feed or Flush. Not thread-safe.</remarks>
  TLineSplitter = class
    private
      FPending: string;
    public
      /// <summary>Append AChunk; call AOnLine for every line it completes, in order.</summary>
      /// <param name="AChunk">Any text, possibly empty or mid-line.</param>
      /// <param name="AOnLine">Receives each complete line without its terminator.</param>
      procedure Feed(const AChunk: string; const AOnLine: TProc<string>);
      /// <summary>Hand back a held partial line, if any, and clear it.</summary>
      /// <param name="AOnLine">Receives the tail; not called when nothing is held.</param>
      procedure Flush(const AOnLine: TProc<string>);
  end;

/// <summary>Parse one stderr line as an engine progress line.</summary>
/// <param name="ALine">The line, surrounding blanks allowed.</param>
/// <param name="AProgress">The parsed values; Default when False.</param>
/// <returns>True only for a JSON object whose single key is "progress" holding an
/// object. Anything else is ordinary stderr text and returns False. Never raises.</returns>
/// <remarks>A field that is missing or of the wrong JSON type (a string or null where
/// an integer belongs, a number or array where a string belongs, a fraction, an
/// integer out of range) reads as 0 / '' and the line is still accepted (True).</remarks>
function TryParseProgressLine(const ALine: string; out AProgress: TEngineProgress): Boolean;

/// <summary>The one-line display, e.g. "TFDQuery -- depth 3 of 5 -- 41 done, 28 queued -- 15 s".</summary>
/// <param name="AProgress">A parsed progress line.</param>
/// <returns>The class's short name (after the last '.'), or the verb when the class is empty.</returns>
function ProgressText(const AProgress: TEngineProgress): string;

implementation

uses
  System.SyncObjs
  , System.JSON
  ;

procedure TCancelToken.Cancel;
begin
  TInterlocked.Exchange(FCancelled, 1);
end;

function TCancelToken.IsCancelled: Boolean;
begin
  Result:= TInterlocked.CompareExchange(FCancelled, 0, 0) = 1;
end;

procedure TLineSplitter.Feed(const AChunk: string; const AOnLine: TProc<string>);
var
  P   : Integer;
  Line: string ;
begin
  FPending:= FPending + AChunk;
  P:= Pos(#10, FPending);
  while P > 0 do
  begin
    Line:= Copy(FPending, 1, P - 1);
    if Line.EndsWith(#13) then
      SetLength(Line, Length(Line) - 1);
    FPending:= Copy(FPending, P + 1, MaxInt);
    AOnLine(Line);
    P:= Pos(#10, FPending);
  end;
end; // procedure

procedure TLineSplitter.Flush(const AOnLine: TProc<string>);
var
  Line: string;
begin
  if FPending = '' then
    Exit;
  Line:= FPending;
  FPending:= '';
  if Line.EndsWith(#13) then
    SetLength(Line, Length(Line) - 1);
  AOnLine(Line);
end;

{ Type-checked field readers. Neither goes through an RTL conversion, so neither
  can raise: a missing or wrong-typed value (string, null, array, object, a
  fraction, an out-of-range integer) reads as 0 / ''. TJSONNumber descends from
  TJSONString, so StrField excludes it explicitly. }
function IntField(const AObj: TJSONObject; const AName: string): Integer;
var
  V: TJSONValue;
begin
  V:= AObj.Values[AName];
  if (V is TJSONNumber) and TryStrToInt(V.Value, Result) then
    Exit;
  Result:= 0;
end;

function StrField(const AObj: TJSONObject; const AName: string): string;
var
  V: TJSONValue;
begin
  V:= AObj.Values[AName];
  if (V is TJSONString) and (V is not TJSONNumber) then
    Result:= V.Value
  else
    Result:= '';
end;

function TryParseProgressLine(const ALine: string; out AProgress: TEngineProgress): Boolean;
var
  Root: TJSONValue ;
  P   : TJSONObject;
  T   : string     ;
begin
  AProgress:= Default(TEngineProgress);
  Result:= False;
  T:= Trim(ALine);
  if not T.StartsWith('{') then
    Exit;
  Root:= TJSONObject.ParseJSONValue(T);
  try
    if not (Root is TJSONObject) or (TJSONObject(Root).Count <> 1)
       or not TJSONObject(Root).TryGetValue<TJSONObject>('progress', P) then
      Exit;
    AProgress.ElapsedS     := IntField(P, 'elapsed_s');
    AProgress.Verb         := StrField(P, 'verb');
    AProgress.QName        := StrField(P, 'class');
    AProgress.Depth        := IntField(P, 'depth');
    AProgress.MaxDepth     := IntField(P, 'max_depth');
    AProgress.ClassesDone  := IntField(P, 'classes_done');
    AProgress.ClassesQueued:= IntField(P, 'classes_queued');
    AProgress.Nodes        := IntField(P, 'nodes');
    Result:= True;
  finally
    Root.Free;
  end; // try
end; // function

function ProgressText(const AProgress: TEngineProgress): string;
var
  Name: string;
begin
  Name:= AProgress.QName;
  if Name = '' then
    Name:= AProgress.Verb
  else if LastDelimiter('.', Name) > 0 then
    Name:= Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  Result:= Format('%s -- depth %d of %d -- %d done, %d queued -- %d s',
    [Name, AProgress.Depth, AProgress.MaxDepth, AProgress.ClassesDone, AProgress.ClassesQueued, AProgress.ElapsedS]);
end;

end.
