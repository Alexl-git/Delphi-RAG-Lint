unit uIndA;

{ 1.56 EXT-C2 fixture: indirect calls through a method-pointer FIELD and a plain procedural VAR.
  Pinned by tests\autotest\run_v156_EXTC2_indirect.ps1 -- line numbers matter, append only. }

interface

type
  TNotify = procedure(Sender: TObject) of object;
  TPlainProc = procedure(AValue: Integer);

  TEmitter = class
  private
    FOnChange: TNotify;
    FOnIdle  : TNotify;
    FUnbound : TNotify;
    FCount   : Integer;
  public
    procedure Bind(AFlag: Boolean);
    procedure Fire;
    procedure FireIdle;
    procedure FireUnbound;
    procedure HandleChange(Sender: TObject);
    procedure HandleIdleA(Sender: TObject);
    procedure HandleIdleB(Sender: TObject);
    procedure NeverBound(Sender: TObject);
    property OnChange: TNotify read FOnChange write FOnChange;
  end;

procedure PlainTarget(AValue: Integer);
procedure PlainOther(AValue: Integer);
procedure BindPlain;
procedure FirePlain;

var
  GHook: TPlainProc;

implementation

procedure PlainTarget(AValue: Integer);
begin
end;

procedure PlainOther(AValue: Integer);
begin
end;

procedure BindPlain;
begin
  GHook:= @PlainTarget;
end;

procedure FirePlain;
begin
  if Assigned(GHook) then GHook(1);
end;

procedure TEmitter.Bind(AFlag: Boolean);
begin
  FOnChange:= HandleChange;
  FOnIdle:= HandleIdleA;
  if AFlag then FOnIdle:= Self.HandleIdleB;
  FUnbound:= nil;
  FCount:= 0;
end;

procedure TEmitter.Fire;
begin
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TEmitter.FireIdle;
begin
  FOnIdle(Self);
end;

procedure TEmitter.FireUnbound;
begin
  if Assigned(FUnbound) then FUnbound(Self);
end;

procedure TEmitter.HandleChange(Sender: TObject);
begin
  Inc(FCount);
end;

procedure TEmitter.HandleIdleA(Sender: TObject);
begin
end;

procedure TEmitter.HandleIdleB(Sender: TObject);
begin
end;

procedure TEmitter.NeverBound(Sender: TObject);
begin
end;

type
  TCompare = function(A, B: Integer): Integer;

var
  GCompare: TCompare;
  GCount  : Integer;

function CmpAsc(A, B: Integer): Integer;
begin
  Result:= A - B;
end;

function CountItems: Integer;
begin
  Result:= 0;
end;

procedure BindCompare;
begin
  GCompare:= CmpAsc;
  GCount:= CountItems;
end;

function UseCompare: Integer;
begin
  Result:= GCompare(1, 2);
end;

end.
