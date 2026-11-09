program MetaclassValue;

// Plan fixture (lane 150 CY2, 150-CY-7b): MvApp passes the class TMvJob of MvJob as a VALUE
// (System.Classes.RegisterClass(TMvJob)); neither class can move (each body needs the other
// unit) and MvJob constructs TMvApp. Today the edge MvApp -> MvJob refuses `class-ref`
// ("passes the class `TMvJob` as a value"): the metaclass hand-over recipe is not built.

{$APPTYPE CONSOLE}

uses
  MvApp in 'MvApp.pas',
  MvJob in 'MvJob.pas';

var
  J: TMvJob;
begin
  J := TMvJob.Create;
  try
    J.Kick;
  finally
    J.Free;
  end;
end.