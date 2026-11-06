unit uIohFirst;

{ With this unit first in the .dpr: uIohSecond initializes BEFORE this unit, through the cycle. }

interface

var
  GFirst: Integer;
  GDirect: Integer;
  GLazy: TObject;
  GNeverSet: Integer;
  GRec: PInteger;

function FirstValue: Integer;
function FirstLazy: TObject;
function FirstNeverSet: Integer;
function FirstShadow: Integer;
function FirstRec: Integer;

implementation

uses
  uIohSecond;

procedure SetLater;
begin
  GDirect:= 1;
end;

function FirstValue: Integer;
begin
  Result:= GFirst;
end;

function FirstLazy: TObject;
begin
  if GLazy = nil then GLazy:= TObject.Create;
  Result:= GLazy;
end;

function FirstNeverSet: Integer;
begin
  Result:= GNeverSet;
end;

function FirstShadow: Integer;
var
  GFirst: Integer;
begin
  GFirst:= 1;
  Result:= GFirst;
end;

function FirstRec: Integer;
begin
  Result:= GRec^;
end;

initialization
  New(GRec);
  GFirst:= SecondValue; // CONTROL-SAFE reads uIohSecond, which already ran
  GLazy:= nil;
  SetLater;
end.