unit FiParity;

interface

uses
  System.SysUtils, System.Classes;

type
  TColor3 = (clRed, clGreen, clBlue);

  IFoo = interface
    procedure Run;
  end;

  IBar<T> = interface
    ['{11111111-2222-3333-4444-555555555555}']
    procedure Put(const pValue: T);
  end;

  Holder = class
  private
    FValue: Integer;
    Count: Integer;
    function GetValue: Integer;
    procedure SetTheValue(pValue: Integer);
  public
    constructor Create;
    destructor Destroy;
    property Value: Integer read GetValue write SetTheValue;
  end;

  TImpl = class(TInterfacedObject, IFoo)
  public
    procedure Run;
  end;

  TDerived = class(TComponent)
  public
    constructor Create(pOwner: TComponent); override;
    destructor Destroy; override;
  end;

procedure W501;
procedure W502;
procedure W503;
procedure W505;
procedure W506;
procedure W507(pFlag: Boolean);
procedure W508;
procedure W509;
procedure W510(pA: Integer);
procedure W511;
procedure W512(pA: Integer);
procedure W513;
procedure W514(const pList: TStringList);
procedure W515(pList: TStringList);
procedure W519;
procedure W520(pA: Integer);
function W521(pA: Integer): Integer;
procedure W528;
procedure W529;
procedure W531(pFoo: IFoo);
procedure W534;
procedure W535(pColor: TColor3);
procedure W536;
procedure O801(pText: string);
procedure O804(pUnused: Integer);
procedure C101;
procedure C102(p1, p2, p3, p4, p5, p6, p7, p8, p9: Integer);
procedure C103;
procedure C108;
procedure C109(pFlag: Boolean);

implementation

resourcestring
  rsNeverUsed = 'never used';

const
  cNeverUsed = 42;

procedure UseFoo(const pFoo: IFoo);
begin
  pFoo.Run;
end;

{ Holder }

constructor Holder.Create;
begin
  FValue := 0;
end;

destructor Holder.Destroy;
begin
  FValue := 0;
end;

function Holder.GetValue: Integer;
begin
  Result := Value;
end;

procedure Holder.SetTheValue(pValue: Integer);
begin
  FValue := pValue;
end;

procedure TImpl.Run;
begin
  WriteLn('run');
end;

constructor TDerived.Create(pOwner: TComponent);
begin
  Tag := 1;
end;

destructor TDerived.Destroy;
begin
  Tag := 0;
end;

procedure W501;
begin
  try
    WriteLn('a');
  except
  end;
end;

procedure W502;
begin
  try
    WriteLn('a');
  finally
  end;
end;

procedure W503;
var
  lX: Integer;
begin
  lX := 1;
  lX := lX;
  WriteLn(lX);
end;

procedure W505;
var
  lX: Integer;
begin
  lX := Random(10);
  if lX > 5 then
  else
    WriteLn(lX);
end;

procedure W506;
var
  lX: Integer;
begin
  lX := Random(10);
  if lX > 5 then
    WriteLn(lX)
  else
  ;
end;

procedure W507(pFlag: Boolean);
begin
  if pFlag then
    WriteLn('same')
  else
    WriteLn('same');
end;

procedure W508;
var
  lX: Integer;
begin
  lX := 1;
  lX := 2;
  WriteLn(lX);
end;

procedure W509;
begin
  Exit;
  WriteLn('never');
end;

procedure W510(pA: Integer);
begin
  if pA = pA then
    WriteLn('always');
end;

procedure W511;
var
  lList: TStringList;
begin
  try
    lList := TStringList.Create;
    lList.Add('a');
  finally
    lList.Free;
  end;
end;

procedure W512(pA: Integer);
begin
  if pA = 1 then
    WriteLn('one')
  else if pA = 1 then
    WriteLn('again');
end;

procedure W513;
begin
  WriteLn(Format('%d %d', [1]));
end;

procedure W514(const pList: TStringList);
var
  I: Integer;
begin
  for I := 0 to pList.Count do
    WriteLn(pList[I]);
end;

procedure W515(pList: TStringList);
begin
  if Assigned(pList) then
    pList.Free;
end;

procedure W519;
begin
end;

procedure W520(pA: Integer);
begin
  if not pA in [1, 2] then
    WriteLn('odd');
end;

function W521(pA: Integer): Integer;
begin
  if pA > 0 then
    Result := pA;
end;

procedure W528;
var
  I: Integer;
begin
  for I := 1 to 3 do
    WriteLn('x');
end;

procedure W529;
begin
  try
    WriteLn('a');
  except
    on E: Exception do
      raise E;
  end;
end;

procedure W531(pFoo: IFoo);
begin
  FreeAndNil(pFoo);
end;

procedure W534;
var
  lImpl: TImpl;
begin
  lImpl := TImpl.Create;
  UseFoo(lImpl);
  lImpl.Free;
end;

procedure W535(pColor: TColor3);
begin
  case pColor of
    clRed: WriteLn('r');
    clGreen: WriteLn('g');
  end;
end;

procedure W536;
begin
  UseFoo(TImpl.Create);
end;

procedure O801(pText: string);
begin
  WriteLn(pText);
end;

procedure O804(pUnused: Integer);
begin
  WriteLn('x');
end;

procedure C101;
begin
  WriteLn(1); WriteLn(2); WriteLn(3); WriteLn(4); WriteLn(5);
  WriteLn(1);
  WriteLn(2);
  WriteLn(3);
  WriteLn(4);
  WriteLn(5);
end;

procedure C102(p1, p2, p3, p4, p5, p6, p7, p8, p9: Integer);
begin
  WriteLn(p1 + p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9);
end;

procedure C103;
var
  a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16: Integer;
begin
  a1 := 1; a2 := a1; a3 := a2; a4 := a3; a5 := a4; a6 := a5; a7 := a6; a8 := a7;
  a9 := a8; a10 := a9; a11 := a10; a12 := a11; a13 := a12; a14 := a13; a15 := a14;
  a16 := a15;
  WriteLn(a16);
end;

procedure C108;
var
  lA, lB: TStringList;
begin
  lA := TStringList.Create;
  lB := TStringList.Create;
  try
    with lA do
      with lB do
        Add('x');
  finally
    lB.Free;
    lA.Free;
  end;
end;

procedure C109(pFlag: Boolean);
begin
  if pFlag = True then
    WriteLn('t');
end;

end.
