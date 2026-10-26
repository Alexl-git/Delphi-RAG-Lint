program B4fBase;

// CYCC B4-f fixture: an implementation-only cycle whose only cuttable edge is BfCanvas -> BfShape,
// and only by a base class (Part B): R1 does not apply (no routine), R2 refuses (TBfShape does not
// implement IInterface) and TBfShape cannot move (its Draw body calls back into BfCanvas).

{$APPTYPE CONSOLE}

uses
  BfCanvas in 'BfCanvas.pas',
  BfShape in 'BfShape.pas';

var
  S: TBfShape;
begin
  S := TBfShape.Create('disc');
  try
    S.Draw;
  finally
    S.Free;
  end;
end.