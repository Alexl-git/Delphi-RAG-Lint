unit unitB;

interface

uses
  unitA;

type
  TWidget = class
  public
    // Public method that calls unitA.Alpha(...) -> carries a Calls fact so the
    // facts-only default keeps it (a managed block is emitted).
    function Compute(X: Integer): Integer;
  end;

implementation

function TWidget.Compute(X: Integer): Integer;
begin
  Result := Alpha(X) * 2;
end;

end.
