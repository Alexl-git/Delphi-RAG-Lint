unit freeonterminate_then_wait;

{ freeonterminate-then-wait fixture.  HIT marker = rule fires, OK marker = silent. }

interface

uses
  System.Classes;

type
  TSelfFreeing = class(TThread)
  public
    constructor Create;
  end;

  TPlain = class(TThread)
  public
    constructor Create;
  end;

  TOwner = class
  private
    FWorker: TThread;
    FSelf: TSelfFreeing;
  public
    procedure Start;
    procedure Stop;
    procedure Fine;
    procedure StopSelf;
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

constructor TSelfFreeing.Create;
begin
  inherited Create(True);
  FreeOnTerminate:= True;
end;

constructor TPlain.Create;
begin
  inherited Create(True);
end;

procedure LocalCtorFot;
var
  W: TSelfFreeing;
begin
  W:= TSelfFreeing.Create;
  W.WaitFor; {HIT}
end;

procedure LocalPlain;
var
  W: TPlain;
begin
  W:= TPlain.Create;
  W.WaitFor; {OK}
end;

procedure TOwner.StopSelf;
begin
  FSelf.Free; {HIT}
end;

end.
