unit sample;

// Fixture for refs.enclosing_symbol_id attribution (v0.82 Task 1).
//
// Proves per-routine enclosing attribution: each Helper call resolves to the
// routine whose impl body contains it, chosen correctly among SEVERAL candidate
// routines (Bar, Outer, Helper) whose bodies do not overlap.
//   - Helper call in TThing.Bar  -> attributed to Bar
//   - Helper call in Outer's body -> attributed to Outer (NOT Bar / Helper)
//
// NOTE (parser limitation, documented): the tree-sitter Delphi grammar does NOT
// emit nested/local procedures (e.g. the Inner below) as their own symbols, and
// does not capture refs inside a nested body. The innermost-largest-ImplStartLine
// tie-break in ResolveEnclosingSymbolId is still correct and will pick a nested
// routine once the parser emits one; it simply cannot be exercised here today.

interface

type
  TThing = class
  public
    procedure Bar;
  end;

procedure Outer;

implementation

procedure Helper;
begin
  Writeln('helper');
end;

procedure TThing.Bar;
var
  N: Integer;
begin
  N := 0;
  Helper;
  if N > 0 then
    N := N + 1;
end;

procedure Outer;
var
  M: Integer;

  procedure Inner;
  begin
    M := 1;
  end;

begin
  M := 0;
  Inner;
  Helper;
end;

end.
