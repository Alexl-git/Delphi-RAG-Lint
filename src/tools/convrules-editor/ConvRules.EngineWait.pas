unit ConvRules.EngineWait;

{ The modal "engine is working" window. Runs a long engine call on a worker
  thread, shows elapsed time and the engine's progress lines, and lets the user
  cancel. VCL -- editor-only, OUTSIDE the model tests' compile closure; the pure
  parts it uses live in ConvRules.EngineProgress. }

interface

uses
  ConvRules.EngineProgress
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

implementation

uses
  System.SysUtils
  , System.Classes
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
      procedure CancelClick(Sender: TObject);
      procedure TimerTick(Sender: TObject);
      procedure CloseQueryHandler(Sender: TObject; var CanClose: Boolean);
    public
      constructor CreateFor(const ATitle: string; AWorker: TWorker; AToken: TCancelToken; const AWatch: TStopwatch);
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
  FCancel.Caption:= 'Cancel';
  FCancel.Cancel := True; // Esc
  FCancel.OnClick:= CancelClick;
  FTimer:= TTimer.Create(Self);
  FTimer.Interval:= TICK_MS;
  FTimer.OnTimer := TimerTick;
  OnCloseQuery:= CloseQueryHandler;
  TimerTick(nil);
end;

procedure TEngineWaitForm.CancelClick(Sender: TObject);
begin
  FToken.Cancel;
  FCancel.Enabled:= False;
  FCancel.Caption:= 'Cancelling...';
end;

procedure TEngineWaitForm.TimerTick(Sender: TObject);
var
  P: TEngineProgress;
begin
  FElapsed.Caption:= Format('%d s elapsed', [FWatch.ElapsedMilliseconds div MS_PER_S]);
  if FWorker.TryLatest(P) then
    FProgress.Caption:= ProgressText(P);
  if FWorker.Finished then
    ModalResult:= mrOk;
end;

procedure TEngineWaitForm.CloseQueryHandler(Sender: TObject; var CanClose: Boolean);
begin
  CanClose:= FWorker.Finished;
  if not CanClose then
    CancelClick(nil);
end;

function RunWithProgressDialog(const ATitle: string; const AWork: TStreamingWork): Integer;
var
  Token : TCancelToken;
  Worker: TWorker;
  Form  : TEngineWaitForm;
  Watch : TStopwatch;
  Saved : TCursor;
begin
  Token := TCancelToken.Create;
  Watch := TStopwatch.StartNew;
  Worker:= TWorker.Create(AWork, Token);
  try
    if WaitForSingleObject(Worker.Handle, SHOW_DELAY_MS) <> WAIT_OBJECT_0 then
    begin
      Form:= TEngineWaitForm.CreateFor(ATitle, Worker, Token, Watch);
      try
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
    Result:= Worker.FResult;
    if Worker.FFailed then
      raise Exception.Create(Worker.FError); // dl:ok raise-bare-exception@65c1 -- the worker's exception object cannot cross threads, so its class name rides in the message; the one caller, TEngineAdapter.GetProptree, catches Exception around its runner call and returns it as AError (test engine.proptree.runner.raise.is.error)
  finally
    // Leaving early (a raise in CreateFor/ShowModal, Application.Terminate): stop the
    // engine, or Worker.Free waits out the whole proptree backstop.
    if not Worker.Finished then
      Token.Cancel;
    Worker.Free;
    Token.Free;
  end; // try
end; // function

end.
