unit thread_use_after_free_on_terminate;

{ thread-use-after-free-on-terminate fixture.  HIT marker = rule fires on that line, OK marker = silent. }

interface

uses
  System.Classes;

procedure UseAfterStart(AThread: TThread);
procedure UseBeforeStart(AThread: TThread);
procedure NoFreeOnTerminate(AThread: TThread);
procedure Reassigned(AThread: TThread);

implementation

procedure UseAfterStart(AThread: TThread);
var
  T: TThread;
begin
  T:= AThread;
  T.FreeOnTerminate:= True;
  T.Start;
  Sleep(T.ThreadID); {HIT}
end;

procedure UseBeforeStart(AThread: TThread);
var
  T: TThread;
begin
  T:= AThread;
  T.FreeOnTerminate:= True;
  Sleep(T.ThreadID); {OK}
  T.Start;
end;

procedure NoFreeOnTerminate(AThread: TThread);
var
  T: TThread;
begin
  T:= AThread;
  T.FreeOnTerminate:= False;
  T.Start;
  Sleep(T.ThreadID); {OK}
end;

procedure Reassigned(AThread: TThread);
var
  T: TThread;
begin
  T:= AThread;
  T.FreeOnTerminate:= True;
  T.Start;
  T:= nil;
  if T <> nil then Sleep(T.ThreadID); {OK}
end;

end.
