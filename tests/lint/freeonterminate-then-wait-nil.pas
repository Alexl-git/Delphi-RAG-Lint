unit freeonterminate_then_wait_nil;

{ freeonterminate-then-wait, FreeAndNil / DisposeOf forms.  HIT marker = rule fires on that line, OK marker = silent. }

interface

uses
  System.Classes, System.SysUtils;

type
  TSelfFreeing = class(TThread)
  public
    constructor Create;
  end;

  TPlain = class(TThread)
  public
    constructor Create;
  end;

procedure NilAfterFlag(AThread: TThread);
procedure DisposeAfterFlag(AThread: TThread);
procedure NilOfSelfFreeing;
procedure NilOfPlain;
procedure FlagFalse(AThread: TThread);
procedure ResetFirst(AThread: TThread);

implementation

constructor TSelfFreeing.Create;
begin
  inherited Create(True);
  FreeOnTerminate:= True;
end;

constructor TPlain.Create;
begin
  inherited Create(True);
end;

procedure NilAfterFlag(AThread: TThread);
var
  T: TThread;
begin
  T:= AThread;
  T.FreeOnTerminate:= True;
  FreeAndNil(T); {HIT}
end;

procedure DisposeAfterFlag(AThread: TThread);
var
  T: TThread;
begin
  T:= AThread;
  T.FreeOnTerminate:= True;
  T.DisposeOf; {HIT}
end;

procedure NilOfSelfFreeing;
var
  W: TSelfFreeing;
begin
  W:= TSelfFreeing.Create;
  FreeAndNil(W); {HIT}
end;

procedure NilOfPlain;
var
  W: TPlain;
begin
  W:= TPlain.Create;
  FreeAndNil(W); {OK}
end;

procedure FlagFalse(AThread: TThread);
var
  T: TThread;
begin
  T:= AThread;
  T.FreeOnTerminate:= False;
  FreeAndNil(T); {OK}
end;

procedure ResetFirst(AThread: TThread);
var
  T: TThread;
begin
  T:= AThread;
  T.FreeOnTerminate:= True;
  T:= nil;
  FreeAndNil(T); {OK}
end;

end.
