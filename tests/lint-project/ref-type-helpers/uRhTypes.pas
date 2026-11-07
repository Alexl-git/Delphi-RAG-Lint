unit uRhTypes;

{ Fixture of run_ref_type_helpers.ps1: the ancestry and the expressions the harness asks about.
  Stand-in classes only, so the fixture needs no library index. }

interface

type
  TRhBase = class
  end;

  TRhMid = class(TRhBase)
  end;

  TRhLeaf = class(TRhMid)
  end;

  TRhOther = class
  end;

  { Derives from a class this project does not declare: its ancestry cannot be followed to the end. }
  TRhLibKid = class(TRhNowhere)
  end;

  { A with-subject whose members shadow the names RhWithProbe uses: Q, FLeaf, Names, and TRhMid,
    a method named like a class, so `TRhMid(1)` inside `with` is a call and not a cast. }
  TRhShadow = class
  public
    Q: TRhOther;
    FLeaf: TRhOther;
    function Names: TRhOther;
    function TRhMid(N: Integer): TRhOther;
  end;

  { A with-subject whose surface cannot be followed: any bare name may be its member. }
  TRhLibSubject = class(TRhNowhere)
  end;

  TRhHolder = class
  public
    FLeaf: TRhLeaf;
    function Make(N: Integer): TRhMid;
    Sub: TRhShadow;
    Sub2: TRhShadow;
    function Names: TRhHolder;
    function Pick(N, M: Integer): TRhHolder;
    procedure SelfProbe;
  end;

function RhFree: TRhHolder;
function RhFree2(A, B: Integer): TRhHolder;
function RhOne(A: Integer): TRhHolder;
procedure RhUse(X: TRhLeaf);
procedure RhProbe;
procedure RhWithProbe;

implementation

procedure RhUse(X: TRhLeaf);
begin
  Assert(X <> nil);
end;

function TRhHolder.Make(N: Integer): TRhMid;
begin
  Result:= nil;
end;

function TRhHolder.Names: TRhHolder;
begin
  Result:= Self;
end;

procedure RhProbe;
var
  H : TRhHolder;
  M : TRhMid;
  Q : TRhLeaf;
begin
  H:= TRhHolder.Create;
  M:= H.FLeaf;
  M:= H.Make(1);
  M:= H.Names().FLeaf;
  M:= H.Names().Make(2);
  RhUse(Q);
  Zip.Zap:= 1;
  { A member read off a call result, every call-rooted receiver shape. }
  M:= RhFree().FLeaf;
  M:= RhFree2(1, 2).FLeaf;
  M:= H.Pick(1, 2).Names().Sub.FLeaf;
  H.Names().FLeaf:= nil;
  M:= H.Names().NoSuch;
  M:= Zip.Make().Zap;
  { The G5 shape keeps its one member-access row. }
  M:= RhOne(1).FLeaf;
end;

function RhFree: TRhHolder;
begin
  Result:= nil;
end;

function RhFree2(A, B: Integer): TRhHolder;
begin
  Result:= nil;
end;

function RhOne(A: Integer): TRhHolder;
begin
  Result:= nil;
end;

function TRhHolder.Pick(N, M: Integer): TRhHolder;
begin
  Result:= Self;
end;

function TRhShadow.Names: TRhOther;
begin
  Result:= nil;
end;

function TRhShadow.TRhMid(N: Integer): TRhOther;
begin
  Result:= nil;
end;

procedure TRhHolder.SelfProbe;
var
  L : TRhLibSubject;
begin
  with L do W13(Self.FLeaf);
  W23(Names().FLeaf);
end;

{ The W<nn>(..) heads are undeclared on purpose: unique handles the harness looks the argument up by. }
procedure RhWithProbe;
var
  H : TRhHolder;
  S : TRhShadow;
  L : TRhLibSubject;
  Z : TRhNowhere2;
  Q : TRhLeaf;
begin
  with S do W01(Q);
  with H do W02(Q);
  with L do W03(Q);
  with Z do W04(Q);
  with S do W05(FLeaf);
  with L do W06(H.FLeaf);
  with S do W07(H.FLeaf);
  with L do W08(TRhLeaf(Q));
  with L do W09(Q as TRhLeaf);
  with H.Sub do W10(Names());
  with L do W11(TRhHolder(Q).FLeaf);
  with L do W12(RhFree().FLeaf);
  with L do W14(TRhLeaf.Create);
  with L do W15(RhFree());
  with H do W17(Names().FLeaf);
  with S do W18(TRhLeaf(Q));
  with S do W20(TRhMid(1));
  with TRhShadow(Q) do W21(1);
  with L, TRhHolder(Q) do W22(1);
  W99(Q);
end;

end.
