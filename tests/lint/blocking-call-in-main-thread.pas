unit BlockingCallInMainThread;

interface

uses
  Winapi.Windows, System.Classes, System.SysUtils, System.SyncObjs, System.Threading,
  Vcl.Forms;

type
  TLoader = class(TThread)
  protected
    procedure Execute; override;
  end;

  TMainForm = class(TForm)
    procedure LoadClick(Sender: TObject);
    procedure WaitHandleClick(Sender: TObject);
    procedure TasksClick(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure TimedClick(Sender: TObject);
    procedure BackgroundClick(Sender: TObject);
    procedure ReleaseClick(Sender: TObject);
  private
    FLoader: TLoader;
    FDone: TEvent;
    FHandle: THandle;
    FTask: ITask;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

procedure TLoader.Execute;
var
  Ev: TEvent;
begin
  Ev:= TEvent.Create;
  try
    Ev.WaitFor(INFINITE); // quiet
    WaitForSingleObject(Ev.Handle, INFINITE); // quiet
  finally
    Ev.Free;
  end;
end;

procedure TMainForm.LoadClick(Sender: TObject);
begin
  FLoader:= TLoader.Create(False);
  FLoader.WaitFor; // fires
  FDone.WaitFor(INFINITE); // fires
  FDone.WaitFor; // fires
end;

procedure TMainForm.WaitHandleClick(Sender: TObject);
var
  Handles: array[0..0] of THandle;
begin
  WaitForSingleObject(FHandle, INFINITE); // fires
  Handles[0]:= FHandle;
  WaitForMultipleObjects(1, @Handles[0], True, INFINITE); // fires
  TThread.Sleep(500); // fires
end;

procedure TMainForm.TasksClick(Sender: TObject);
var
  Tasks: TArray<ITask>;
begin
  SetLength(Tasks, 1);
  Tasks[0]:= TTask.Run(procedure begin end);
  TTask.WaitForAll(Tasks); // fires
  TTask.WaitForAny(Tasks); // fires
  FTask.Wait; // fires
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  FLoader.Terminate;
  FLoader.WaitFor; // quiet
  FLoader.Free;
end;

procedure TMainForm.TimedClick(Sender: TObject);
begin
  FDone.WaitFor(50); // quiet
  WaitForSingleObject(FHandle, 100); // quiet
  TTask.WaitForAll([FTask], 200); // quiet
  FTask.Wait(100); // quiet
end;

procedure TMainForm.BackgroundClick(Sender: TObject);
begin
  TTask.Run(
    procedure
    begin
      FDone.WaitFor(INFINITE); // quiet
      WaitForSingleObject(FHandle, INFINITE); // quiet
    end);
end;

procedure TMainForm.ReleaseClick(Sender: TObject);
begin
  FLoader.WaitFor; // quiet
  FreeAndNil(FLoader);
end;

end.
