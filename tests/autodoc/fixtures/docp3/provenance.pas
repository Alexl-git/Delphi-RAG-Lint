unit provenance;

interface

function Marked(const AText: string): Integer;

/// <summary>Hand-written and must survive verbatim.</summary>
/// <returns>Observed: this is hand-written prose that merely starts with the word.</returns>
function HandWritten: Integer;

implementation

function Marked(const AText: string): Integer;
begin
  Result := Length(AText);
end;

function HandWritten: Integer;
begin
  Result := 1;
end;

end.
