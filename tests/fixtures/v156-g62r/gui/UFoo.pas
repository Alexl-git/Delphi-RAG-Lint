unit UFoo;

interface

type
  TFoo = class
  public
    procedure Greet;
    procedure Wrap;
    procedure Quiet;
    procedure Ping;
    procedure Pong;
    procedure Loop1;
    procedure Loop2;
  end;

procedure ShowDone;

implementation

uses
  Vcl.Dialogs;

procedure ShowDone;
begin
  ShowMessage('done');
end;

procedure TFoo.Greet;
begin
  ShowMessage('hello');
end;

procedure TFoo.Wrap;
begin
  Greet;
end;

procedure TFoo.Quiet;
begin
  FillChar(Self, 0, 0);
end;

procedure TFoo.Ping;
begin
  Pong;
end;

procedure TFoo.Pong;
begin
  Ping;
  ShowMessage('pong');
end;

procedure TFoo.Loop1;
begin
  Loop2;
end;

procedure TFoo.Loop2;
begin
  Loop1;
end;

end.
