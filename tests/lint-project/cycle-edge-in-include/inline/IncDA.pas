unit IncDA;

interface

type
  TIncDARec = record
    X: Integer;
  end;

procedure DoIncDA;

implementation

uses
  IncDB;

procedure DoIncDA;
begin
  UseIncDB;
end;

end.