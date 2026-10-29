unit freeonterminate_then_wait;

{ freeonterminate-then-wait fixture.  HIT marker = rule fires, OK marker = silent. }

interface

uses
  System.Classes;

type
  TOwner = class
  private
    FWorker: TThread;
  public
    procedure Start;
    procedure Stop;
    procedure Fine;
  end;

implementation

procedure LocalWait(AThread: TThread);
var
  T: TThread;
begin
  T:= AThread;
  T.FreeOnTerminate:= True;
  T.WaitFor; {HIT}
end;

procedure LocalFree(AThread: TThread);
var
  T: TThread;
begin
  T:= AThread;
  T.FreeOnTerminate:= True;
  T.Free; {HIT}
end;

procedure LocalFalse(AThread: TThread);
var
  T: TThread;
begin
  T:= AThread;
  T.FreeOnTerminate:= False;
  T.WaitFor; {OK}
end;

procedure LocalReset(AThread: TThread);
var
  T: TThread;
begin
  T:= AThread;
  T.FreeOnTerminate:= True;
  T:= nil;
  T.WaitFor; {OK}
end;

procedure TOwner.Start;
begin
  FWorker.FreeOnTerminate:= True;
end;

procedure TOwner.Stop;
begin
  FWorker.WaitFor; {HIT}
end;

procedure TOwner.Fine;
begin
  Start;
end;

end.
