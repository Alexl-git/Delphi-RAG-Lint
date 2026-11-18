unit rlWork;

{ check-init fixture recv-local (lane HBRECV, spec 5.6): Init/Run on the SAME object through a local,
  a parameter or Self. Every class declares no constructor, so the constructor model (lane HBFIELDS)
  answers MAY-BE-UNSET no-declared-ctor; the receiver proof decides. Each MAY case has a SET twin that
  differs by one line or one receiver. }

interface

uses
  System.SysUtils;

type
  TLocal = class
  private
    FData: TObject;
  public
    procedure Init;
    procedure Run;
  end;

  TTwo = class
  private
    FData: TObject;
  public
    procedure Init;
    procedure Run;
  end;

  TTwoOk = class
  private
    FData: TObject;
  public
    procedure Init;
    procedure Run;
  end;

  TEsc = class
  private
    FData: TObject;
  public
    procedure Init;
    procedure Run;
  end;

  TEscOk = class
  private
    FData: TObject;
  public
    procedure Init;
    procedure Run;
  end;

  TCond = class
  private
    FData: TObject;
  public
    procedure Init;
    procedure Run;
  end;

  TCondOk = class
  private
    FData: TObject;
  public
    procedure Init;
    procedure Run;
  end;

  TReas = class
  private
    FData: TObject;
  public
    procedure Init;
    procedure Run;
  end;

  TReasOk = class
  private
    FData: TObject;
  public
    procedure Init;
    procedure Run;
  end;

  TParam = class
  private
    FData: TObject;
  public
    procedure Init;
    procedure Run;
  end;

  TParamVar = class
  private
    FData: TObject;
  public
    procedure Init;
    procedure Run;
  end;

  TSelfy = class
  private
    FData: TObject;
  public
    procedure Init;
    procedure Run;
    procedure Go;
  end;

  TSelfyBad = class
  private
    FData: TObject;
  public
    procedure Init;
    procedure Run;
    procedure Go;
  end;

  TVirt = class
  private
    FData: TObject;
  public
    procedure Init; virtual;
    procedure Run;
  end;

  TVirtSub = class(TVirt)
  public
    procedure Init; override;
  end;

  TVirt2 = class
  private
    FData: TObject;
  public
    procedure Init; virtual;
    procedure Run;
  end;

  TVirt2Sub = class(TVirt2)
  public
    procedure Init; override;
  end;

  TClos = class
  private
    FData: TObject;
  public
    procedure Init;
    procedure Run;
  end;

  TClosOk = class
  private
    FData: TObject;
  public
    procedure Init;
    procedure Run;
  end;

  TNoCall = class
  private
    FData: TObject;
  public
    procedure Init;
    procedure Run;
  end;

procedure RunAll(pFlag: Boolean);

implementation

procedure TLocal.Init;
begin
  FData:= TObject.Create;
end;

procedure TLocal.Run;
begin
  FData.ToString;    // USE-LOCAL
end;

procedure TTwo.Init;
begin
  FData:= TObject.Create;
end;

procedure TTwo.Run;
begin
  FData.ToString;    // USE-TWO
end;

procedure TTwoOk.Init;
begin
  FData:= TObject.Create;
end;

procedure TTwoOk.Run;
begin
  FData.ToString;    // USE-TWOOK
end;

procedure TEsc.Init;
begin
  FData:= TObject.Create;
end;

procedure TEsc.Run;
begin
  FData.ToString;    // USE-ESC
end;

procedure TEscOk.Init;
begin
  FData:= TObject.Create;
end;

procedure TEscOk.Run;
begin
  FData.ToString;    // USE-ESCOK
end;

procedure TCond.Init;
begin
  FData:= TObject.Create;
end;

procedure TCond.Run;
begin
  FData.ToString;    // USE-COND
end;

procedure TCondOk.Init;
begin
  FData:= TObject.Create;
end;

procedure TCondOk.Run;
begin
  FData.ToString;    // USE-CONDOK
end;

procedure TReas.Init;
begin
  FData:= TObject.Create;
end;

procedure TReas.Run;
begin
  FData.ToString;    // USE-REAS
end;

procedure TReasOk.Init;
begin
  FData:= TObject.Create;
end;

procedure TReasOk.Run;
begin
  FData.ToString;    // USE-REASOK
end;

procedure TParam.Init;
begin
  FData:= TObject.Create;
end;

procedure TParam.Run;
begin
  FData.ToString;    // USE-PARAM
end;

procedure TParamVar.Init;
begin
  FData:= TObject.Create;
end;

procedure TParamVar.Run;
begin
  FData.ToString;    // USE-PARAMVAR
end;

procedure TSelfy.Init;
begin
  FData:= TObject.Create;
end;

procedure TSelfy.Run;
begin
  FData.ToString;    // USE-SELFY
end;

procedure TSelfy.Go;
begin
  Init;
  Run;
end;

procedure TSelfyBad.Init;
begin
  FData:= TObject.Create;
end;

procedure TSelfyBad.Run;
begin
  FData.ToString;    // USE-SELFYBAD
end;

procedure TSelfyBad.Go;
begin
  Run;
  Init;
end;

procedure TVirt.Init;
begin
  FData:= TObject.Create;
end;

procedure TVirt.Run;
begin
  FData.ToString;    // USE-VIRT
end;

procedure TVirtSub.Init;
begin
end;

procedure TVirt2.Init;
begin
  FData:= TObject.Create;
end;

procedure TVirt2.Run;
begin
  FData.ToString;    // USE-VIRT2
end;

procedure TVirt2Sub.Init;
begin
  inherited Init;
end;

procedure TClos.Init;
begin
  FData:= TObject.Create;
end;

procedure TClos.Run;
begin
  FData.ToString;    // USE-CLOS
end;

procedure TClosOk.Init;
begin
  FData:= TObject.Create;
end;

procedure TClosOk.Run;
begin
  FData.ToString;    // USE-CLOSOK
end;

procedure TNoCall.Init;
begin
  FData:= TObject.Create;
end;

procedure TNoCall.Run;
begin
  FData.ToString;    // USE-NOCALL
end;

{ callers }

procedure SwapEsc(var pX: TEsc);
begin
  pX:= TEsc.Create;
end;

procedure SwapEscOk(var pX: TEscOk);
begin
  pX:= TEscOk.Create;
end;

procedure CaseLocal;
var
  X: TLocal;
begin
  X:= TLocal.Create;
  X.Init;
  X.Run;
end;

procedure CaseTwo;
var
  A, B: TTwo;
begin
  A:= TTwo.Create;
  B:= TTwo.Create;
  A.Init;
  B.Run;    // SITE-TWO
end;

procedure CaseTwoOk;
var
  A, B: TTwoOk;
begin
  A:= TTwoOk.Create;
  B:= TTwoOk.Create;
  A.Init;
  A.Run;
  B.Free;
end;

procedure CaseEsc;
var
  X: TEsc;
begin
  X:= TEsc.Create;
  X.Init;
  SwapEsc(X);    // SITE-ESC
  X.Run;
end;

procedure CaseEscOk;
var
  X, Y: TEscOk;
begin
  X:= TEscOk.Create;
  Y:= TEscOk.Create;
  X.Init;
  SwapEscOk(Y);
  X.Run;
end;

procedure CaseCond(pFlag: Boolean);
var
  X: TCond;
begin
  X:= TCond.Create;
  if pFlag then X.Init;
  X.Run;    // SITE-COND
end;

procedure CaseCondOk(pFlag: Boolean);
var
  X: TCondOk;
begin
  X:= TCondOk.Create;
  X.Init;
  if pFlag then X.Run;
end;

procedure CaseReas;
var
  X: TReas;
begin
  X:= TReas.Create;
  X.Init;
  X:= TReas.Create;    // SITE-REAS
  X.Run;
end;

procedure CaseReasOk;
var
  X: TReasOk;
begin
  X:= TReasOk.Create;
  X:= TReasOk.Create;
  X.Init;
  X.Run;
end;

procedure CaseParam(pX: TParam);
begin
  pX.Init;
  pX.Run;
end;

procedure CaseParamVar(var pX: TParamVar);
begin
  pX.Init;
  pX.Run;    // SITE-PARAMVAR
end;

procedure CaseSelfy;
var
  S: TSelfy;
  T: TSelfyBad;
begin
  S:= TSelfy.Create;
  S.Go;
  T:= TSelfyBad.Create;
  T.Go;    // SITE-SELFYBAD
end;

procedure CaseVirt;
var
  X: TVirt;
  Y: TVirt2;
begin
  X:= TVirt.Create;
  X.Init;
  X.Run;    // SITE-VIRT
  Y:= TVirt2.Create;
  Y.Init;
  Y.Run;
end;

procedure CaseClos;
var
  X: TClos;
  P: TProc;
begin
  X:= TClos.Create;
  X.Init;
  P:= procedure
    begin
      X.Run;    // SITE-CLOS
    end;
  P();
end;

procedure CaseClosOk;
var
  X: TClosOk;
  P: TProc;
begin
  X:= TClosOk.Create;
  X.Init;
  P:= procedure
    begin
    end;
  P();
  X.Run;
end;

procedure RunAll(pFlag: Boolean);
var
  PV: TParamVar;
begin
  CaseLocal;
  CaseTwo;
  CaseTwoOk;
  CaseEsc;
  CaseEscOk;
  CaseCond(pFlag);
  CaseCondOk(pFlag);
  CaseReas;
  CaseReasOk;
  CaseParam(TParam.Create);
  PV:= TParamVar.Create;
  CaseParamVar(PV);
  CaseSelfy;
  CaseVirt;
  CaseClos;
  CaseClosOk;
end;

end.
