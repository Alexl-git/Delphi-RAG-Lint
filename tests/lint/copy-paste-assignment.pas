unit copy_paste_assignment;

interface

implementation

uses
  System.Types;

procedure ThreeRowsOneCopied(var R: TRect; const A: TRect);
begin
  R.Left := A.Left;
  R.Top := A.Left;
  R.Right := A.Right;
end;

procedure FourRowsOneCopied(var R: TRect; const A: TRect);
begin
  R.Left := A.Left;
  R.Top := A.Top;
  R.Right := A.Top;
  R.Bottom := A.Bottom;
end;

procedure AxisPairOnly(var R: TRect; const A: TRect);
begin
  R.Left := A.Left;
  R.Top := A.Left;
end;

procedure SingleOddRow(var R: TRect; const A: TRect);
begin
  R.Top := A.Left;
end;

procedure AllDistinct(var R: TRect; const A: TRect);
begin
  R.Left := A.Left;
  R.Top := A.Top;
  R.Right := A.Right;
end;

procedure DifferentSources(var R: TRect; const A, B: TRect);
begin
  R.Left := A.Left;
  R.Top := B.Left;
  R.Right := A.Right;
end;

procedure NonAxisTwoRows(var R: TRect; const A: TRect);
begin
  R.Left := A.Left;
  R.Right := A.Left;
end;

end.
