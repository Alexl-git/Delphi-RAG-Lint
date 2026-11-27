unit uMetCalc;

{ Fixture of tests\autotest\run_v156_MET1.ps1 (1.56 lane MET-1): the repeated parameter
  group pLeft / pTop / pWidth occurs in four routines with four names (G-58), pHeight
  joins it in three of them. PairOnly shares only two parameters and is in no group. }

interface

function RectArea(pLeft, pTop, pWidth, pHeight: Integer): Integer;
function RectRight(pLeft, pTop, pWidth: Integer): Integer;
function RectClampedArea(pLeft, pTop, pWidth, pHeight: Integer): Integer;
function RectIsWide(pLeft, pTop, pWidth, pHeight: Integer): Boolean;
function PairOnly(pLeft, pTop: Integer): Integer;
function SumEven(pCount: Integer): Integer;

implementation

uses
  uMetUtil;

function RectArea(pLeft, pTop, pWidth, pHeight: Integer): Integer;
begin
  Result:= pWidth * pHeight;
  if (pLeft < 0) or (pTop < 0) then
    Result:= 0;
end;

function RectRight(pLeft, pTop, pWidth: Integer): Integer;
begin
  Result:= pLeft + pWidth;
  if pTop < 0 then
    Result:= pWidth;
end;

function RectClampedArea(pLeft, pTop, pWidth, pHeight: Integer): Integer;
begin
  Result:= RectArea(pLeft, pTop, Clamp(pWidth, 0, 100), Clamp(pHeight, 0, 100));
end;

function RectIsWide(pLeft, pTop, pWidth, pHeight: Integer): Boolean;
begin
  Result:= (pWidth > pHeight) and (pLeft >= 0) and (pTop >= 0);
end;

function PairOnly(pLeft, pTop: Integer): Integer;
begin
  Result:= pLeft + pTop;
end;

function SumEven(pCount: Integer): Integer;
var
  I: Integer;

  function Step(pIndex: Integer): Integer;
  begin
    if IsEven(pIndex) then
      Result:= pIndex
    else
      Result:= 0;
  end;

begin
  Result:= 0;
  // one loop
  for I:= 1 to pCount do
    Result:= Result + Step(I);
end;

end.
