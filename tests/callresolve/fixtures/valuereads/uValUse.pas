unit uValUse;

interface

uses
  uValLib, uValLib2;

type
  TVal = class
  private
    FTotal: Integer;
  public
    procedure Run(AErr: Integer);
    function Calc: Integer;
    procedure Loops;
    procedure Blocks;
    function Calc2: Integer;
    procedure Anon;
  end;

const
  CHECK_OK = 1;

var
  GOwn: Integer;

function GetIt: Integer;

implementation

uses
  uUnknown;

function GetIt: Integer;
begin
  Result := 0;
end;

procedure TVal.Run(AErr: Integer);
const
  LIMIT = 5;
var
  L: Integer;
  N: Integer;
  GOwn: Integer;

  procedure Inner;
  begin
    N := L; // R-OUTER-LOCAL
  end;

  procedure InnerConst;
  const
    AErr = 7;
  begin
    N := AErr; // NEG-INNER-CONST
  end;

begin
  L := 1;
  GOwn := 2;
  N := L; // R-LOCAL
  N := AErr; // R-PARAM
  N := LIMIT; // NEG-LOCAL-CONST
  N := CHECK_OK; // R-UNIT-CONST
  N := GShared; // R-USED-UNIT
  N := GOwn; // R-SHADOW-LOCAL
  N := GClash; // NEG-AMBIGUOUS
  N := GMissing; // NEG-NOT-FOUND
  N := FTotal; // NEG-FIELD
  N := GetIt; // NEG-ROUTINE
  with TUnknownThing.Make do
    N := L; // NEG-WITH
  Inner;
end;

function TVal.Calc: Integer;
begin
  Result := 1;
  Calc := Result; // NEG-RESULT
end;

procedure TVal.Loops;
begin
  for var i := 0 to 1 do FTotal := i; // DUP-FIRST-DECL
  for var i := 0 to 2 do // DUP-SECOND-DECL
  begin
    FTotal := i; // DUP-SECOND-READ
  end;
end;

procedure TVal.Blocks;
begin
  if FTotal > 0 then
  begin
    var K: Integer := 1; // DUPW-FIRST-DECL
    K := 2; // DUPW-FIRST-WRITE
    FTotal := K; // DUPW-FIRST-READ
  end;
  if FTotal > 1 then
  begin
    var K: Integer := 5; // DUPW-SECOND-DECL
    K := 6; // DUPW-SECOND-WRITE
    FTotal := K; // DUPW-SECOND-READ
  end;
  if FTotal > 2 then
  begin
    var Q: Integer := 1;
    FTotal := Q; // R-INSCOPE-Q
  end;
  FTotal := Q; // NEG-OUTSCOPE-Q
end;

function TVal.Calc2: Integer;
begin const CHECK_OK = 9;
  Result := CHECK_OK; // NEG-MIDLINE-CONST
end;

procedure TVal.Anon;
var
  P: TProc;
begin
  if FTotal > 0 then
  begin
    var H: Integer := 1; // ANON-INLINE-DECL
    FTotal := H; // R-BEFORE-ANON-VAR
  end;
  P := procedure
    var
      H: Integer; // ANON-SECTION-DECL
    begin
      H := 2;
      FTotal := H; // R-ANON-SECTION-VAR
    end;
end;
end.