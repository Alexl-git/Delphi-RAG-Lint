unit uInOnly;

interface

/// <summary>Two-way var param, the converter's shape: IN first, OUT after.</summary>
/// <param name="ANodes">IN: the current nodes, borrowed. OUT (only when the result is True): replacement nodes the caller now owns.</param>
function TwoWay(var ANodes: Integer): Boolean;

/// <summary>Input-only description on a var param -- must still fire.</summary>
/// <param name="AValue">Input value to use.</param>
procedure VarInputOnly(var AValue: Integer);

/// <summary>Input-only description on an out param -- must still fire.</summary>
/// <param name="ACount">In: the count.</param>
procedure OutInputOnly(out ACount: Integer);

/// <summary>An output marker inside another word is not a marker.</summary>
/// <param name="AMode">In: the layout to use, without changes.</param>
procedure NotAMarker(var AMode: Integer);

/// <summary>A by-value param is never graded by this rule.</summary>
/// <param name="AText">In: the text.</param>
procedure ByValueIn(AText: string);

/// <summary>Leading with Out is not input-only.</summary>
/// <param name="AResult">Out: the result.</param>
procedure LeadsWithOut(out AResult: Integer);

/// <summary>Input first, then returned -- two-way.</summary>
/// <param name="ABuf">Input buffer; the filled buffer is returned in it.</param>
procedure InputThenReturned(var ABuf: Integer);

implementation

function TwoWay(var ANodes: Integer): Boolean; begin ANodes := 1; Result := True; end;
procedure VarInputOnly(var AValue: Integer); begin AValue := AValue + 1; end;
procedure OutInputOnly(out ACount: Integer); begin ACount := 0; end;
procedure NotAMarker(var AMode: Integer); begin AMode := 0; end;
procedure ByValueIn(AText: string); begin if AText = '' then Exit; end;
procedure LeadsWithOut(out AResult: Integer); begin AResult := 0; end;
procedure InputThenReturned(var ABuf: Integer); begin ABuf := 2; end;

end.
