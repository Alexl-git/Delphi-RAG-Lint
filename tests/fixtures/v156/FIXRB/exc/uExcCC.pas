unit uExcCC;

{ v156 FIXR-B #2: three units of the SAME length and shape; only the handled class differs. }

interface

uses
  System.SysUtils;

type
  EQuxErr = class(Exception);

procedure SinkCC(const S: string);
procedure RunCC;

implementation

procedure SinkCC(const S: string);
begin
end;

procedure RunCC;
begin
  try
    SinkCC('x');
  except
    on E: EQuxErr do
      SinkCC(E.Message);
  end;
end;

end.
