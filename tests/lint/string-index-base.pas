unit string_index_base;

interface

implementation

uses
  System.SysUtils, System.Classes;

procedure Basis(var S: string; const T: string);
var
  R: string;
  N: Integer;
begin
  R := Copy(S, 0, 3);
  Delete(S, 0, 1);
  Insert(T, S, 0);
  if Pos(',', S) = -1 then Exit;
  N := Pos('x', S);
  if N <> -1 then Exit;
end;

procedure Fein(var S: string; const T: string);
var
  R: string;
begin
  R := Copy(S, 1, 3);
  Delete(S, 1, 1);
  Insert(T, S, 1);
  if Pos(',', S) = 0 then Exit;
  if S.IndexOf(',') = -1 then Exit;
end;

procedure ArrayShapes(const A: TArray<string>; var B: TBytes; const S: string;
  L: TStringList);
var
  Units: TArray<string>;
  R: TArray<string>;
begin
  R := Copy(A, 0, 2);
  B := Copy(B, 0, Length(B));
  Insert(S, Units, 0);
  R := Copy(L.ToStringArray, 0, 3);
  R := Copy(S.Split([',']), 0, 1);
end;
end.
