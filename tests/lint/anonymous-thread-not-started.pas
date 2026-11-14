unit anonymous_thread_not_started;

{ anonymous-thread-not-started fixture.  HIT marker = rule fires on that line, OK marker = silent. }

interface

uses
  System.Classes, System.Generics.Collections;

procedure Dropped;
procedure AssignedNeverStarted;
procedure InlineNeverStarted;
procedure StartedByChain;
procedure StartedLater;
function  Returned: TThread;
procedure Stored(AList: TList<TThread>);

implementation

procedure Dropped;
begin
  TThread.CreateAnonymousThread( {HIT}
    procedure
    begin
      Sleep(10);
    end);
end;

procedure AssignedNeverStarted;
var
  T: TThread;
begin
  T:= TThread.CreateAnonymousThread( {HIT}
    procedure
    begin
      Sleep(10);
    end);
  T.FreeOnTerminate:= True;
end;

procedure InlineNeverStarted;
begin
  var U := TThread.CreateAnonymousThread( {HIT}
    procedure
    begin
      Sleep(10);
    end);
  U.FreeOnTerminate:= True;
end;

procedure StartedByChain;
begin
  TThread.CreateAnonymousThread( {OK}
    procedure
    begin
      Sleep(10);
    end).Start;
end;

procedure StartedLater;
var
  T: TThread;
begin
  T:= TThread.CreateAnonymousThread( {OK}
    procedure
    begin
      Sleep(10);
    end);
  T.Start;
end;

function Returned: TThread;
begin
  Result:= TThread.CreateAnonymousThread( {OK}
    procedure
    begin
      Sleep(10);
    end);
end;

procedure Stored(AList: TList<TThread>);
var
  T: TThread;
begin
  T:= TThread.CreateAnonymousThread( {OK}
    procedure
    begin
      Sleep(10);
    end);
  AList.Add(T);
end;

end.
