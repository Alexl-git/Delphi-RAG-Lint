unit harvest_drift;

interface

// Original prose, first version.
function Drifting: Integer;

// Prose that will be deleted.
function Vanishing: Integer;

function Driver: Integer;

implementation

function Drifting: Integer;
begin
  Result := 1;
end;

function Vanishing: Integer;
begin
  Result := 2;
end;

// Calls the other two so each one has a CALLER fact. Without at least one fact
// the engine writes no doc block at all ("nothing to document"), a harvested
// summary would have nowhere to land, and every assertion in the runner would
// be vacuous. The same device is used in harvest_text.pas and harvest_impl.pas.
//
// THE EMPTY PARENTHESES ARE LOAD-BEARING -- do not "simplify" them away. A bare
// parameterless call used as a BINARY-EXPRESSION OPERAND ('Result := Drifting +
// Vanishing;') records NO reference at all, so neither routine gets a caller
// fact, the batch path's facts-only filter drops the fresh create, and
// 'document --unit' reports "nothing to document" while '--qname' documents the
// same symbol. Not the same as the fixed lone-bare-RHS bug: 'Result := A;' and
// 'Result := Abs(A);' both record fine; only the operand form is dropped. Filed
// as docs\INBOX-bare-call-in-binary-expression-not-indexed.md.
function Driver: Integer;
begin
  Result := Drifting() + Vanishing();
end;

end.
