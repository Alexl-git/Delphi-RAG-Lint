unit uLeafUse;

{ Five routines, each binding a LOCAL named Child. Every bare `Child` here is a
  variable use, not a call to TWalker.Child -- but each emits a same-named ref
  that the unresolved-name caller bucket used to claim. }

interface

procedure UseA;
procedure UseB;
procedure UseC;
procedure UseD;
procedure UseE;

implementation

procedure UseA;
var
  Child: Integer;
begin
  Child := 1;
end;

procedure UseB;
var
  Child: Integer;
begin
  Child := 2;
end;

procedure UseC;
var
  Child: Integer;
begin
  Child := 3;
end;

procedure UseD;
var
  Child: Integer;
begin
  Child := 4;
end;

procedure UseE;
var
  Child: Integer;
begin
  Child := 5;
end;

end.
