unit NrTypes;

interface

uses
  System.Types, System.Classes;

const
  CIdx = 3;
  CDefault = 7;

type
  TPoint2 = record
    Alpha: Integer;
    Beta: Integer;
  end;
  TPairs = array[0..1] of TPoint2;
  TBox = record
    Corner: TPoint2;
    Gamma: Integer;
    Pts: array[0..1] of TPoint2;
    Named: TPairs;
  end;
  /// <summary>A second Alpha: only the const's own record type answers.</summary>
  TOtherPt = record
    Alpha: Integer;
    Lat: Integer;
    X: Integer;
  end;
  IDoer = interface
    ['{7C0E6A52-5E67-4C5F-9B65-1B1C7A1E2F11}']
    function Act: Integer;
  end;
  TDoer = class(TInterfacedObject, IDoer)
  public
    function Act: Integer;
  end;
  TBase = class(TInterfacedObject, IDoer)
  private
    FVal: Integer;
    FDoer: IDoer;
    function GetVal: Integer;
    procedure SetVal(const V: Integer);
    function IsStored: Boolean;
    function GetIdx(Index: Integer): Integer;
  protected
    function Twice: Integer; virtual;
    procedure Run; virtual;
    procedure Take(N: Integer); virtual;
    property Val: Integer read GetVal write SetVal stored IsStored default CDefault;
  public
    Count: Integer;
    property Raw: Integer read FVal write FVal;
    property Slot: Integer index CIdx read GetIdx;
    property Doer: IDoer read FDoer implements IDoer;
    function Make(N: Integer): TBase;
  end;
  TKid = class(TBase)
  protected
    function Twice: Integer; override;
    procedure Run; override;
    procedure Take(N: Integer); override;
  end;
  /// <summary>Its own Run: a nearer name `inherited Run` must not bind to.</summary>
  TLibKid = class(TStringList)
  public
    procedure Clear; override;
  end;

const
  COne: TPoint2 = (Alpha: 1; Beta: 2);
  CBox: TBox = (Corner: (Alpha: 3; Beta: 4); Gamma: 5;
    Pts: ((Alpha: 10; Beta: 11), (Alpha: 12; Beta: 13));
    Named: ((Alpha: 14; Beta: 15), (Alpha: 16; Beta: 17)));
  CArr: array[0..1] of TPoint2 = ((Alpha: 6; Beta: 7), (Alpha: 8; Beta: 9));
  CAlias: TPairs = ((Alpha: 18; Beta: 19), (Alpha: 20; Beta: 21));
  COther: TOtherPt = (Alpha: 22; Lat: 23; X: 30);
  CLib: TPoint = (X: 24; Y: 25);

var
  VOne: TPoint2 = (Alpha: 26; Beta: 27);

function MakeA: TBase;
function Use: Integer;

implementation

function TDoer.Act: Integer;
begin
  Result:= 1;
end;

function TBase.GetVal: Integer;
begin
  Result:= FVal;
end;

procedure TBase.SetVal(const V: Integer);
begin
  FVal:= V;
end;

function TBase.IsStored: Boolean;
begin
  Result:= True;
end;

function TBase.GetIdx(Index: Integer): Integer;
begin
  Result:= Index;
end;

function TBase.Twice: Integer;
begin
  Result:= 2;
end;

procedure TBase.Run;
begin
end;

procedure TBase.Take(N: Integer);
begin
  Count:= N;
end;

function TBase.Make(N: Integer): TBase;
begin
  Count:= N;
  Result:= Self;
end;

function TKid.Twice: Integer;
begin
  Result:= inherited Twice + inherited Val;
  inherited Run;
  inherited Take(4);
end;

procedure TKid.Run;
  procedure Run;
  begin
  end;
begin
  Run;
  inherited Run;
  inherited;
  if inherited Twice > 0 then Count:= 1;
end;

procedure TKid.Take(N: Integer);
begin
  inherited Make(N).Count:= N;
  inherited Take(N);
end;

procedure TLibKid.Clear;
begin
  inherited Clear;
end;

function MakeA: TBase;
begin
  Result:= TBase.Create;
end;

function Use: Integer;
const
  CLocal: TPoint2 = (Alpha: 28; Beta: 29);
var
  A: array of Integer;
  X, Y: Integer;
  B: TBase;
begin
  Result:= CLocal.Beta + COne.Alpha + CBox.Corner.Beta + CArr[1].Alpha + CAlias[0].Beta + COther.Lat + CLib.Y + VOne.Alpha;
  B:= MakeA();
  Result:= Result + MakeA().Count;
  MakeA().Count:= 1;
  Result:= Result + B.Make(1).Count;
  SetLength(A, 2);
  for X in A do
    Result:= Result + X;
  for Y in A do
    Result:= Result + 1;
  for var Z in A do
    Result:= Result + Z;
  for var W: Integer in A do
    Result:= Result + W;
  B.Free;
end;

end.
