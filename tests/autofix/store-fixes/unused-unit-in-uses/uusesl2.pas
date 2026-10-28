unit uusesl2;

{ Leading-comma layout: ubhelp is a MIDDLE entry, uehelp the LAST one before
  a ; on its own line -- each line goes whole. }

interface

uses
  uchelp
  , ubhelp
  , udhelp
  , uehelp
  ;

function Value: Integer;

implementation

function Value: Integer;
begin
  Result:= CValue + DValue;
end;

end.
