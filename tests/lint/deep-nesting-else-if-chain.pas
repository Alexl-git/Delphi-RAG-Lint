unit DeepNestElseIfChain;

interface

implementation

// A flat else-if DISPATCH. Every branch sits at the same logical level -- this
// is the shape of an argument parser or a command table, and no style guide
// calls it nested. The grammar right-nests it (ifElse inside ifElse inside...),
// so a depth counter that adds one per if-node reports nine levels here and
// 141 on DRagLint.CLI.pas's ParseArgs. Threshold is 5, so this file must yield
// NO deep-nesting finding.
procedure Dispatch(const A: string);
begin
  if A = 'one' then
    WriteLn(1)
  else if A = 'two' then
    WriteLn(2)
  else if A = 'three' then
    WriteLn(3)
  else if A = 'four' then
    WriteLn(4)
  else if A = 'five' then
    WriteLn(5)
  else if A = 'six' then
    WriteLn(6)
  else if A = 'seven' then
    WriteLn(7)
  else if A = 'eight' then
    WriteLn(8)
  else
    WriteLn(0);
end;

// GENUINE nesting must still fire, so the fix cannot simply stop counting if
// nodes: six ifs down the THEN side, each one inside the last.
procedure ReallyNested(X: Integer);
begin
  if X > 0 then
    if X > 1 then
      if X > 2 then
        if X > 3 then
          if X > 4 then
            if X > 5 then
              WriteLn('deep');
end;

end.
