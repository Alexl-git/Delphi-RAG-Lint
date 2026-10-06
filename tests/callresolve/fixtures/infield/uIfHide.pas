unit uIfHide;

{ Fixture for run_in_class_field_bind.ps1, review round 1: Delphi's NEAREST
  member hides a farther one whatever its kind, and the walk never guesses past
  an ancestor it cannot resolve. }

interface

uses
  uIfAmb1, uIfAmb2;

type
  TProcI = procedure(A: Integer) of object;

  IHasFIp = interface
    function GetFIp: Integer;
    property FIp: Integer read GetFIp;
  end;

  TBaseH = class(TInterfacedObject)
  public
    FHm: Integer;
    FHc: Integer;
    FHp: Integer;
    FHo: Integer;
  end;

  TMidH = class(TBaseH)
  private
    function GetFHp: Integer;
  public
    const FHc = 5;
    procedure FHm(A: Integer);
    property FHp: Integer read GetFHp;
  end;

  TLeafH = class(TMidH, IHasFIp)
  private
    FHo: Integer;
    GShadow: Integer;
    class var FCv: Integer;
    function GetFIp: Integer;
  public
    procedure UseHiding;
    class procedure UseClassVar;
  end;

  TLeafA = class(TAmb)
  public
    procedure UseAmb;
  end;

  TOuterN = class
  public
    type
      TInnerN = class
      public
        FIn: Integer;
        function Get: Integer;
      end;
  end;

  TRecR = record
    FA: Integer;
    function Sum: Integer;
  end;

  TBoxG<T> = class
  public
    FItem: T;
    function Get: T;
  end;

  TIntBox = class(TBoxG<Integer>)
  public
    function Twice: Integer;
  end;

  TLeafHHelper = class helper for TLeafH
  public
    function ReadOwn: Integer;
  end;

var
  GShadow: Integer;
  FIp: Integer;

implementation

function TMidH.GetFHp: Integer;
begin
  Result:= 0;
end;

procedure TMidH.FHm(A: Integer);
begin
end;

function TLeafH.GetFIp: Integer;
begin
  Result:= 0;
end;

procedure TLeafH.UseHiding;
var
  N: Integer;
  P: TProcI;
begin
  P:= FHm; // H-METHOD
  N:= FHc; // H-CONST
  N:= N + FHp; // H-PROP
  N:= N + FHo; // H-OWN
  N:= N + GShadow; // H-GLOBAL
  N:= N + FIp; // H-INTF
  if Assigned(P) then P(N);
end;

class procedure TLeafH.UseClassVar;
var
  N: Integer;
begin
  N:= FCv; // H-CLASSVAR
  FCv:= N;
end;

procedure TLeafA.UseAmb;
var
  N: Integer;
begin
  N:= FAmb; // H-AMBIG
  FAmb:= N;
end;

function TOuterN.TInnerN.Get: Integer;
begin
  Result:= FIn; // H-NESTED
end;

function TRecR.Sum: Integer;
begin
  Result:= FA; // H-RECORD
end;

function TBoxG<T>.Get: T;
begin
  Result:= FItem; // H-GENERIC
end;

function TIntBox.Twice: Integer;
begin
  Result:= FItem * 2; // H-GENERIC-DESC
end;

function TLeafHHelper.ReadOwn: Integer;
begin
  Result:= FHo; // H-HELPER
end;

end.
