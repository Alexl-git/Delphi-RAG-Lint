unit markededit;

interface

/// <summary><!-- drag-lint:auto -->A developer typed this after the marker.</summary>
/// <param name="AValue"><!-- drag-lint:auto -->Also typed after the marker.</param>
/// <returns><!-- drag-lint:auto -->Also typed here after the marker.</returns>
function Foo(AValue: Integer): Integer;

function Bar(AValue: Integer): Integer;

implementation

function Foo(AValue: Integer): Integer;
begin
  Result := AValue;
end;

function Bar(AValue: Integer): Integer;
begin
  Result := AValue;
end;

end.
