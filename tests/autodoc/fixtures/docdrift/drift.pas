unit drift;

// Fixture for the TDocDrift engine (ADF Task 6). Each decl below CARRIES a
// stale DocInsight comment on purpose -- drift is only about DOCUMENTED decls.
// The comments here are the "before" (stale) state the engine must diff against
// the live signatures / body facts.

interface

type
  EFoo = class(Exception);

  /// <summary>Does a thing with the input value.</summary>
  /// <param name="Old">The old parameter that was since renamed.</param>
  /// <returns>The formatted result string.</returns>
  function F(New: Integer): string;

  /// <summary>Runs a side effect.</summary>
  /// <returns>Nothing useful -- this returns tag is spurious.</returns>
  procedure P;

  /// <summary>Reads a record by key.</summary>
  /// <param name="Key">The lookup key.</param>
  /// <exception cref="EFoo">Documented but never actually raised.</exception>
  function Lookup(Key: Integer): string;

implementation

uses
  System.SysUtils;

function F(New: Integer): string;
begin
  Result := IntToStr(New);
end;

procedure P;
begin
  // pure side effect, no result
end;

function Lookup(Key: Integer): string;
begin
  // Documents EFoo but raises nothing.
  Result := IntToStr(Key);
end;

end.
