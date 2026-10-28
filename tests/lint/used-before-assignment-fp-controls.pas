unit UbaFpControls;

interface

implementation

uses
  System.Classes, System.SysUtils;

type
  TPair = record
    A: Integer;
    B: Integer;
  end;

procedure FillBuf(var Buf; Count: Integer);
begin
  FillChar(Buf, Count, 0);
end;

{ POSITIVE CONTROLS -- must keep firing. }
function TruePositiveScalar(Flag: Boolean): Integer;
var
  X: Integer;
begin
  if Flag then X := 1;
  Result := X;
end;

function TruePositiveArray: Byte;
var
  pb: array[0..3] of Byte;
begin
  Result := pb[1];
end;

function TruePositiveRecordField: Integer;
var
  R: TPair;
begin
  Result := 0;
  try
    R.A := 1;
    Result := R.A;
  except
    Result := R.B;
  end;
end;

end.
