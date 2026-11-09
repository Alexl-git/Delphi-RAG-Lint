unit RG_148;

interface

type
  TRgNames = record
    Count: Integer;
    Names: array [0..3] of string end;

  TRgCls = class
  private
    FUnusedRec: Integer;
    FUnusedLast: array [0..2] of string end;

procedure RgBeep(X: Integer); stdcall; external 'user32.dll' name 'MessageBeep'
procedure RgIdx(X: Integer); external 'lib.dll' index 5
procedure RgLib(X: Integer); external RgLibName name RgSomeConst

implementation

uses System.Generics.Collections;

procedure RgGeneric(pFlag: Boolean);
var
  L: TList<Integer>;
  D: TDictionary<string, Integer>;
begin
  L := TList<Integer (* c *)>.Create;
  D := TDictionary<string, // key
    Integer>.Create;
  if pFlag then L.Add(1);
end;

end.