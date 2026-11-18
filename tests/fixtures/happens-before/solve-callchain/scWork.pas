unit scWork;

interface

procedure RunAll;

implementation

uses
  scData;

procedure Level3;
begin
  if GData + GDataIf > 0 then // USE-DEEP
    Writeln('ok');
end;

procedure Level2;
begin
  Level3;
end;

procedure Level1;
begin
  Level2;
end;

procedure RunAll;
begin
  Level1;
end;

end.
