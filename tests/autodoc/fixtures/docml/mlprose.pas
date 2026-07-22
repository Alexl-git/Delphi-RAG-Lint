unit mlprose;
interface
/// <summary>First line of a summary that is deliberately written across
/// several source lines to exercise the multi-line prefix handling in the
/// merge step of document --apply.</summary>
/// <param name="AValue">A parameter whose description also spans
/// two source lines to be sure params re-prefix too.</param>
/// <returns>A result whose description spans
/// multiple source lines as well.</returns>
/// <remarks>
/// Hand-written remarks prose that also spans
/// two lines and must keep its /// prefix.
/// </remarks>
function Frob(const AValue: Integer): Boolean;
implementation
function Frob(const AValue: Integer): Boolean;
begin
  Result:= AValue > 0;
end;
end.
