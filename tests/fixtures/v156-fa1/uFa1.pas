unit uFa1;

{ Fixture of tests\autotest\run_v156_FA1.ps1 (1.56 lane FA-1, noreturn-contract).
  A line that must report carries the FIRE marker; every other line must stay silent. }

interface

uses
  System.SysUtils, uFa1Other;

type
  TNotify = procedure of object;

  IWorker = interface
    procedure Work;
  end;

  TPlain = class
  public
    procedure Die;
    procedure Cancel; virtual;
    procedure HandleClick(Sender: TObject);
    constructor CreateBroken;
  end;

  TWorker = class(TInterfacedObject, IWorker)
  public
    procedure Work;
  end;

  TDerived = class(TPlain)
  public
    procedure Cancel; override;
  end;

procedure LocalFail; noreturn;

implementation

var
  Count: Integer;

procedure LocalFail;
begin
  raise Exception.Create('local');
end;

{ ---- code after a call that never returns ---- }

procedure AfterCrossUnit(A: Integer);
begin
  if A = 0 then Exit;
  OtherFail('a');
  Count := 1; // FIRE noreturn-contract
end;

procedure AfterMethod(S: TStopper);
begin
  if S = nil then Exit;
  S.Stop('b');
  OtherPlain; // FIRE noreturn-contract
end;

procedure AfterSameUnit(A: Integer);
begin
  if A = 0 then Exit;
  LocalFail;
  Count := 2; // FIRE noreturn-contract
  Count := 3;
end;

procedure AfterRtlByName(A: Integer);
begin
  if A = 0 then Exit;
  RaiseLastOSError;
  Beep; // FIRE noreturn-contract
end;

procedure AfterInBlock(A: Integer);
begin
  if A = 0 then
  begin
    OtherFail('c');
    Inc(Count); // FIRE noreturn-contract
  end;
  Count := 4;
end;

procedure AfterQualified(A: Integer);
begin
  if A = 0 then Exit;
  uFa1Other.OtherFail('d');
  { a comment is not code }
  Beep; // FIRE noreturn-contract
end;

function SilentResultIdiom(A: Integer): Integer;
begin
  if A = 0 then Exit(1);
  OtherFail('e');
  Result := 0;
end;

function SilentOwnNameIdiom(A: Integer): Integer;
begin
  if A = 0 then Exit(1);
  OtherFail('f');
  SilentOwnNameIdiom := 0;
end;

procedure SilentExitIdiom(A: Integer);
begin
  if A = 0 then Exit;
  OtherFail('g');
  Exit;
end;

procedure SilentAfterPlain;
begin
  OtherPlain;
  Count := 6;
end;

procedure SilentBranch(A: Integer);
begin
  if A = 0 then OtherFail('h') else Count := 7;
  Count := 8;
end;

procedure SilentVariable(Handler: TNotify; S: TStopper);
begin
  Handler;
  S.Go;
  Count := 9;
end;

procedure SilentLast(A: Integer);
begin
  if A = 0 then Exit;
  OtherFail('i'); // nothing follows
end;

{ ---- a routine that never returns and does not say so ---- }

procedure AlwaysRaises; // FIRE noreturn-contract
begin
  raise Exception.Create('always');
end;

procedure ViaOther(const AText: string); // FIRE noreturn-contract
begin
  OtherFail(AText);
end;

procedure BothBranches(A: Boolean); // FIRE noreturn-contract
begin
  if A then OtherFail('j') else Abort;
end;

procedure TPlain.Die; // FIRE noreturn-contract
begin
  OtherFail('k');
end;

function NoValue: Integer; // FIRE noreturn-contract
begin
  RaiseLastOSError;
end;

procedure SilentMayReturn(A: Boolean);
begin
  if A then OtherFail('l');
end;

procedure SilentForever;
begin
  while True do Inc(Count);
end;

procedure SilentHandled;
begin
  try
    OtherFail('m');
  except
    on E: Exception do Count := 10;
  end;
end;

procedure SilentSwallowed;
begin
  try
    OtherFail('n');
  except
  end;
end;

procedure TPlain.Cancel;
begin
  OtherFail('o');
end;

procedure TPlain.HandleClick(Sender: TObject);
begin
  OtherFail('p');
end;

constructor TPlain.CreateBroken;
begin
  OtherFail('q');
end;

procedure TWorker.Work;
begin
  OtherFail('r');
end;

procedure TDerived.Cancel;
begin
  OtherFail('s');
end;

end.
