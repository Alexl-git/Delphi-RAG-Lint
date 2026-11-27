unit uExcBB;

{ v156 FIXR-B #2: three units of the SAME length and shape; only the handled class differs. }

interface

uses
  System.SysUtils;

type
  EBarErr = class(Exception);

procedure SinkBB(const S: string);
procedure RunBB;

implementation

procedure SinkBB(const S: string);
begin
end;

procedure RunBB;
begin
  try
    SinkBB('x');
  except
    on E: EBarErr do
      SinkBB(E.Message);
  end;
end;

end.
