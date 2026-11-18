unit fsRun;

interface

type
  TRun = class
  private
    FSecs: Integer;
  public
    constructor Create;
    procedure Build;
    procedure Peek;
    procedure Maybe(pDo: Boolean);
    procedure CopyFrom(pOther: TRun);
  end;

var
  GUnread: Integer;  { written, never read: SET with the limit no-judged-use }

implementation

constructor TRun.Create;
begin
  inherited Create;
end;

procedure TRun.Build;
begin
  FSecs:= 1;
  Writeln(FSecs);    // USE-SAME
end;

procedure TRun.Peek;
begin
  Writeln(FSecs);    // USE-PEEK
end;

procedure TRun.Maybe(pDo: Boolean);
begin
  if pDo then
    FSecs:= 2;
  Writeln(FSecs);    // USE-COND
end;

procedure TRun.CopyFrom(pOther: TRun);
begin
  FSecs:= 3;
  Writeln(pOther.FSecs);    // USE-OTHER
end;

initialization
  GUnread:= 1;
end.