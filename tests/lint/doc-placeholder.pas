unit DocPlaceholder;

// Fixture for lane v152 DOCPOL: doc-placeholder + doc-malformed-summary. No .expected
// (store-backed rules); driven by tests\autotest\run_v152_DOCPOL.ps1.
//   Placeholder -- summary "Summary here ..."           -> doc-placeholder
//   Real        -- a real summary                       -> silent (positive control for both rules)
//   Malformed   -- summary opens with a declaration     -> doc-malformed-summary (rule OFF by default)

interface

/// <summary>Summary here ...</summary>
procedure Placeholder;

/// <summary>Does a real thing and returns nothing.</summary>
procedure Real;

/// <summary>procedure Malformed(AValue: Integer);</summary>
procedure Malformed;

implementation

procedure Placeholder;
begin
  Real;
end;

procedure Real;
begin
  Malformed;
end;

procedure Malformed;
begin
  Placeholder;
end;

end.
