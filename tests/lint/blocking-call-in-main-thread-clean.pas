unit BlockingCallInMainThreadClean;

{ Not a form unit: a console / service helper waits on purpose. }

interface

uses
  Winapi.Windows, System.Classes, System.SyncObjs;

procedure WaitAll(const AEvent: TEvent; AHandle: THandle; AThread: TThread);

implementation

procedure WaitAll(const AEvent: TEvent; AHandle: THandle; AThread: TThread);
begin
  AEvent.WaitFor(INFINITE);
  WaitForSingleObject(AHandle, INFINITE);
  AThread.WaitFor;
end;

end.
