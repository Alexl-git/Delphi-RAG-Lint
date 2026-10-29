unit missing_const_param;

{ Fixture for missing-const-param (OFF by default).
  Hit: by-value managed-type parameter (string, interface, dynamic array,
  Variant) that is never assigned, never modified through Inc/SetLength/..,
  never address-taken.
  FP shapes kept silent: ordinal/record-free types, const/var/out params,
  assigned params, params used as lhs root (S[1] := ..), params handed to
  modifying intrinsics, @S, virtual/override/message methods, event handlers
  (first param Sender), methods whose address is taken, external. }

interface

type
  TFoo = class
  public
    procedure Hit(S: string);
    procedure HitIntf(Obj: IInterface);
    procedure HitArr(A: TArray<Integer>);
    procedure NoHitConst(const S: string);
    procedure NoHitVar(var S: string);
    procedure NoHitInt(N: Integer);
    procedure NoHitAssigned(S: string);
    procedure NoHitIndexAssigned(S: string);
    procedure NoHitSetLength(A: TArray<Integer>);
    procedure NoHitAddr(S: string);
    procedure NoHitVirtual(S: string); virtual;
    procedure NoHitOverride(S: string); override;
    procedure NoHitHandler(Sender: TObject; S: string);
  end;

implementation

procedure TFoo.Hit(S: string);
begin
  Writeln(Length(S));
end;

procedure TFoo.HitIntf(Obj: IInterface);
begin
  if Obj = nil then Exit;
end;

procedure TFoo.HitArr(A: TArray<Integer>);
begin
  Writeln(Length(A));
end;

procedure TFoo.NoHitConst(const S: string);
begin
  Writeln(S);
end;

procedure TFoo.NoHitVar(var S: string);
begin
  Writeln(S);
end;

procedure TFoo.NoHitInt(N: Integer);
begin
  Writeln(N);
end;

procedure TFoo.NoHitAssigned(S: string);
begin
  S:= S + 'x';
end;

procedure TFoo.NoHitIndexAssigned(S: string);
begin
  S[1]:= 'x';
end;

procedure TFoo.NoHitSetLength(A: TArray<Integer>);
begin
  SetLength(A, 3);
end;

procedure TFoo.NoHitAddr(S: string);
var P: PString;
begin
  P:= @S;
end;

procedure TFoo.NoHitVirtual(S: string);
begin
  Writeln(S);
end;

procedure TFoo.NoHitOverride(S: string);
begin
  Writeln(S);
end;

procedure TFoo.NoHitHandler(Sender: TObject; S: string);
begin
  Writeln(S);
end;

end.