unit DragLint.Plugin.LspWriteQueue;

(* Non-blocking outgoing channel to the LSP engine's stdin (2026-10-29).

   WHY. TDragLintLspClient used to WriteFile the engine's stdin from the CALLER's
   thread -- the IDE main thread -- with no timeout, while holding the lock the
   reader thread also needs. An engine that stops READING stdin (busy in a
   13-minute request, hung, paused in a debugger) fills the pipe buffer and the
   next WriteFile never returns: the IDE froze for good, and the reader thread
   blocked on the same lock (docs\INBOX-ide-hang-on-slow-engine.md, section 1).
   Owner rule: "whatever gets stuck in DL must not make the IDE stuck".

   WHAT. Callers hand a complete frame to Enqueue, which only takes a lock, adds
   to a bounded list and signals; it never touches the pipe. ONE writer thread
   owns the pipe and is the only code that can block on it. A full queue drops
   the new frame (Enqueue returns False) instead of waiting. A frame enqueued
   with a coalesce key REPLACES a not-yet-written frame with the same key in
   place -- used for textDocument/didChange, where only the newest buffer of a
   document matters and a stalled engine would otherwise collect one full copy
   of the unit per dwell.

   SHUTDOWN never waits on the pipe either: Destroy cancels the writer's
   blocked WriteFile with CancelSynchronousIo and joins for a bounded time. *)

interface

uses
  System.SysUtils
  , System.Classes
  , System.SyncObjs
  , System.Generics.Collections
  , Winapi.Windows
  ;

type
  /// <summary>Raised-once notice that a write to the pipe failed.</summary>
  /// <param name="ALastError">GetLastError of the failed WriteFile.</param>
  /// <remarks>Called on the WRITER thread, never on the caller's.</remarks>
  TDLPipeErrorProc = reference to procedure(ALastError: DWORD);

  /// <summary>Bounded, coalescing, non-blocking queue of frames written to a
  /// pipe handle by one private writer thread.</summary>
  /// <remarks>Thread-safe: Enqueue / PendingCount / WriteStalledMs may be called
  /// from any thread. Does NOT own AHandle -- the creator closes it, AFTER
  /// freeing this object. Once a write fails the queue is Failed for good and
  /// refuses every later frame.</remarks>
  TDLLspWriteQueue = class
    strict private type
      TFrame = record
        Bytes: TBytes;
        Key  : string;
      end;
    strict private
      FHandle       : THandle            ;
      FCapacity     : Integer            ;
      FFrames       : TList<TFrame>      ;
      FLock         : TCriticalSection   ;
      FWake         : TEvent             ;
      FThread       : TThread            ;
      FOnPipeError  : TDLPipeErrorProc   ;
      FFailed       : Boolean            ;
      FStopping     : Boolean            ;
      FWriting      : Boolean            ;
      FWriteStarted : UInt64             ;
      FDropped      : Integer            ;
      FWritten      : Integer            ;
      FJoinBudgetMs : Cardinal           ;
      function TakeNext(out AFrame: TFrame): Boolean;
      function WriteAll(const ABytes: TBytes; out ALastError: DWORD): Boolean;
      procedure WriterLoop;
      function GetFailed: Boolean;
      function GetDropped: Integer;
      function GetWritten: Integer;
    public
      /// <summary>Starts the writer thread for AHandle.</summary>
      /// <param name="AHandle">Write end of the pipe; not owned.</param>
      /// <param name="ACapacity">Maximum frames waiting to be written; values
      /// below 1 are treated as 1.</param>
      /// <param name="AOnPipeError">Optional; told once when a write fails.</param>
      constructor Create(AHandle: THandle; ACapacity: Integer; const AOnPipeError: TDLPipeErrorProc);

      /// <summary>Stops the writer without waiting on the pipe.</summary>
      /// <remarks>Cancels a WriteFile blocked on a full pipe (CancelSynchronousIo)
      /// and joins for at most JoinBudgetMs. A writer that still has not
      /// left is abandoned together with this object's internals (deliberate
      /// leak) rather than freezing the caller.</remarks>
      destructor Destroy; override;

      /// <summary>Queues one complete frame; never blocks on the pipe.</summary>
      /// <param name="ABytes">The bytes to write, header included.</param>
      /// <param name="ACoalesceKey">When not empty, replaces a waiting frame with
      /// the same key in place instead of adding a new one.</param>
      /// <returns>False when the frame was NOT queued: the queue is full, has
      /// failed, or is stopping.</returns>
      function Enqueue(const ABytes: TBytes; const ACoalesceKey: string = ''): Boolean;

      /// <summary>Frames waiting to be written (excluding one being written).</summary>
      /// <returns>The count.</returns>
      function PendingCount: Integer;

      /// <summary>Milliseconds the CURRENT WriteFile has been blocked, or 0 when
      /// the writer is idle.</summary>
      /// <remarks>A large value means the engine has stopped reading stdin.</remarks>
      /// <returns>Elapsed ms of the write in progress, 0 when none.</returns>
      function WriteStalledMs: UInt64;

      /// <summary>True once a write has failed; the queue refuses everything after.</summary>
      property Failed : Boolean read GetFailed ;
      /// <summary>Frames refused because the queue was full.</summary>
      property Dropped: Integer read GetDropped;
      /// <summary>Frames written completely.</summary>
      property Written: Integer read GetWritten;
      /// <summary>Upper bound in ms on Destroy's join of the writer thread
      /// (default 2000). Set from the caller's remaining stop budget.</summary>
      property JoinBudgetMs: Cardinal read FJoinBudgetMs write FJoinBudgetMs;
  end;

implementation

const
  { Upper bound on Destroy's join, and the slice between CancelSynchronousIo
    retries inside it. }
  JOIN_TOTAL_MS = 2000;
  JOIN_SLICE_MS = 50  ;

type
  TDLLspWriterThread = class(TThread)
    strict private
      FBody: TProc;
    protected
      procedure Execute; override;
    public
      constructor Create(const ABody: TProc);
  end;

constructor TDLLspWriterThread.Create(const ABody: TProc);
begin
  FBody:= ABody;
  FreeOnTerminate:= False;
  inherited Create(False);
end;

procedure TDLLspWriterThread.Execute;
begin
  try
    FBody();
  except
    { The writer is the queue's only consumer; an escape here would end it
      silently and leave Enqueue filling a list nobody drains. Say so. }
    on E: Exception do OutputDebugString(PChar('drag-lint LSP writer thread died: ' + E.ClassName + ': ' + E.Message)); // dl:ok outputdebugstring@b428 -- this unit has no log of its own on purpose (no dependency on the client); a dying writer must still say so somewhere
  end;
end;

{ TDLLspWriteQueue }

constructor TDLLspWriteQueue.Create(AHandle: THandle; ACapacity: Integer; const AOnPipeError: TDLPipeErrorProc);
begin
  inherited Create;
  FHandle     := AHandle;
  FCapacity   := if ACapacity < 1 then 1 else ACapacity;
  FOnPipeError:= AOnPipeError;
  FJoinBudgetMs:= JOIN_TOTAL_MS;
  FFrames     := TList<TFrame>.Create;
  FLock       := TCriticalSection.Create;
  FWake       := TEvent.Create(nil, True, False, '');
  FThread     := TDLLspWriterThread.Create(WriterLoop);
end;

destructor TDLLspWriteQueue.Destroy;
var
  Waited: Cardinal;
  Joined: Boolean;
begin
  FLock.Enter;
  try
    FStopping:= True;
    FFrames.Clear;
  finally
    FLock.Leave;
  end;
  FWake.SetEvent;

  Joined:= False;
  Waited:= 0;
  repeat
    { Repeated, not once: a cancel that lands just BEFORE the writer enters
      WriteFile cancels nothing, and the writer would then block anyway. }
    CancelSynchronousIo(FThread.Handle);
    if WaitForSingleObject(FThread.Handle, JOIN_SLICE_MS) = WAIT_OBJECT_0 then
    begin
      Joined:= True;
      Break;
    end;
    Inc(Waited, JOIN_SLICE_MS);
  until Waited >= FJoinBudgetMs;

  if not Joined then
  begin
    { The writer still references FLock / FFrames / FWake. Freeing them under
      it would turn a stuck pipe into an access violation inside the IDE, so the
      whole object is abandoned instead. Bounded: one per engine restart. }
    Exit;
  end;
  FThread.Free;
  FWake.Free;
  FLock.Free;
  FFrames.Free;
  inherited Destroy;
end;

function TDLLspWriteQueue.Enqueue(const ABytes: TBytes; const ACoalesceKey: string): Boolean;
var
  F: TFrame;
  I: Integer;
begin
  Result:= False;
  FLock.Enter;
  try
    if FFailed or FStopping then Exit;
    if ACoalesceKey <> '' then
      for I:= 0 to FFrames.Count - 1 do
        if FFrames[I].Key = ACoalesceKey then
        begin
          F      := FFrames[I];
          F.Bytes:= ABytes;
          FFrames[I]:= F;
          Exit(True);
        end;
    if FFrames.Count >= FCapacity then
    begin
      Inc(FDropped);
      Exit;
    end;
    F.Bytes:= ABytes;
    F.Key  := ACoalesceKey;
    FFrames.Add(F);
    FWake.SetEvent;
    Result:= True;
  finally
    FLock.Leave;
  end;
end;

function TDLLspWriteQueue.TakeNext(out AFrame: TFrame): Boolean;
begin
  Result:= False;
  AFrame:= Default(TFrame);
  FLock.Enter;
  try
    if FStopping then Exit;
    if FFrames.Count = 0 then
    begin
      FWake.ResetEvent;
      Exit;
    end;
    AFrame:= FFrames[0];
    FFrames.Delete(0);
    FWriting     := True;
    FWriteStarted:= GetTickCount64;
    Result:= True;
  finally
    FLock.Leave;
  end;
end;

function TDLLspWriteQueue.WriteAll(const ABytes: TBytes; out ALastError: DWORD): Boolean;
var
  Offset : Integer;
  Written: DWORD  ;
begin
  ALastError:= 0;
  Offset:= 0;
  while Offset < Length(ABytes) do
  begin
    if not WriteFile(FHandle, ABytes[Offset], DWORD(Length(ABytes) - Offset), Written, nil) then
    begin
      ALastError:= GetLastError;
      Exit(False);
    end;
    if Written = 0 then
    begin
      ALastError:= ERROR_NO_DATA;
      Exit(False);
    end;
    Inc(Offset, Integer(Written));
  end;
  Result:= True;
end;

procedure TDLLspWriteQueue.WriterLoop;
var
  F      : TFrame ;
  Ok     : Boolean;
  LastErr: DWORD  ;
begin
  while True do
  begin
    FWake.WaitFor(INFINITE);
    FLock.Enter;
    try
      if FStopping then Exit;
    finally
      FLock.Leave;
    end;
    if not TakeNext(F) then Continue;

    { THE ONLY PLACE THAT CAN BLOCK ON THE ENGINE -- and no lock is held here. }
    Ok:= WriteAll(F.Bytes, LastErr);

    FLock.Enter;
    try
      FWriting:= False;
      if Ok then Inc(FWritten)
      else
      begin
        FFailed:= True;
        FFrames.Clear;
      end;
    finally
      FLock.Leave;
    end;
    if not Ok then
    begin
      if Assigned(FOnPipeError) then
        try
          FOnPipeError(LastErr);
        except
          on E: Exception do OutputDebugString(PChar('drag-lint LSP pipe-error handler raised: ' + E.Message)); // dl:ok outputdebugstring@1983 -- this unit has no log of its own on purpose (no dependency on the client); a dying writer must still say so somewhere
        end;
      Exit;
    end;
  end; // while
end;

function TDLLspWriteQueue.PendingCount: Integer;
begin
  FLock.Enter;
  try
    Result:= FFrames.Count;
  finally
    FLock.Leave;
  end;
end;

function TDLLspWriteQueue.WriteStalledMs: UInt64;
begin
  FLock.Enter;
  try
    Result:= if FWriting then GetTickCount64 - FWriteStarted else 0;
  finally
    FLock.Leave;
  end;
end;

function TDLLspWriteQueue.GetFailed: Boolean;
begin
  FLock.Enter;
  try
    Result:= FFailed;
  finally
    FLock.Leave;
  end;
end;

function TDLLspWriteQueue.GetDropped: Integer;
begin
  FLock.Enter;
  try
    Result:= FDropped;
  finally
    FLock.Leave;
  end;
end;

function TDLLspWriteQueue.GetWritten: Integer;
begin
  FLock.Enter;
  try
    Result:= FWritten;
  finally
    FLock.Leave;
  end;
end;

end.
