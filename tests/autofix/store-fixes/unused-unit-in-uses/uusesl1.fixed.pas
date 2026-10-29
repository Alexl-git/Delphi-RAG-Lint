unit uusesl1;

{ Leading-comma layout (house style): ubhelp is the FIRST entry -- the next
  entry is promoted (its comma goes); uehelp is the LAST entry with the ; on
  the same line -- the line above takes the ;. }

interface

uses
  uchelp
  ;

function Value: Integer;

implementation

uses
  udhelp;

function Value: Integer;
begin
  Result:= CValue + DValue;
end;

end.
