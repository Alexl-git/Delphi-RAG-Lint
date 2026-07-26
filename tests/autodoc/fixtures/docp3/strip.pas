unit strip;

interface

// An ordinary implementation-style comment that must survive untouched.
/// <summary>Hand-written summary; must survive.</summary>
/// <param name="AValue">Hand-written param desc; must survive.</param>
/// <remarks>Hand-written remarks prose; must survive.</remarks>
function Mixed(AValue: Integer): Integer;

function Plain(AValue: Integer): Integer;

implementation

function Mixed(AValue: Integer): Integer;
begin
  Result := AValue;
end;

function Plain(AValue: Integer): Integer;
begin
  Result := AValue + 1;
end;

end.
