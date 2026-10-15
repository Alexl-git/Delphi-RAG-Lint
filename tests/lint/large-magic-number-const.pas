unit LargeMagicNumberConst;

interface

const
  { A named constant IS the fix the rule recommends -- the literal that forms a
    const's value must NOT be flagged "consider naming the constant". }
  PanelHeight = 92;
  TimeoutMs   = 8640;

implementation

procedure P;
var
  X: Integer;
begin
  { The same arbitrary literal in executable code MUST still fire. }
  X := 92;
  X := 8640;
end;

procedure Q;
begin
  { An INLINE constant's value is a named constant too (Gitea drag-lint#2). }
  const LIMIT_MS = 16000;
  Writeln(LIMIT_MS);
end;

end.
