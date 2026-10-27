unit basic;

interface

implementation

uses
  System.Types;

procedure P(var R: TRect; const A: TRect);
begin
  R.Left := A.Left;
  R.Top := A.Top;
  R.Right := A.Right;
end;

procedure Q(var R: TRect; const A: TRect);
begin
  R.Left := A.Left;
  R.Top := A.Top;
end;

end.
