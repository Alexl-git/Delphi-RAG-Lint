unit GA_IsDotted;

{ Grammar-shape audit fixture, shape (b), store-backed rules: is-always-true
  and is-never-true read the right of `is` through TRefTypeScan.WrittenType.
  Grammar v1.4.5 spells a dotted type there `typerefDot` (was `exprDot`). }

interface

type
  TBase = class
  end;

  TLeaf = class(TBase)
  end;

  TOther = class
  end;

procedure Probe(pLeaf: TLeaf; pFlag: Boolean);

implementation

procedure Probe(pLeaf: TLeaf; pFlag: Boolean);
var
  LHits: Integer;
begin
  LHits := 0;
  if pLeaf is TBase then Inc(LHits);
  if pLeaf is GA_IsDotted.TBase then Inc(LHits);
  if pLeaf is TBase and pFlag then Inc(LHits);
  if pLeaf is TOther then Inc(LHits);
  if pLeaf is GA_IsDotted.TOther then Inc(LHits);
  if LHits > 0 then pLeaf.Free;
end;

end.
