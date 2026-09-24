unit uParenlessLib;

{ Library half of the parenless-call fixture (run_parenless_call_bind.ps1).
  NextId is the parameterless FUNCTION every positive site calls without
  parentheses; the rest are the shapes a parenless read must NOT bind to. }

interface

type
  TIdFunc = function: Integer;
  TKeyFunc = function(A: Integer): Integer;

function NextId: Integer;
function NextKey(A: Integer): Integer;
function Pick: Integer; overload;
function Pick(A: Integer): Integer; overload;
procedure RegisterGen(AGen: TIdFunc);
procedure RegisterQ(AGen: System.SysUtils.TFunc<Integer>);
procedure RegisterS(AGen: Func<Integer>);

var
  GNext: Integer;

implementation

function NextId: Integer;
begin
  GNext := GNext + 1;
  Result := GNext;
end;

function NextKey(A: Integer): Integer;
begin
  Result := A + 1;
end;

function Pick: Integer;
begin
  Result := 1;
end;

function Pick(A: Integer): Integer;
begin
  Result := A;
end;

procedure RegisterGen(AGen: TIdFunc);
begin
  if Assigned(AGen) then
    GNext := 0;
end;

{ D16b: the zero-argument function types the project index never holds --
  a UNIT-QUALIFIED System.SysUtils.TFunc<T> and Spring4D's Func<T>. }
procedure RegisterQ(AGen: System.SysUtils.TFunc<Integer>);
begin
  if Assigned(AGen) then
    GNext := 0;
end;

procedure RegisterS(AGen: Func<Integer>);
begin
  if Assigned(AGen) then
    GNext := 0;
end;

end.