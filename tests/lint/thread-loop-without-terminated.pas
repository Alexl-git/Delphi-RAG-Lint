unit thread_loop_without_terminated;

{ thread-loop-without-terminated fixture.  HIT marker = rule fires on that line, OK marker = silent. }

interface

uses
  System.Classes, System.SysUtils;

type
  TPoller = class(TThread)
  private
    FStop: Boolean;
    procedure Drain;
    procedure Shared;
  protected
    procedure Execute; override;
  public
    procedure Pump;
  end;

  TGood = class(TThread)
  protected
    procedure Execute; override;
  end;

  TNotThread = class
  public
    procedure Execute;
  end;

implementation

procedure TPoller.Execute;
var
  I: Integer;
begin
  while True do {HIT}
  begin
    Sleep(1000);
  end;
  repeat {HIT}
    Sleep(10);
  until False;
  while not FStop do {HIT}
  begin
    Sleep(10);
  end;
  I:= 0;
  while I < 10 do {OK}
    Inc(I);
  Drain;
  Shared;
end;

procedure TPoller.Drain;
begin
  while True do {HIT}
    Sleep(5);
end;

procedure TPoller.Shared;
begin
  while True do {OK}
  begin
    Sleep(5);
    Break;
  end;
end;

procedure TPoller.Pump;
begin
  Shared;
  while True do {OK}
    Sleep(5);
end;

procedure TGood.Execute;
begin
  while not Terminated do {OK}
    Sleep(10);
  while True do {OK}
  begin
    if Terminated then Break;
    Sleep(10);
  end;
  repeat {OK}
    Sleep(10);
  until Terminated;
end;

procedure TNotThread.Execute;
begin
  while True do {OK}
    Sleep(10);
end;

end.
