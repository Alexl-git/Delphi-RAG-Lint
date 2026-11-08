unit uQfThreads;

{ Fixture of quit-from-thread: a TThread.Execute body and thread-start lambdas that end the process or
  post WM_QUIT. A TRIGGER-QF line fires, a CONTROL-QF line stays silent, and nothing else fires. }

interface

uses
  System.Classes, System.SysUtils, System.Threading, Winapi.Windows, Vcl.Forms;

type
  TQfPoster = class(TThread)
  protected
    procedure Execute; override;
  end;

  TQfNeverBuilt = class(TThread)
  protected
    procedure Execute; override;
  end;

  TQfNotAThread = class
  public
    procedure Execute;
  end;

procedure StartAll;

implementation

procedure StartAll;
begin
  TQfPoster.Create;
  TThread.CreateAnonymousThread(
    procedure
    begin
      Halt(1); // TRIGGER-QF-ANON-HALT
    end).Start;
  TTask.Run(
    procedure
    begin
      Application.Terminate; // TRIGGER-QF-TASK-TERMINATE
    end);
  TThread.CreateAnonymousThread(
    procedure
    begin
      TThread.Synchronize(nil,
        procedure
        begin
          Application.Terminate; // CONTROL-QF-SYNCHRONIZED
        end);
    end).Start;
  Application.Terminate; // CONTROL-QF-MAIN-THREAD
  PostQuitMessage(0); // CONTROL-QF-MAIN-THREAD-POST
end;

procedure TQfPoster.Execute;
begin
  PostQuitMessage(0); // TRIGGER-QF-POST
  Winapi.Windows.PostQuitMessage(1); // TRIGGER-QF-POST-QUALIFIED
  Application.Terminate; // TRIGGER-QF-TERMINATE
  ExitProcess(2); // TRIGGER-QF-EXIT
  Halt; // TRIGGER-QF-HALT-BARE
  Self.Terminate; // CONTROL-QF-THREAD-TERMINATE
  Synchronize(
    procedure
    begin
      PostQuitMessage(0); // CONTROL-QF-SYNCHRONIZE-LAMBDA
    end);
end;

procedure TQfNeverBuilt.Execute;
begin
  PostQuitMessage(0); // TRIGGER-QF-UNBUILT
end;

procedure TQfNotAThread.Execute;
begin
  PostQuitMessage(0); // CONTROL-QF-NOT-A-THREAD
end;

end.