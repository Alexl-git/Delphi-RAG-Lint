unit miss;

// Fixture for the missing-doc lint rule (ADF Task 7). Declarations:
//   Documented   -- public, HAS a real /// doc comment       -> NOT flagged
//   Undocumented -- public, has NO doc comment at all         -> FLAGGED (the one finding)
//   Stubbed      -- public, has a drag-lint MANAGED stub doc  -> NOT flagged (doc-drift's job)
//   TThing.Helper-- private class method, no doc              -> NOT flagged (private, exempt)

interface

/// <summary>Already documented; nothing to report here.</summary>
procedure Documented;

procedure Undocumented;

/// <summary>TODO: describe.</summary>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: (none)
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure Stubbed;

/// <summary>Documented container for the private-member exemption case below.</summary>
type
  TThing = class
  private
    procedure Helper;
  end;

implementation

procedure Documented;
begin
  // no-op
end;

procedure Undocumented;
begin
  // no-op
end;

procedure Stubbed;
begin
  // no-op
end;

procedure TThing.Helper;
begin
  // no-op
end;

end.
