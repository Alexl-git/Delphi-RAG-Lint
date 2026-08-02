unit returns;

interface

type
  TCfg = record
    Alpha  : Integer;
    Beta   : Integer;
    Gamma  : Integer;
    Delta  : Integer;
    Sigma  : Integer;
    Omega  : Integer;
  end;

  TIntGetter = reference to function(const ARec: TCfg): Integer;

  TBox = class
    class function ClassLag(A: Integer): Integer;
  end;

  TAlpha = class
    class function Same(A: Integer): Integer;
  end;

  TBeta = class
    class function Same(A: Integer): Integer;
  end;

function PlainSum(A, B: Integer): Integer;

function DoubleIt(X: Integer): Integer;

function ConcatPath(const A, B: string): string;

function PrevIdx(const AItems: TArray<Integer>; AFrom: Integer): Integer;

function Accum(const AItems: TArray<Integer>): Integer;

function DefaultCfg(ASeed: Integer): TCfg;

function NestedCallRhs(const ADir, AName: string): string;

function MultiLineRhs(A, B: Integer): Boolean;

function OneLiner(A: Integer): Integer;

function AnonHost(const ACfg: TCfg): Integer;

function LocalHost(A: Integer): Integer;

function InlineProcVar(A: Integer): Integer;

function ParamlessProcVar(A: Integer): Integer;

function LocalProcTypeDecl(A: Integer): Integer;

function BraceCommentInc(A: Integer): Integer;

function BraceCommentSelfRef(A: Integer): Integer;

function ParenStarSetLength(A: Integer): string;

function StrLiteralResult(A: Integer): string;

function ForeignA(A: Integer): Integer;

function ForeignB(A: Integer): Integer;

procedure Driver;

implementation

uses
  System.SysUtils;

function PlainSum(A, B: Integer): Integer;
begin
  Result := A + B;
end;

function DoubleIt(X: Integer): Integer;
begin
  Result := X * 2;
end;

function ConcatPath(const A, B: string): string;
begin
  Result := A + '.' + B;
end;

function PrevIdx(const AItems: TArray<Integer>; AFrom: Integer): Integer;
begin
  Result := AFrom;
  while (Result >= 0) and (AItems[Result] = 0) do
    Dec(Result);
end;

function Accum(const AItems: TArray<Integer>): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(AItems) do
    Result := Result + AItems[I];
end;

function DefaultCfg(ASeed: Integer): TCfg;
begin
  Result.Alpha := ASeed + 1;
  Result.Beta  := ASeed + 2;
  Result.Gamma := ASeed + 3;
  Result.Delta := ASeed + 4;
  Result.Sigma := ASeed + 5;
  Result.Omega := ASeed + 6;
end;

function NestedCallRhs(const ADir, AName: string): string;
begin
  Result := ConcatPath( ConcatPath(ADir, 'sub'), AName);
end;

function MultiLineRhs(A, B: Integer): Boolean;
begin
  Result := (A > 0) and
            (B > 0);
end;

function OneLiner(A: Integer): Integer;
begin
  if A > 0 then begin Result := A * 3 end else begin Result := 0 end;
end;

function AnonHost(const ACfg: TCfg): Integer;
var
  F: TIntGetter;
begin
  F := function(const AInner: TCfg): Integer begin Result := AInner.Beta end;
  Result := F(ACfg) + 1;
end;

function LocalHost(A: Integer): Integer;

  function Twice(X: Integer): Integer;
  begin
    Result := X * 5;
  end;

begin
  Result := Twice(A) + 1;
end;

function InlineProcVar(A: Integer): Integer;
var
  F: function(X: Integer): Integer;
begin
  F := DoubleIt;
  Result := F(A) + 9;
end;

function ParamlessProcVar(A: Integer): Integer;
var
  F: function: Integer;
begin
  F := nil;
  Result := F() + A;
end;

function LocalProcTypeDecl(A: Integer): Integer;
type
  TGetter = function: Integer;
var
  G: TGetter;
begin
  G := nil;
  Result := G() + A;
end;

function BraceCommentInc(A: Integer): Integer;
begin
  { old implementation: Inc(Result); }
  Result := A + 100;
end;

function BraceCommentSelfRef(A: Integer): Integer;
begin
  { was: Result := Result + 1; }
  Result := A + 200;
end;

function ParenStarSetLength(A: Integer): string;
begin
  (* dead: SetLength(Result, A); *)
  Result := 'p' + IntToStr(A);
end;

function StrLiteralResult(A: Integer): string;
begin
  Result := Format('Result := Result + 1; %d', [A]);
end;

class function TBox.ClassLag(A: Integer): Integer;
begin
  Result := A + 41;
end;

function ForeignA(A: Integer): Integer;
begin
  Result := A * 7;
end;

function ForeignB(A: Integer): Integer;
begin
  Result := A - 7;
end;

class function TAlpha.Same(A: Integer): Integer;
begin
  Result := A * 11;
end;

class function TBeta.Same(A: Integer): Integer;
begin
  Result := A * 22;
end;

procedure Driver;
var
  C: TCfg;
begin
  C := DefaultCfg(0);
  if MultiLineRhs(PlainSum(1, 2), DoubleIt(3)) then
    C.Alpha := OneLiner(4);
  C.Beta  := PrevIdx([0], 1) + Accum([1]) + AnonHost(C) + LocalHost(1) + InlineProcVar(2);
  C.Gamma := Length(NestedCallRhs('a', 'b')) + Length(ConcatPath('a', 'b'));
  C.Delta := ParamlessProcVar(5) + LocalProcTypeDecl(6) + BraceCommentInc(7) + BraceCommentSelfRef(8);
  C.Omega := Length(ParenStarSetLength(9)) + Length(StrLiteralResult(10));
  C.Sigma := C.Alpha + C.Beta + C.Gamma + C.Delta + C.Omega
           + TBox.ClassLag(11) + ForeignA(12) + ForeignB(13)
           + TAlpha.Same(14) + TBeta.Same(15);
end;

end.
