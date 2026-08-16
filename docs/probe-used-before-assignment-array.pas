unit uarr;
interface
uses Winapi.Windows, System.SysUtils;
procedure A1;
procedure A2;
procedure A3;
procedure A4;
procedure A5;
implementation

{ Form B -- element-wise assignment in one loop, read in a later one. }
procedure A1;
var
  Arr: array[0..2] of Integer;
  I, S: Integer;
begin
  for I := 0 to 2 do
    Arr[I] := I;
  S := 0;
  for I := 0 to 2 do
    S := S + Arr[I];
  Writeln(S);
end;

{ Form B, straight-line: every element assigned explicitly. }
procedure A2;
var
  Arr: array[0..1] of Integer;
begin
  Arr[0] := 1;
  Arr[1] := 2;
  Writeln(Arr[0] + Arr[1]);
end;

{ Form A -- address-of the first element handed to a filling API. }
procedure A3;
var
  Buf: array[0..15] of AnsiChar;
  N: Integer;
begin
  N := GetModuleFileNameA(0, @Buf[0], Length(Buf));
  Writeln(N);
  Writeln(Buf[0]);
end;

{ Form A with a dynamic array via SetLength -- the common Delphi idiom. }
procedure A4;
var
  Dyn: TArray<Integer>;
  I: Integer;
begin
  SetLength(Dyn, 3);
  for I := 0 to 2 do
    Dyn[I] := I;
  Writeln(Dyn[0]);
end;

{ GENUINELY unsafe: never assigned at all. The positive control. }
procedure A5;
var
  Arr: array[0..2] of Integer;
begin
  Writeln(Arr[0]);
end;

end.