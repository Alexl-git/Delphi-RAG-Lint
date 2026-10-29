unit uuses;

interface

uses
  uchelp;

function Value: Integer;

implementation

uses uihelp, udhelp;

function Value: Integer;
begin
  Result:= CValue + DValue;
end;

end.
