unit uFadFirst;

{ With this unit first in the .dpr: uFadSecond initializes first, so this unit is FINALIZED first. }

interface

var
  GFirst: TObject;
  GGuarded: TObject;
  GSpared: TObject;

function FirstHash: Integer;
function FirstGuarded: Integer;
function FirstSpared: Integer;

implementation

uses
  System.SysUtils, uFadSecond;

function FirstHash: Integer;
begin
  Result:= GFirst.GetHashCode;
end;

function FirstGuarded: Integer;
begin
  if Assigned(GGuarded) then Result:= GGuarded.GetHashCode else Result:= 0;
end;

function FirstSpared: Integer;
begin
  Result:= GSpared.GetHashCode;
end;

initialization

finalization
  SecondHash; // CONTROL-SAFE uFadSecond is finalized after this unit
  FreeAndNil(GFirst);
  FreeAndNil(GGuarded);
end.