unit string_index_base;

interface

implementation

uses
  System.SysUtils;

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

end.
