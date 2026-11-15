unit ParallelForSharedWrite;

interface

uses
  System.Classes, System.SysUtils, System.SyncObjs, System.Threading;

type
  TSummer = class
  private
    FTotal: Integer;
    FLock: TCriticalSection;
    FNames: TStringList;
  public
    procedure SumBad(const AValues: TArray<Integer>);
    procedure CountBad(const AValues: TArray<Integer>);
    procedure FieldBad(const AValues: TArray<Integer>);
    procedure TasksInLoopBad(const AValues: TArray<Integer>);
    procedure WhileTasksBad(const AValues: TArray<Integer>);
    procedure PerIndexOk(var AOut: TArray<Integer>; const AValues: TArray<Integer>);
    procedure LocalsOk(const AValues: TArray<Integer>);
    procedure LockedOk(const AValues: TArray<Integer>);
    procedure InterlockedOk(const AValues: TArray<Integer>);
    procedure SynchronizedOk(const AValues: TArray<Integer>);
    procedure SingleTaskOk;
  end;

implementation

procedure TSummer.SumBad(const AValues: TArray<Integer>);
var
  Sum: Integer;
begin
  Sum:= 0;
  TParallel.For(0, High(AValues),
    procedure(I: Integer)
    begin
      Sum:= Sum + AValues[I]; // fires
    end);
  Writeln(Sum);
end;

procedure TSummer.CountBad(const AValues: TArray<Integer>);
var
  Hits: Integer;
begin
  Hits:= 0;
  TParallel.For(0, High(AValues),
    procedure(I: Integer)
    begin
      if AValues[I] > 0 then
        Inc(Hits); // fires
    end);
  Writeln(Hits);
end;

procedure TSummer.FieldBad(const AValues: TArray<Integer>);
begin
  TParallel.For(0, High(AValues),
    procedure(I: Integer)
    begin
      FTotal:= FTotal + AValues[I]; // fires
    end);
end;

procedure TSummer.TasksInLoopBad(const AValues: TArray<Integer>);
var
  Tasks: TArray<ITask>;
  Last : Integer;
  I    : Integer;
begin
  SetLength(Tasks, Length(AValues));
  Last:= 0;
  for I:= 0 to High(AValues) do
    Tasks[I]:= TTask.Run(
      procedure
      begin
        Last:= I; // fires
      end);
  TTask.WaitForAll(Tasks);
  Writeln(Last);
end;

procedure TSummer.WhileTasksBad(const AValues: TArray<Integer>);
var
  Tasks: TArray<ITask>;
  Done : Integer;
  K    : Integer;
begin
  Done:= 0;
  K:= 0;
  while K < Length(AValues) do
  begin
    Tasks:= Tasks + [TTask.Run(
      procedure
      begin
        Dec(Done); // fires
      end)];
    Inc(K);
  end;
  TTask.WaitForAll(Tasks);
end;

procedure TSummer.PerIndexOk(var AOut: TArray<Integer>; const AValues: TArray<Integer>);
var
  Squares: TArray<Integer>;
begin
  SetLength(Squares, Length(AValues));
  TParallel.For(0, High(AValues),
    procedure(I: Integer)
    begin
      Squares[I]:= AValues[I] * AValues[I]; // quiet
    end);
  AOut:= Squares;
end;

procedure TSummer.LocalsOk(const AValues: TArray<Integer>);
begin
  TParallel.For(0, High(AValues),
    procedure(I: Integer)
    var
      Acc: Integer;
    begin
      Acc:= 0; // quiet
      for var J:= 0 to I do
        Acc:= Acc + J; // quiet
      var Twice:= Acc * 2; // quiet
      Twice:= Twice + 1; // quiet
      Writeln(Twice);
    end);
end;

procedure TSummer.LockedOk(const AValues: TArray<Integer>);
var
  Sum: Integer;
begin
  Sum:= 0;
  TParallel.For(0, High(AValues),
    procedure(I: Integer)
    begin
      FLock.Enter;
      try
        Sum:= Sum + AValues[I]; // quiet
        FNames.Add(IntToStr(I));
      finally
        FLock.Leave;
      end;
    end);
  Writeln(Sum);
end;

procedure TSummer.InterlockedOk(const AValues: TArray<Integer>);
var
  Sum: Integer;
begin
  Sum:= 0;
  TParallel.For(0, High(AValues),
    procedure(I: Integer)
    begin
      TInterlocked.Add(Sum, AValues[I]); // quiet
    end);
  Writeln(Sum);
end;

procedure TSummer.SynchronizedOk(const AValues: TArray<Integer>);
var
  Sum: Integer;
begin
  Sum:= 0;
  TParallel.For(0, High(AValues),
    procedure(I: Integer)
    begin
      TThread.Synchronize(nil,
        procedure
        begin
          Sum:= Sum + AValues[I]; // quiet
        end);
    end);
  Writeln(Sum);
end;

procedure TSummer.SingleTaskOk;
var
  Last: Integer;
begin
  Last:= 0;
  TTask.Run(
    procedure
    begin
      Last:= 1; // quiet
    end).Wait;
  Writeln(Last);
end;

end.
