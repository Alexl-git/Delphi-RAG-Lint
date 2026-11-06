unit uTtForm;

{ Fixture of ui-access-in-thread-typed: thread entry points that are lambdas, bare
  members of a form (the implicit Self) and the routines a thread reaches through
  resolved calls. Every marker is read by run_ui_thread_typed.ps1. }

interface

uses
  System.Classes, System.SysUtils, System.Threading, Vcl.Forms, Vcl.StdCtrls;

type
  TTtForm = class(TForm)
  public
    Label1: TLabel;
    Memo1: TMemo;
    Lst: TStringList;
    FCount: Integer;
    procedure TouchUi;
    procedure TouchBare;
    procedure Pure;
    procedure Guarded;
    procedure SelfMarshalled;
    procedure Go;
    procedure StartNamed;
    procedure Relay;
  end;

  TOtherTask = class
  public
    class procedure Run(const AProc: TProc);
  end;

implementation

procedure TTtForm.TouchUi;
begin
  Label1.Caption := 'written from whoever calls this'; // CONTROL-UIT-HELPER-NOT-ANCHORED
end;

procedure TTtForm.TouchBare;
begin
  Invalidate; // CONTROL-UIT-BARE-OUTSIDE-THREAD
end;

procedure TTtForm.Relay;
begin
  TouchUi;
end;

procedure TTtForm.Pure;
begin
  FCount := FCount + 1;
  Lst.Add('data');
end;

procedure TTtForm.Guarded;
begin
  if TThread.CurrentThread.ThreadID = MainThreadID then
    Label1.Caption := 'guarded';
end;

procedure TTtForm.SelfMarshalled;
begin
  TThread.Synchronize(nil, Relay);
end;

class procedure TOtherTask.Run(const AProc: TProc);
begin
  AProc();
end;

procedure TTtForm.Go;
begin
  Caption := 'still the main thread'; // CONTROL-UIT-MAIN-THREAD-BARE
  Label1.Caption := 'still the main thread'; // CONTROL-UIT-MAIN-THREAD-DOT
  TThread.CreateAnonymousThread(
    procedure
    begin
      Label1.Caption := 'anon thread'; // TRIGGER-UIT-ANON-THREAD
      FCount := 1; // CONTROL-UIT-LAMBDA-PLAIN-FIELD
      Tag := 1; // CONTROL-UIT-BARE-TCOMPONENT-MEMBER
    end).Start;
  TTask.Run(
    procedure
    begin
      Caption := 'bare write'; // TRIGGER-UIT-BARE-WRITE
      Close; // TRIGGER-UIT-BARE-CALL
      Self.Hide; // TRIGGER-UIT-EXPLICIT-SELF
      TouchUi; // TRIGGER-UIT-LAMBDA-HOP
      Pure; // CONTROL-UIT-LAMBDA-HOP-PURE
    end);
  TTask.Create(
    procedure
    begin
      Invalidate; // TRIGGER-UIT-TASK-CREATE
    end).Start;
  TTask.Future<Integer>(
    function: Integer
    begin
      Memo1.Clear; // TRIGGER-UIT-FUTURE
      Result := 1;
    end);
  TParallel.For(0, 3,
    procedure(I: Integer)
    begin
      Memo1.Lines.Add('x'); // TRIGGER-UIT-PARALLEL-FOR-LINES
    end);
  TTask.Run(
    procedure
    begin
      TThread.Synchronize(nil,
        procedure
        begin
          Caption := 'marshalled'; // CONTROL-UIT-NESTED-SYNCHRONIZE
        end);
      TThread.Queue(nil, TouchUi); // CONTROL-UIT-QUEUE-NAMED
    end);
  TOtherTask.Run(
    procedure
    begin
      Caption := 'not a thread start'; // CONTROL-UIT-OTHER-RUN
    end);
end;

procedure TTtForm.StartNamed;
begin
  TTask.Run(TouchUi); // TRIGGER-UIT-NAMED-ENTRY
  TTask.Run(Pure); // CONTROL-UIT-NAMED-ENTRY-PURE
end;

end.
