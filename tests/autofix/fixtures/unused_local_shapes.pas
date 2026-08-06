unit unused_local_shapes;

{ Fixture for the unused-local autofix.

  Deliberately covers the shapes a per-finding, text-only fix gets WRONG:
  a shared declaration where only SOME names are dead (deleting the line would
  remove variables that are still used), and a var section whose LAST
  declaration is dead while the earlier ones live (a backwards scan for the
  'var' keyword swallows the whole block). Both produce code that does not
  compile, silently, with exit code 0. }

interface

implementation

{ 1. sole declaration in the section -> the declaration AND the now-orphaned
     'var' keyword both go, because a bare 'var' before 'begin' will not compile. }
procedure SoleDecl;
var
  Dead: Integer;
begin
  Writeln('x');
end;

{ 2. every name in a shared declaration is dead -> the whole line goes, and the
     section empties, so the 'var' keyword goes with it. }
procedure AllNamesDead;
var
  D1, D2, D3: string;
begin
  Writeln('x');
end;

{ 3. only SOME names are dead -> splice the name list and KEEP the declaration.
     Live is still used; deleting this line would break the build. }
procedure SomeNamesDead;
var
  Dead1, Live, Dead2: string;
begin
  Live := 'v';
  Writeln(Live);
end;

{ 4. the LAST declaration is dead but the earlier ones survive -> the section
     must keep its 'var' keyword and every live declaration. }
procedure LastDeclDead;
var
  Kept1: Integer;
  Kept2: string;
  DeadTail: Boolean;
begin
  Kept1 := 1;
  Kept2 := 'a';
  Writeln(Kept1);
  Writeln(Kept2);
end;

{ 5. a live declaration FOLLOWS the dead one. }
procedure DeadFirst;
var
  DeadHead: Integer;
  Survivor: string;
begin
  Survivor := 'b';
  Writeln(Survivor);
end;

end.
