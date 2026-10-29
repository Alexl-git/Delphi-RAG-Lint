unit uuses;

interface

uses
  ubhelp,
  uchelp;

function Value: Integer;

implementation

uses uihelp, uehelp, udhelp;

function Value: Integer;
begin
  Result:= CValue + DValue;
end;

end.
