unit ConvRules.EngineWait;

{ The modal "engine is working" window. Runs a long engine call on a worker
  thread, shows elapsed time and the engine's progress lines, and lets the user
  cancel. VCL -- editor-only, OUTSIDE the model tests' compile closure; the pure
  parts it uses live in ConvRules.EngineProgress. }

interface

uses
  System.SysUtils // TFunc<string>: RunWithWaitQuestion's question
  , ConvRules.EngineProgress
  ;

/// <summary>Runs AWork on a worker thread behind a modal progress window.</summary>
/// <param name="ATitle">First line of the window, e.g. "Loading property tree for X".</param>
/// <param name="AWork">The engine call; receives the progress sink and the cancel token.</param>
/// <returns>AWork's result: the engine exit code, or ENGINE_OUTCOME_CANCELLED after Cancel.</returns>
/// <exception cref="Exception">Re-raises, on the caller's thread, anything AWork raised on the worker.</exception>
/// <remarks>Main thread only. The window appears only when AWork is still running after
/// SHOW_DELAY_MS, so a fast call never flashes it. Modal: the editor takes no other
/// input while the call runs, so a second load cannot start inside the first. Cancel,
/// Esc and the window's X all request cancellation; the window closes when the worker
/// has actually finished.</remarks>
function RunWithProgressDialog(const ATitle: string; const AWork: TStreamingWork): Integer;

/// <summary>R2: runs AWork on a worker thread behind the progress window and, once it has
/// run AAskAfterMs, ASKS in the same window whether to keep waiting.</summary>
/// <param name="ATitle">First line of the window.</param>
/// <param name="AShowAfterMs">The window appears only when AWork is still running after this.</param>
/// <param name="AAskAfterMs">When the question appears (elapsed time); Keep waiting hides it
/// and asks again after another AAskAfterMs.</param>
/// <param name="AQuestion">The question text; called on the main thread every tick while the
/// question shows, so it may follow what the worker has learned so far (it must read that
/// under its own lock).</param>
/// <param name="AWork">The engine call; receives the progress sink and the cancel token.</param>
/// <param name="AGaveUp">True when the user chose not to wait (Do not wait, Esc, the X) --
/// the call was cancelled; False when it ended on its own.</param>
/// <returns>AWork's result: the engine exit code, or ENGINE_OUTCOME_CANCELLED after Do not wait.</returns>
/// <exception cref="Exception">Re-raises, on the caller's thread, anything AWork raised on the worker.</exception>
/// <remarks>Main thread only; modal, as RunWithProgressDialog. The engine call keeps running
/// while the question is open; when it ends, the window -- question and all -- closes by
/// itself and the answer is used (owner design 2026-10-25, point 3). The window blocks the
/// editor for at most AShowAfterMs before it appears.</remarks>
function RunWithWaitQuestion(const ATitle: string; AShowAfterMs, AAskAfterMs: Cardinal; const AQuestion: TFunc<string>; const AWork: TStreamingWork; out AGaveUp: Boolean): Integer;

implementation

uses
  System.Classes
  , System.Diagnostics
  , Winapi.Windows
  , Vcl.Forms
  , Vcl.Controls
  , Vcl.StdCtrls
  , Vcl.ExtCtrls
  ;

const
  SHOW_DELAY_MS = 400;
  TICK_MS       = 250;
  WIN_W         = 480;
  WIN_H         = 150;
  MARGIN        = 12;
  LINE_H        = 20;
  BTN_W         = 90;
  BTN_H         = 25;
  MS_PER_S      = 1000;
  QUESTION_H    = 4 * LINE_H; // the wrapped question, below the elapsed line
  QUESTION_Y    = MARGIN + 3 * LINE_H; // under the title, progress and elapsed lines
  KEEP_X        = WIN_W - MARGIN - BTN_W - MARGIN - BTN_W; // Keep waiting, left of Cancel
  CAP_CANCEL    = 'Cancel';
  CAP_NO_WAIT   = 'Do not wait';
  CAP_KEEP      = 'Keep waiting';

type
  TWorker = class(TThread)
    private
      FWork     : TStreamingWork;
      FToken    : TCancelToken;
      FResult   : Integer;
      FFailed   : Boolean;
      FError    : string;
      FLatest   : TEngineProgress;
      FHasLatest: Boolean;
      procedure Publish(const AProgress: TEngineProgress);
    protected
      procedure Execute; override;
    public
      constructor Create(const AWork: TStreamingWork; AToken: TCancelToken);
      function TryLatest(out AProgress: TEngineProgress): Boolean;
  end;

  TEngineWaitForm = class(TForm)
    private
      FElapsed : TLabel;
      FProgress: TLabel;
      FCancel  : TButton;
      FTimer   : TTimer;
      FWorker  : TWorker;
      FToken   : TCancelToken;
      FWatch   : TStopwatch;
      FQuestion: TFunc<string>; // nil = never ask (RunWithProgressDialog)
      FAskAfter: Int64;         // ms between questions
      FNextAsk : Int64;         // elapsed ms at which the question shows next
      FAsking  : Boolean;
      FAskLbl  : TLabel;
      FKeep    : TButton;
      procedure CancelClick(Sender: TObject);
      procedure KeepClick(Sender: TObject);
      procedure ShowQuestion(AShow: Boolean);
      procedure TimerTick(Sender: TObject);
      procedure CloseQueryHandler(Sender: TObject; var CanClose: Boolean);
    public
      constructor CreateFor(const ATitle: string; AWorker: TWorker; AToken: TCancelToken; const AWatch: TStopwatch);
      procedure EnableQuestion(AAskAfterMs: Cardinal; const AQuestion: TFunc<string>);
  end;

{ TWorker }

constructor TWorker.Create(const AWork: TStreamingWork; AToken: TCancelToken);
begin
  FWork := AWork;
  FToken:= AToken;
  inherited Create(False);
end;

procedure TWorker.Publish(const AProgress: TEngineProgress);
begin
  System.TMonitor.Enter(Self); // System.: Vcl.Forms.TMonitor (a display) would shadow it
  try
    FLatest   := AProgress;
    FHasLatest:= True;
  finally
    System.TMonitor.Exit(Self);
  end;
end;

function TWorker.TryLatest(out AProgress: TEngineProgress): Boolean;
begin
  System.TMonitor.Enter(Self); // System.: Vcl.Forms.TMonitor (a display) would shadow it
  try
    AProgress:= FLatest;
    Result   := FHasLatest;
  finally
    System.TMonitor.Exit(Self);
  end;
end;

procedure TWorker.Execute;
begin
  try
    FResult:= FWork(
      procedure(const AProgress: TEngineProgress)
      begin
        Publish(AProgress);
      end, FToken);
  except // dl:ok try-except-swallowed@f9c1 -- not swallowed: FFailed/FError carry it to RunWithProgressDialog, which re-raises it on the caller's thread
    on E: Exception do
    begin
      // Re-raised on the caller's thread by RunWithProgressDialog.
      FFailed:= True;
      FError := E.ClassName + ': ' + E.Message;
    end;
  end; // try
end;

{ TEngineWaitForm }

constructor TEngineWaitForm.CreateFor(const ATitle: string; AWorker: TWorker; AToken: TCancelToken; const AWatch: TStopwatch);
var
  LTitle: TLabel;
begin
  inherited CreateNew(nil);
  FWorker:= AWorker;
  FToken := AToken;
  FWatch := AWatch;
  Caption:= 'drag-lint engine';
  BorderStyle:= bsDialog;
  Position:= poMainFormCenter;
  ClientWidth := WIN_W;
  ClientHeight:= WIN_H;
  LTitle:= TLabel.Create(Self);
  LTitle.Parent:= Self;
  LTitle.SetBounds(MARGIN, MARGIN, WIN_W - 2 * MARGIN, LINE_H);
  LTitle.Caption:= ATitle;
  FProgress:= TLabel.Create(Self);
  FProgress.Parent:= Self;
  FProgress.SetBounds(MARGIN, MARGIN + LINE_H, WIN_W - 2 * MARGIN, LINE_H);
  FProgress.Caption:= 'Waiting for the engine...';
  FElapsed:= TLabel.Create(Self);
  FElapsed.Parent:= Self;
  FElapsed.SetBounds(MARGIN, MARGIN + 2 * LINE_H, WIN_W - 2 * MARGIN, LINE_H);
  FCancel:= TButton.Create(Self);
  FCancel.Parent:= Self;
  FCancel.SetBounds(WIN_W - MARGIN - BTN_W, WIN_H - MARGIN - BTN_H, BTN_W, BTN_H);
  FCancel.Caption:= CAP_CANCEL;
  FCancel.Anchors:= [akRight, akBottom]; // the question grows the window downwards
  FCancel.Cancel := True; // Esc
  FCancel.OnClick:= CancelClick;
  FTimer:= TTimer.Create(Self);
  FTimer.Interval:= TICK_MS;
  FTimer.OnTimer := TimerTick;
  OnCloseQuery:= CloseQueryHandler;
  TimerTick(nil);
end;

procedure TEngineWaitForm.EnableQuestion(AAskAfterMs: Cardinal; const AQuestion: TFunc<string>);
begin
  FQuestion:= AQuestion;
  FAskAfter:= AAskAfterMs;
  FNextAsk := AAskAfterMs;
  FAskLbl:= TLabel.Create(Self);
  FAskLbl.Parent  := Self;
  FAskLbl.AutoSize:= False;
  FAskLbl.WordWrap:= True;
  FAskLbl.SetBounds(MARGIN, QUESTION_Y, WIN_W - 2 * MARGIN, QUESTION_H);
  FAskLbl.Visible := False;
  FKeep:= TButton.Create(Self);
  FKeep.Parent := Self;
  FKeep.SetBounds(KEEP_X, WIN_H - MARGIN - BTN_H, BTN_W, BTN_H);
  FKeep.Anchors:= [akRight, akBottom];
  FKeep.Caption:= CAP_KEEP;
  FKeep.OnClick:= KeepClick;
  FKeep.Visible:= False;
end;

procedure TEngineWaitForm.ShowQuestion(AShow: Boolean);
begin
  FAsking:= AShow;
  if AShow then
    FAskLbl.Caption:= FQuestion();
  ClientHeight    := if AShow then WIN_H + QUESTION_H else WIN_H;
  FAskLbl.Visible := AShow;
  FKeep.Visible   := AShow;
  FKeep.Default   := AShow; // Enter keeps waiting; Esc (FCancel.Cancel) does not wait
  if FCancel.Enabled then
    FCancel.Caption:= if AShow then CAP_NO_WAIT else CAP_CANCEL;
end;

procedure TEngineWaitForm.KeepClick(Sender: TObject);
begin
  ShowQuestion(False);
  FNextAsk:= FWatch.ElapsedMilliseconds + FAskAfter;
end;

procedure TEngineWaitForm.CancelClick(Sender: TObject);
begin
  FToken.Cancel;
  FCancel.Enabled:= False;
  FCancel.Caption:= 'Cancelling...';
  if FKeep <> nil then
    FKeep.Enabled:= False;
end;

procedure TEngineWaitForm.TimerTick(Sender: TObject);
var
  P: TEngineProgress;
begin
  FElapsed.Caption:= Format('%d s elapsed', [FWatch.ElapsedMilliseconds div MS_PER_S]);
  if FWorker.TryLatest(P) then
    FProgress.Caption:= ProgressText(P);
  if FWorker.Finished then
    ModalResult:= mrOk // the answer arrived: an open question closes with the window
  else if Assigned(FQuestion) and not FToken.IsCancelled then
  begin
    if FAsking then
      FAskLbl.Caption:= FQuestion() // the worker may have learned more (the version)
    else if FWatch.ElapsedMilliseconds >= FNextAsk then
      ShowQuestion(True);
  end;
end;

procedure TEngineWaitForm.CloseQueryHandler(Sender: TObject; var CanClose: Boolean);
begin
  CanClose:= FWorker.Finished;
  if not CanClose then
    CancelClick(nil);
end;

// Both public runners: the window, the worker, the cancel. AError = what AWork raised on
// the worker (empty = nothing); the caller raises it on its own thread.
function RunWorkerWindow(const ATitle: string; AShowAfterMs, AAskAfterMs: Cardinal; const AQuestion: TFunc<string>; const AWork: TStreamingWork; out AGaveUp: Boolean; out AError: string): Integer;
var
  Token : TCancelToken;
  Worker: TWorker;
  Form  : TEngineWaitForm;
  Watch : TStopwatch;
  Saved : TCursor;
begin
  AGaveUp:= False;
  AError := '';
  Token := TCancelToken.Create;
  Watch := TStopwatch.StartNew;
  Worker:= TWorker.Create(AWork, Token);
  try
    if WaitForSingleObject(Worker.Handle, AShowAfterMs) <> WAIT_OBJECT_0 then
    begin
      Form:= TEngineWaitForm.CreateFor(ATitle, Worker, Token, Watch);
      try
        if Assigned(AQuestion) then
          Form.EnableQuestion(AAskAfterMs, AQuestion);
        // Finished while the form was being built: showing it now would only flash it.
        if not Worker.Finished then
        begin
          // The caller holds an hourglass; the Cancel button must look clickable.
          Saved:= Screen.Cursor;
          Screen.Cursor:= crDefault;
          try
            Form.ShowModal;
          finally
            Screen.Cursor:= Saved;
          end;
        end;
      finally
        Form.Free;
      end; // try
    end;
    Worker.WaitFor;
    AGaveUp:= Token.IsCancelled; // only the window cancels before this point
    Result:= Worker.FResult;
    if Worker.FFailed then
      AError:= Worker.FError;
  finally
    // Leaving early (a raise in CreateFor/ShowModal, Application.Terminate): stop the
    // engine, or Worker.Free waits out the whole proptree backstop.
    if not Worker.Finished then
      Token.Cancel;
    Worker.Free;
    Token.Free;
  end; // try
end; // function

function RunWithProgressDialog(const ATitle: string; const AWork: TStreamingWork): Integer;
var
  LGaveUp: Boolean;
  LError : string;
begin
  Result:= RunWorkerWindow(ATitle, SHOW_DELAY_MS, 0, nil, AWork, LGaveUp, LError);
  if LError <> '' then
    raise Exception.Create(LError); // dl:ok raise-bare-exception@1693 -- the worker's exception object cannot cross threads, so its class name rides in the message; the one caller, TEngineAdapter.GetProptree, catches Exception around its runner call and returns it as AError (test engine.proptree.runner.raise.is.error)
end;

function RunWithWaitQuestion(const ATitle: string; AShowAfterMs, AAskAfterMs: Cardinal; const AQuestion: TFunc<string>; const AWork: TStreamingWork; out AGaveUp: Boolean): Integer;
var
  LError: string;
begin
  Result:= RunWorkerWindow(ATitle, AShowAfterMs, AAskAfterMs, AQuestion, AWork, AGaveUp, LError);
  if LError <> '' then
    raise Exception.Create(LError); // dl:ok raise-bare-exception@1693 -- as RunWithProgressDialog: the worker's exception cannot cross threads, so its class name rides in the message; the one caller, TConvertTab.ProbeCapabilities, lets it reach the VCL handler (VersionOutput / InfoOutput do not raise)
end;

end.
