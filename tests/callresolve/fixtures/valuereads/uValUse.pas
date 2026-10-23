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

end.