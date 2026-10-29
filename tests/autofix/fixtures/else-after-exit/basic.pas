unit basic;

interface

uses
  System.SysUtils;

procedure P1(Flag: Boolean);
procedure P2(N: Integer);
procedure P3(Flag: Boolean);

implementation

procedure P1(Flag: Boolean);
begin
  if Flag then
    Exit
  else
    Writeln('x');
end;

procedure P2(N: Integer);
var
  I: Integer;
begin
  for I := 0 to N do
  begin
    if I = 3 then
    begin
      Writeln('three');
      Continue;
    end
    else
    begin
      Writeln(I);
      Writeln('more')
    end;
    Writeln('tail');
  end;
end;

procedure P3(Flag: Boolean);
begin
  if Flag then raise Exception.Create('x') else Writeln('ok');
end;

end.
