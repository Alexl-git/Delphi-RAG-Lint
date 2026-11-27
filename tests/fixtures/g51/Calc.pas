unit Calc;

interface

type
  TCalc = class
  public
    function Branchy(pValue: Integer): Integer;
    function Middling(pValue: Integer): Integer;
  end;

function Simple(pValue: Integer): Integer;
function Untracked(pValue: Integer): Integer;

implementation

function Simple(pValue: Integer): Integer;
begin
  Result:= pValue + 1;
end;

function Untracked(pValue: Integer): Integer;
begin
  if pValue > 0 then
    Result:= 1
  else
    Result:= 0;
end;

function TCalc.Branchy(pValue: Integer): Integer;
begin
  Result:= 0;
  if pValue > 1 then
    Inc(Result);
  if pValue > 2 then
    Inc(Result);
  if pValue > 3 then
    Inc(Result);
  if pValue > 4 then
    Inc(Result);
  if pValue > 5 then
    Inc(Result);
end;

function TCalc.Middling(pValue: Integer): Integer;
begin
  Result:= 0;
  if pValue > 1 then
    Inc(Result);
  if pValue > 2 then
    Inc(Result);
  if pValue > 3 then
    Inc(Result);
end;

end.
