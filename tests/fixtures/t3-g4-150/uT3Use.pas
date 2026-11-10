unit uT3Use;

interface

uses
  uT3Types;

procedure UseDotted;
function LocalSum: Integer;
function VarSum: Integer;
function NestedSum: Integer;

implementation

const
  CUnit: TT3Rec = (Alpha: 1; Beta: 2);

type
  TT3Runner = class
  end;

procedure UseDotted;
var
  V: uT3Types.TT3Runner;
  W: TT3Runner;
  Y: uT3Use.TT3Runner;
  X: NoSuchUnit.TT3Rec;
  Z: TT3Rec.TT3Rec;
begin
  V := nil;
  W := nil;
  Y := nil;
  V.Go;
end;

function LocalSum: Integer;
const
  CLocal: TT3Rec = (Alpha: 3; Beta: 4);
begin
  Result := CLocal.Alpha + CLocal.Beta;
end;

function VarSum: Integer;
var
  R: TT3Rec;
begin
  R := CUnit;
  Result := R.Alpha + CUnit.Beta;
end;

function NestedSum: Integer;
const
  COuter: TT3Rec = (Alpha: 5; Beta: 6);

  function Inner: Integer;
  begin
    Result := COuter.Alpha;
  end;

begin
  Result := Inner;
end;

end.