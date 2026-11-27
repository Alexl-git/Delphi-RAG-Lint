unit uExcAA;

{ v156 FIXR-B #2: three units of the SAME length and shape; only the handled class differs. }

interface

uses
  System.SysUtils;

type
  EFooErr = class(Exception);

procedure SinkAA(const S: string);
procedure RunAA;

implementation

procedure SinkAA(const S: string);
begin
end;

procedure RunAA;
begin
  try
    SinkAA('x');
  except
    on E: EFooErr do
      SinkAA(E.Message);
  end;
end;

end.
