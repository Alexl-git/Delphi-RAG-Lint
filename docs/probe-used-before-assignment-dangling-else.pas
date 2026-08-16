unit probe_used_before_assignment_dangling_else;

interface

uses
  System.SysUtils, System.Types, Winapi.Windows;

function Fill(const A: string; out E: DWord): Boolean;

procedure V0(const F: string);
procedure V1(const F: string);
procedure V2(const F: string);
procedure V3(const F: string);
procedure V4(const F: string);
procedure V5(const F: string);
procedure V6(const F: string);
procedure V7(const F: string);

implementation

function Fill(const A: string; out E: DWord): Boolean;
begin
  E := Length(A);
  Result := E > 0;
end;

{ V0 -- the E1 baseline. Outer `if` with NO else, inner if/else, the read is an
  open-array element in the else branch. This is the shape that FIRES. }
procedure V0(const F: string);
var
  Err: DWord;
begin
  if F <> '' then
    if Fill(F, Err) then
      Writeln('ok')
    else
      Writeln(Format('%s %d', [F, Err]));
end;

{ V1 -- V0 plus an explicit ELSE on the OUTER if. If the outer if's FALSE edge
  is mis-wired onto the inner else-block, giving it a real else-block of its own
  should silence this. THE KEY DISCRIMINATOR. }
procedure V1(const F: string);
var
  Err: DWord;
begin
  if F <> '' then
    if Fill(F, Err) then
      Writeln('ok')
    else
      Writeln(Format('%s %d', [F, Err]))
  else
    Writeln('empty');
end;

{ V2 -- V0 with the outer condition reduced to a constant. Tests whether the
  outer condition's CONTENT matters (the note's next-step 1). }
procedure V2(const F: string);
var
  Err: DWord;
begin
  if True then
    if Fill(F, Err) then
      Writeln('ok')
    else
      Writeln(Format('%s %d', [F, Err]));
end;

{ V3 -- V0 with the outer `if` replaced by a `while`. Tests whether it is the
  BRANCH specifically or any enclosing control-flow construct. }
procedure V3(const F: string);
var
  Err: DWord;
begin
  while F <> '' do
    if Fill(F, Err) then
      Writeln('ok')
    else
      Writeln(Format('%s %d', [F, Err]));
end;

{ V4 -- V0 with the open-array read moved to the THEN branch. Tests whether the
  else branch is load-bearing once the outer `if` is present. }
procedure V4(const F: string);
var
  Err: DWord;
begin
  if F <> '' then
    if Fill(F, Err) then
      Writeln(Format('%s %d', [F, Err]))
    else
      Writeln('ok');
end;

{ V5 -- V0 with the outer `if` replaced by a plain begin..end block, i.e. one
  more nesting LEVEL but no extra edge. Separates "nesting depth" from "extra
  CFG edge". }
procedure V5(const F: string);
var
  Err: DWord;
begin
  begin
    if Fill(F, Err) then
      Writeln('ok')
    else
      Writeln(Format('%s %d', [F, Err]));
  end;
end;

{ V6 -- V0 with the read moved AFTER the inner if, at the join. Here the outer
  if's false edge genuinely does bypass the definition, so a finding would be
  CORRECT (Err really may be unassigned when F = ''). Control for "the rule can
  be right". }
procedure V6(const F: string);
var
  Err: DWord;
begin
  if F <> '' then
  begin
    if Fill(F, Err) then
      Writeln('ok')
    else
      Writeln('bad');
    Writeln(Format('%s %d', [F, Err]));
  end;
end;

{ V7 -- V0 with the open-array replaced by a direct read in a non-call, non-
  condition position (an assignment RHS). Tests whether the open-array
  constructor specifically is what classifies Err as a genuine read. }
procedure V7(const F: string);
var
  Err: DWord;
  N: DWord;
begin
  if F <> '' then
    if Fill(F, Err) then
      Writeln('ok')
    else
    begin
      N := Err;
      Writeln(N);
    end;
end;

{ V8 -- GENUINELY UNSAFE, open-array read at the join. The F = '' path skips
  Fill entirely, so Err really is possibly-unassigned here. A correct rule MUST
  fire. If it does, then open-array reads at a join ARE checked, and V6's
  silence is the diverted-false-edge bug rather than a dead check. }
procedure V8(const F: string);
var
  Err: DWord;
begin
  if F <> '' then
    Fill(F, Err);
  Writeln(Format('%s %d', [F, Err]));
end;

{ V9 -- V8 with a plain assignment-RHS read instead of the open array. Equally
  unsafe. If V8 fires and this does not, the rule only ever detects reads inside
  an open-array constructor -- a coverage hole independent of the edge bug. }
procedure V9(const F: string);
var
  Err: DWord;
  N: DWord;
begin
  if F <> '' then
    Fill(F, Err);
  N := Err;
  Writeln(N);
end;

{ V10 -- V0 with the else branch wrapped in begin..end but the read form
  UNCHANGED (still the open array). V7 changed the read form AND made the else
  compound at the same time; this isolates the compound-statement half. }
procedure V10(const F: string);
var
  Err: DWord;
begin
  if F <> '' then
    if Fill(F, Err) then
      Writeln('ok')
    else
    begin
      Writeln(Format('%s %d', [F, Err]));
    end;
end;

{ V11 -- V0 with a single-statement else whose read is an EXPRESSION operand
  rather than an open-array element (Err + 1, so it is not a bare argument and
  cannot be taken for a possible-def). Isolates the read-form half. }
procedure V11(const F: string);
var
  Err: DWord;
begin
  if F <> '' then
    if Fill(F, Err) then
      Writeln('ok')
    else
      Writeln(Err + 1);
end;

{ V12 -- outer `if` (no else) + inner `if` with NO ELSE EITHER, open-array read
  in the inner then. DECISIVE: if this fires, a single-statement then-body that
  is itself an `if` is not decomposed at all, and the else plays no part. If it
  is silent, the else is required, which points at how the grammar types the
  DANGLING-ELSE construct rather than at nesting. }
procedure V12(const F: string);
var
  Err: DWord;
begin
  if F <> '' then
    if Fill(F, Err) then
      Writeln(Format('%s %d', [F, Err]));
end;

end.
