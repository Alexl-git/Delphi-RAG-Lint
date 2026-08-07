unit paramdoc;

{ Fixture for run_doc_p3_param_structure.ps1 -- PHASE A3 (rulings D-3 and D-4)
  and PHASE A4 (doc-drift must accept what A3 emits).

  D-3: an automatic generator supplies STRUCTURE, not MEANING. Every signature
  parameter gets a <param name="..."> tag; the tag's BODY is filled only where
  the SOURCE carries the meaning -- a comment sitting beside that parameter
  inside the parameter list.

  D-4: a <param> has a structure part and a meaning part. The structure is
  regenerated; a hand-written meaning is never overwritten.

  Driver calls each routine with explicit parentheses so every one carries a
  caller fact and therefore renders a doc block at all -- see harvest_text.pas
  for why that device is load-bearing rather than decorative. }

interface

// Structure only: neither parameter carries a comment, so both get a tag with
// no body. This is the shape doc-drift used to report as "has no <param> tag"
// while `document` refused to write one -- the contradiction PHASE A4 closes.
function Plain(AFirst: Integer; ASecond: string): Integer;

// Meaning harvested from inside the parameter list, one comment per parameter.
function Noted(AFirst: Integer { how many times to repeat };
               ASecond: string { the label shown to the user }): Integer;

// A GROUP comment after the shared type belongs to every name in that group;
// a comment beside ONE name belongs to that name alone.
function Grouped(ALeft { the left edge }, ARight: Integer { a coordinate, in pixels }): Integer;

// Hand-written meaning that a re-run must not touch (D-4).
/// <summary>Hand-written, and authoritative.</summary>
/// <param name="AKept">Hand-written meaning that must survive every re-run.</param>
function Kept(AKept: Integer): Integer;

function Driver: Integer;

implementation

function Plain(AFirst: Integer; ASecond: string): Integer;
begin
  Result := AFirst + Length(ASecond);
end;

function Noted(AFirst: Integer; ASecond: string): Integer;
begin
  Result := AFirst + Length(ASecond);
end;

function Grouped(ALeft, ARight: Integer): Integer;
begin
  Result := ALeft + ARight;
end;

function Kept(AKept: Integer): Integer;
begin
  Result := AKept;
end;

function Driver: Integer;
begin
  Result := Plain(1, 'a') + Noted(2, 'b') + Grouped(3, 4) + Kept(5);
end;

end.
