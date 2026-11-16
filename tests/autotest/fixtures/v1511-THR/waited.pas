unit waited;

interface

implementation

uses
  System.Threading;

procedure DoWork;
begin
end;

procedure WaitedDirect;
var
  T: ITask;
begin
  T:= TTask.Run(
    procedure
    begin
      DoWork;
    end);
  T.Wait;
end;

procedure WaitedAll;
var
  A, B: ITask;
begin
  A:= TTask.Run(
    procedure
    begin
      DoWork;
    end);
  B:= TTask.Run(
    procedure
    begin
      DoWork;
    end);
  TTask.WaitForAll([A, B]);
end;

procedure WaitedChained;
begin
  TTask.Run(
    procedure
    begin
      DoWork;
    end).Wait;
end;

procedure NotWaitedAssigned;
var
  T: ITask;
begin
  T:= TTask.Run(
    procedure
    begin
      DoWork;
    end);
  DoWork;
end;

procedure NotWaitedBare;
begin
  TTask.Run(
    procedure
    begin
      DoWork;
    end);
end;

procedure WaitsOtherTask;
var
  T, U: ITask;
begin
  T:= TTask.Run(
    procedure
    begin
      DoWork;
    end);
  U:= TTask.Run(
    procedure
    begin
      DoWork;
    end);
  U.Wait;
end;

end.
