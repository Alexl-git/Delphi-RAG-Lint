unit TaskExceptionUnobserved;

interface

uses
  System.Classes, System.SysUtils, System.Threading;

type
  TJobs = class
  private
    FTask: ITask;
    procedure Work;
    procedure SafeWork;
  public
    procedure CreatedAndStarted;
    procedure CreatedLocalNeverWaited;
    procedure MethodRefDiscarded;
    procedure FutureDiscarded;
    procedure CreatedAndWaited;
    procedure KeptInField;
    procedure GuardedBody;
    procedure GuardedMethodRef;
    procedure UnknownBody(const AProc: TProc);
    procedure FutureRead;
    procedure HostRuleCovers;
  end;

implementation

procedure TJobs.Work;
begin
  raise Exception.Create('lost');
end;

procedure TJobs.SafeWork;
begin
  try
    Work;
  except
    on E: Exception do
      Writeln(E.Message);
  end;
end;

procedure TJobs.CreatedAndStarted;
begin
  TTask.Create( // fires
    procedure
    begin
      Work;
    end).Start;
end;

procedure TJobs.CreatedLocalNeverWaited;
var
  T: ITask;
begin
  T:= TTask.Create(Work); // fires
  T.Start;
end;

procedure TJobs.MethodRefDiscarded;
begin
  TTask.Run(Work); // fires
end;

procedure TJobs.FutureDiscarded;
begin
  TTask.Future<Integer>( // fires
    function: Integer
    begin
      Result:= StrToInt('x');
    end);
end;

procedure TJobs.CreatedAndWaited;
var
  T: ITask;
begin
  T:= TTask.Create(Work); // quiet
  T.Start;
  T.Wait;
end;

procedure TJobs.KeptInField;
begin
  FTask:= TTask.Run(Work); // quiet
end;

procedure TJobs.GuardedBody;
begin
  TTask.Create( // quiet
    procedure
    begin
      try
        Work;
      except
        on E: Exception do
          Writeln(E.Message);
      end;
    end).Start;
end;

procedure TJobs.GuardedMethodRef;
begin
  TTask.Run(SafeWork); // quiet
end;

procedure TJobs.UnknownBody(const AProc: TProc);
begin
  TTask.Run(AProc); // quiet
end;

procedure TJobs.FutureRead;
var
  F: IFuture<Integer>;
begin
  F:= TTask.Future<Integer>( // quiet
    function: Integer
    begin
      Result:= 1;
    end);
  Writeln(F.Value);
end;

procedure TJobs.HostRuleCovers;
begin
  TTask.Run( // quiet
    procedure
    begin
      Work;
    end);
end;

end.
