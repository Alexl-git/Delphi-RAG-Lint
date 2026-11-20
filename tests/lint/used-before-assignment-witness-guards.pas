unit UbaWitnessGuards;

interface

implementation

uses
  System.SysUtils;

procedure Touch(var AFlag: Boolean);
begin
  AFlag := not AFlag;
end;

{ 1.52.1 SLZ-RULE2 -- witness-flag guards the pairing proof did not see:
  a conjunct (`HasBest and (Best ...)`), an early exit (`if not Have then Exit`),
  an or-disjunct (`(not Has) or (X ...)`), and a flag in a compound if-condition
  (`HaveG and HaveL`). Each FP shape is a proven pairing and must stay silent;
  every control breaks ONE clause and must keep firing. }

function ConjunctGuard(const A: TArray<Integer>): Integer;
var
  Best   : Integer;
  HasBest: Boolean;
  I      : Integer;
begin
  Result := 0;
  HasBest := False;
  for I := 0 to High(A) do
    if A[I] > 0 then begin Best := A[I]; HasBest := True; end;
  if HasBest and (Best > 3) then Result := Best;
end;

function EarlyExitGuard(const A: TArray<Integer>): Integer;
var
  Best    : Integer;
  HaveBest: Boolean;
  I       : Integer;
begin
  HaveBest := False;
  for I := 0 to High(A) do
    if not HaveBest then begin Best := A[I]; HaveBest := True; end;
  if not HaveBest then Exit(-1);
  Result := Best * 2;
end;

function OrDisjunctGuard(const A: TArray<Integer>): Integer;
var
  Mth   : Integer;
  HasMth: Boolean;
begin
  Result := 0;
  HasMth := False;
  if Length(A) > 1 then
  begin
    Mth := A[1];
    HasMth := True;
  end;
  if (not HasMth) or (Mth < 0) then Exit;
  Result := Mth;
end;

function CompoundIfGuard(const AG, AL: string): Integer;
var
  G, L        : Integer;
  HaveG, HaveL: Boolean;
begin
  Result := 0;
  HaveG := False;
  HaveL := False;
  if AG <> '' then
  begin
    try
      G := StrToInt(AG);
      HaveG := True;
    except
      on E: Exception do Result := -1;
    end;
  end;
  if AL <> '' then
  begin
    try
      L := StrToInt(AL);
      HaveL := True;
    except
      on E: Exception do Result := -2;
    end;
  end;
  if HaveG and HaveL then
    Result := G + L
  else if HaveL then Result := L
  else if HaveG then Result := G;
end;

{ ---- controls: each must still fire ---- }

function CtlFlagNotInitialised(const A: TArray<Integer>): Integer;
var
  Best   : Integer;
  HasBest: Boolean;
  I      : Integer;
begin
  Result := 0;
  for I := 0 to High(A) do
    if A[I] > 0 then begin Best := A[I]; HasBest := True; end;
  if HasBest and (Best > 3) then Result := Best;
end;

function CtlStrayTrueSite(const A: TArray<Integer>): Integer;
var
  Best   : Integer;
  HasBest: Boolean;
begin
  Result := 0;
  HasBest := False;
  if Length(A) > 0 then begin Best := A[0]; HasBest := True; end;
  if Length(A) > 9 then HasBest := True;
  if HasBest and (Best > 3) then Result := Best;
end;

function CtlNonDivertingThen(const A: TArray<Integer>): Integer;
var
  Best    : Integer;
  HaveBest: Boolean;
begin
  Result := 0;
  HaveBest := False;
  if Length(A) > 0 then begin Best := A[0]; HaveBest := True; end;
  if not HaveBest then Result := -1;
  Result := Result + Best;
end;

function CtlFlagByVarArg(const A: TArray<Integer>): Integer;
var
  Best   : Integer;
  HasBest: Boolean;
begin
  Result := 0;
  HasBest := False;
  if Length(A) > 0 then begin Best := A[0]; HasBest := True; end;
  Touch(HasBest);
  if HasBest and (Best > 3) then Result := Best;
end;

function CtlWrongPolarity(const A: TArray<Integer>): Integer;
var
  Best   : Integer;
  HasBest: Boolean;
begin
  Result := 0;
  HasBest := False;
  if Length(A) > 0 then begin Best := A[0]; HasBest := True; end;
  if HasBest or (Best > 3) then Result := 1;
end;

procedure CtlOutParamReadFirst(out ALimit: Integer; const AStart: Integer);
begin
  if AStart < ALimit then ALimit := AStart;
end;

end.