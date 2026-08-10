unit doc_idem_unit;

{ Fixture for run_doc_idempotent_unit.ps1 -- the UNIT-SCALE idempotency lock.

  The existing run_doc_idempotent.ps1 locks ONE symbol via --qname in a
  two-symbol fixture, and that is why a corpus-scale convergence failure got
  past it. This fixture reproduces the two shapes that actually broke:

    1. NESTED ROUTINES inside a large outer body. Autodoc documents nested
       routines too, and those doc lines land INSIDE the outer routine's
       implementation span -- so the outer routine's own
       "N lines (full implementation)" fact changes BECAUSE it was documented.
       A fact that its own emission invalidates cannot reach a fixed point.

    2. PARAMETERS of several shapes -- const / var / grouped names sharing one
       type / a defaulted parameter -- because the <param> tag set is
       regenerated from the indexed signature on every run, and any per-run
       instability in how a name or type is rendered rewrites the block
       forever (see the scar comment on ParseParamNames in
       DRagLint.Refactor.DocStub).

  Nothing here is documented by hand: the whole file is the "no original doc
  from the user" case, which is exactly the case the owner's acceptance gate
  names -- a second run must produce 0 edits. }

interface

type
  TShape = record
    Width : Integer;
    Height: Integer;
  end;

function AreaOf(const AShape: TShape; AScale: Integer = 1): Integer;
function Classify(const AShape: TShape; var AReason: string): string;
procedure Grow(var AShape: TShape; ADx, ADy: Integer);

implementation

{ Outer routine with TWO nested routines, and a cyclomatic complexity ABOVE the
  docs.complexity_min threshold (default 10) so the 'Complexity: N (cyclomatic,
  outer body), M lines (full implementation)' fact is actually EMITTED. Both
  conditions are required to reproduce the corpus failure: below the threshold
  the unstable fact is never written, and without nested routines nothing
  inserts lines INSIDE this routine's own implementation span. }
function AreaOf(const AShape: TShape; AScale: Integer = 1): Integer;

  function Clamp(AValue: Integer): Integer;
  begin
    if AValue < 0 then Result := 0 else Result := AValue;
  end;

  function Scaled(AValue: Integer): Integer;
  begin
    if AScale > 1 then Result := AValue * AScale else Result := AValue;
  end;

var
  I, Acc: Integer;
begin
  Acc := 0;
  if (AShape.Width > 0) and (AShape.Height > 0) then
  begin
    for I := 1 to AScale do
    begin
      if (I mod 2) = 0 then Acc := Acc + 1
      else if (I mod 3) = 0 then Acc := Acc + 2
      else if (I mod 5) = 0 then Acc := Acc + 3;
      while (Acc > 100) and (I > 0) do Acc := Acc - 50;
      case I of
        1: Acc := Acc + 1;
        2: Acc := Acc + 2;
        3: Acc := Acc + 3;
      end;
    end;
  end
  else if (AShape.Width < 0) or (AShape.Height < 0) then
    Acc := -1;
  repeat
    Inc(Acc);
  until (Acc >= 0) or (AScale = 0);
  Result := Scaled(Clamp(AShape.Width) * Clamp(AShape.Height)) + Acc;
end;

function Classify(const AShape: TShape; var AReason: string): string;
begin
  if (AShape.Width <= 0) or (AShape.Height <= 0) then
  begin
    AReason := 'degenerate';
    Exit('none');
  end;
  if AShape.Width = AShape.Height then
  begin
    AReason := 'equal sides';
    Result := 'square';
  end
  else
  begin
    AReason := 'unequal sides';
    Result := 'rectangle';
  end;
end;

procedure Grow(var AShape: TShape; ADx, ADy: Integer);
begin
  Inc(AShape.Width, ADx);
  Inc(AShape.Height, ADy);
end;

end.
