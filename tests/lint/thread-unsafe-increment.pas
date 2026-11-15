unit ThreadUnsafeIncrement;

interface

uses
  System.Classes, System.SysUtils, System.SyncObjs, System.Threading;

type
  TWorker = class(TThread)
  private
    FOwnCount: Integer;
    class var FProcessed: Integer;
    function Fetch: Boolean;
  protected
    procedure Execute; override;
  end;

  TLockedWorker = class(TThread)
  private
    FLock: TCriticalSection;
  protected
    procedure Execute; override;
  end;

  TNotAThread = class
  public
    procedure Execute;
  end;

var
  GDone: Integer;
  GBytes: Int64;

threadvar
  TPerThread: Integer;

procedure StartBackground;

implementation

var
  GErrors: Integer;

function TWorker.Fetch: Boolean;
begin
  Result:= not Terminated;
end;

procedure TWorker.Execute;
var
  Local: Integer;
begin
  Local:= 0;
  while not Terminated do
    if Fetch then
    begin
      Inc(GDone); // fires
      GBytes:= GBytes + 1; // fires
      Dec(GErrors); // fires
      Inc(FProcessed, 2); // fires
      GErrors:= GErrors - 1; // fires
      Inc(FOwnCount); // quiet
      Inc(Local); // quiet
      Inc(TPerThread); // quiet
      TInterlocked.Increment(GDone); // quiet
      Synchronize(
        procedure
        begin
          Inc(GDone); // quiet
        end);
      GDone:= 5; // quiet
    end;
end;

procedure TLockedWorker.Execute;
begin
  FLock.Acquire;
  try
    Inc(GDone); // quiet
  finally
    FLock.Release;
  end;
end;

procedure TNotAThread.Execute;
begin
  Inc(GDone); // quiet
end;

procedure StartBackground;
begin
  TTask.Run(
    procedure
    begin
      Inc(GErrors); // fires
    end);
  TThread.CreateAnonymousThread(
    procedure
    begin
      GDone:= GDone + 1; // fires
    end).Start;
  Inc(GDone); // quiet
end;

end.
