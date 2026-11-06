unit uFadSecond;

interface

var
  GSecond: TObject;

function SecondHash: Integer;

implementation

uses
  System.SysUtils, uFadFirst;

function SecondHash: Integer;
begin
  Result:= GSecond.GetHashCode;
end;

initialization

finalization
  FirstHash; // TRIGGER-CALL
  FirstGuarded; // CONTROL-GUARDED
  FirstSpared; // CONTROL-SPARED
  FreeAndNil(GSecond);
end.