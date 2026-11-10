library T2Lib;

uses
  uT2LibUnit in 'uT2LibUnit.pas';

const
  CLibVer = 3;

var
  GLibCount: Integer;

function LibAdd(A, B: Integer): Integer; stdcall;
begin
  Result:= A + B + CLibVer;
  Inc(GLibCount);
end;

exports
  LibAdd,
  T2Twice;

begin
  GLibCount:= 0;
end.