unit DRagLint.LSP.Deferred;

{ Deferred slow answers (ruling B9c, lane v152 ASYNC).
  Design: docs\superpowers\specs\2026-11-18-deferred-answers-design.md.

  An on-demand answer that a user is WAITING for (the IDE hover popup) is
  split in two: the fast part answers at once with a placeholder line, the
  slow part is computed on a second request for the SAME position and is
  abandoned the moment the user moves on. Batch callers (autodoc, lint-all,
  MCP, the CLI) never announce a hover and keep the full answer in one reply.

  This unit holds only the pure parts -- the per-session slot state machine,
  the protocol constants and the test/measurement switches -- so the state
  rules can be read (and checked) without the 7000-line server around them. }

interface

uses
  System.Diagnostics
  ;

const
  /// <summary>The placeholder line a deferred first answer carries where the
  /// slow sections will go. Clients detect a partial answer by this exact text
  /// (the RAD Studio plugin keeps a copy: DragLint.Plugin.HoverTracker).</summary>
  DEFERRED_PLACEHOLDER = 'computing...';

  /// <summary>The notification a client sends right before a hoverBundle it
  /// can complete in two steps: params are a TextDocumentPositionParams.</summary>
  DEFER_HOVER_METHOD = 'draglint/deferHover';

  /// <summary>LSP RequestCancelled: the reply to a deferred full answer that
  /// was abandoned because the user moved on (or the client cancelled it).</summary>
  LSP_ERR_REQUEST_CANCELLED = -32800;

  /// <summary>Test switch: milliseconds of artificial work injected into the
  /// slow section of a FULL hover bundle, in cancellable slices.</summary>
  ENV_TEST_HOVER_SLOW_MS = 'DRAGLINT_TEST_HOVER_SLOW_MS';

  /// <summary>Measurement switch: when '1', every hover section writes one
  /// 'hover-timing &lt;section&gt; &lt;ms&gt;' line to stderr.</summary>
  ENV_HOVER_TIMING = 'DRAGLINT_HOVER_TIMING';

  /// <summary>Slice length of the injected slow work; bounds how late a
  /// cancellation is noticed inside it.</summary>
  SLOW_SLICE_MS = 20;

type
  /// <summary>What a hoverBundle request should compute, decided by the
  /// session's deferred-hover slot.</summary>
  TDeferredHoverDecision = (
    dhdFull,     { no deferral: the whole answer in one reply (batch callers, old clients) }
    dhdFast,     { the announced first step: fast sections + DEFERRED_PLACEHOLDER }
    dhdComplete  { the second step at the same position: the whole answer, cancellable }
  );

  /// <summary>One session's deferred-hover state: which position was announced,
  /// whether its first step was answered, and whether the running second step
  /// has been abandoned.</summary>
  /// <remarks>
  /// <para>ONE slot per server: a hover is a question about where the pointer
  /// is NOW, so a newer position always supersedes an older one.</para>
  /// <para>Not thread-safe; the LSP loop is single-threaded and so is every
  /// caller (requests served during a yield run on that same thread).</para>
  /// <para>Keys are opaque strings built by HoverKey; two requests mean the
  /// same position exactly when their keys are equal.</para>
  /// </remarks>
  IDeferredHoverSlot = interface
    ['{6C1F4B7E-2D57-4E0B-9A6E-1F3B0C8D5A21}']
    /// <summary>Records a client's announcement that the next hoverBundle at
    /// AKey may be answered in two steps. Supersedes any other position.</summary>
    /// <param name="AKey">HoverKey of the announced position.</param>
    procedure Announce(const AKey: string);
    /// <summary>Decides how a hoverBundle at AKey is answered and advances
    /// the slot: announced -> dhdFast (armed); armed -> dhdComplete; anything
    /// else -> dhdFull. A request for a different position forgets the slot
    /// but does NOT abandon a running second step: only an announcement
    /// (Announce) or CancelRequest does.</summary>
    /// <remarks>Why: the client that announced cancels its own request before
    /// it announces the next position, so the RequestCancelled reply reaches a
    /// dropped callback. An unannounced request elsewhere (the menu hover)
    /// says nothing about the announcing client, whose callback is still live
    /// and would read the error reply as an engine without hoverBundle.</remarks>
    /// <param name="AKey">HoverKey of the request's position.</param>
    /// <returns>The decision for this request.</returns>
    function Decide(const AKey: string): TDeferredHoverDecision;
    /// <summary>Marks the start of a dhdComplete computation answering
    /// request AId (the JSON text of the id).</summary>
    /// <param name="AId">The request id, as JSON text.</param>
    /// <param name="AKey">The position being completed.</param>
    /// <returns>The run's serial (&gt; 0); pass it to Abandoned and EndComplete.</returns>
    /// <remarks>A second step started while another runs (possible only
    /// inside a yield) supersedes it: the older serial reads Abandoned.</remarks>
    function BeginComplete(const AId, AKey: string): Integer;
    /// <summary>Ends run ASerial (finished or abandoned); a stale serial is
    /// ignored, so a superseded run never clears the newer one.</summary>
    /// <param name="ASerial">The serial BeginComplete returned.</param>
    procedure EndComplete(ASerial: Integer);
    /// <summary>$/cancelRequest: abandons the running second step when AId
    /// is its request id; any other id is ignored.</summary>
    /// <param name="AId">The cancelled request id, as JSON text.</param>
    procedure CancelRequest(const AId: string);
    /// <summary>True once run ASerial must stop: cancelled by id, superseded
    /// by an announcement of another position, or replaced by a newer run.</summary>
    /// <param name="ASerial">The serial BeginComplete returned.</param>
    /// <returns>Whether that computation was abandoned.</returns>
    function Abandoned(ASerial: Integer): Boolean;
  end;

/// <summary>Creates an idle deferred-hover slot.</summary>
/// <returns>A new slot; reference-counted, the caller holds the only reference.</returns>
function NewDeferredHoverSlot: IDeferredHoverSlot;

/// <summary>The slot key of a hover position.</summary>
/// <param name="APath">The document path (compared case-insensitively).</param>
/// <param name="ALine0">0-based line.</param>
/// <param name="ACol0">0-based column.</param>
/// <returns>A string equal for exactly the same position.</returns>
function HoverKey(const APath: string; ALine0, ACol0: Integer): string;

/// <summary>Milliseconds of injected slow work (ENV_TEST_HOVER_SLOW_MS), or 0
/// when the switch is unset or not a positive integer.</summary>
/// <returns>The injected delay in ms.</returns>
function InjectedHoverSlowMs: Integer;

/// <summary>When ENV_HOVER_TIMING is '1', writes the time since ASw started as
/// one 'hover-timing &lt;section&gt; &lt;ms&gt;' line to stderr (stdout is the
/// protocol channel and is never used), then restarts ASw, so consecutive calls
/// time consecutive sections.</summary>
/// <param name="ASw">The section stopwatch; restarted on return.</param>
/// <param name="ASection">Section name (no spaces).</param>
procedure LapHoverTiming(var ASw: TStopwatch; const ASection: string);

implementation

uses
  System.SysUtils
  ;

type
  TDeferredHoverSlot = class(TInterfacedObject, IDeferredHoverSlot)
  private
    type
      TSlotState = (ssIdle, ssAnnounced, ssArmed);
    var
      FState    : TSlotState;
      FKey      : string    ;
      FRunId    : string    ;
      FRunKey   : string    ;
      FRunning  : Boolean   ;
      FAbandoned: Boolean   ;
      FRunSerial: Integer   ;
    procedure Supersede(const AKey: string);
  public
    procedure Announce(const AKey: string);
    function Decide(const AKey: string): TDeferredHoverDecision;
    function BeginComplete(const AId, AKey: string): Integer;
    procedure EndComplete(ASerial: Integer);
    procedure CancelRequest(const AId: string);
    function Abandoned(ASerial: Integer): Boolean;
  end;

procedure TDeferredHoverSlot.Supersede(const AKey: string);
begin
  { A question about another position: the running answer is about where the
    pointer WAS. }
  if FRunning and (FRunKey <> AKey) then FAbandoned:= True;
end;

procedure TDeferredHoverSlot.Announce(const AKey: string);
begin
  Supersede(AKey);
  FState:= ssAnnounced;
  FKey  := AKey;
end;

function TDeferredHoverSlot.Decide(const AKey: string): TDeferredHoverDecision;
begin
  { No Supersede here: an UNANNOUNCED hover elsewhere (the menu hover) is not
    the tracker moving on, and abandoning the tracker's run would answer its
    still-live request with an error (see Announce). }
  Result:= dhdFull;
  if FKey <> AKey then
  begin
    { An unannounced position (the menu hover, a batch caller): full answer;
      whatever was pending elsewhere is forgotten. }
    FState:= ssIdle;
    FKey  := '';
    Exit;
  end;
  case FState of
    ssAnnounced:
      begin
        FState:= ssArmed;
        Result:= dhdFast;
      end;
    ssArmed:
      begin
        FState:= ssIdle;
        FKey  := '';
        Result:= dhdComplete;
      end;
  end;
end;

function TDeferredHoverSlot.BeginComplete(const AId, AKey: string): Integer;
begin
  Inc(FRunSerial);
  FRunning  := True ;
  FAbandoned:= False;
  FRunId    := AId  ;
  FRunKey   := AKey ;
  Result    := FRunSerial;
end;

procedure TDeferredHoverSlot.EndComplete(ASerial: Integer);
begin
  if ASerial <> FRunSerial then Exit;
  FRunning  := False;
  FAbandoned:= False;
  FRunId    := '';
  FRunKey   := '';
end;

procedure TDeferredHoverSlot.CancelRequest(const AId: string);
begin
  if FRunning and (AId <> '') and (AId = FRunId) then FAbandoned:= True;
end;

function TDeferredHoverSlot.Abandoned(ASerial: Integer): Boolean;
begin
  Result:= (ASerial <> FRunSerial) or (FRunning and FAbandoned);
end;

function NewDeferredHoverSlot: IDeferredHoverSlot;
begin
  Result:= TDeferredHoverSlot.Create;
end;

function HoverKey(const APath: string; ALine0, ACol0: Integer): string;
begin
  Result:= Format('%s|%d|%d', [AnsiLowerCase(APath), ALine0, ACol0]);
end;

function InjectedHoverSlowMs: Integer;
begin
  Result:= StrToIntDef(GetEnvironmentVariable(ENV_TEST_HOVER_SLOW_MS), 0);
  if Result < 0 then Result:= 0;
end;

function HoverTimingEnabled: Boolean;
begin
  Result:= GetEnvironmentVariable(ENV_HOVER_TIMING) = '1';
end;

procedure ReportHoverTiming(const ASection: string; AMs: Int64);
begin
  if HoverTimingEnabled then Writeln(ErrOutput, 'hover-timing ', ASection, ' ', AMs);
end;

procedure LapHoverTiming(var ASw: TStopwatch; const ASection: string);
begin
  ReportHoverTiming(ASection, ASw.ElapsedMilliseconds);
  ASw:= TStopwatch.StartNew;
end;

end.
