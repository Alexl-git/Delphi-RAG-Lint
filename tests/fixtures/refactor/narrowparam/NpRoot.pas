unit NpRoot;

// The top of the chain; NpUse does not use this unit, so narrowing to TRoot must add it.

interface

type
  TRoot = class
  public
    RootField: Integer;
    procedure RootOnly;
  end;

implementation

procedure TRoot.RootOnly;
begin
end;

end.