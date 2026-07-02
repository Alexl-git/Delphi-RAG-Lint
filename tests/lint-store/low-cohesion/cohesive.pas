unit cohesive;

interface

type
  TCohesive = class
  private
    FShared: Integer;
  public
    procedure First;
    procedure Second;
  end;

implementation

procedure TCohesive.First;
begin
  FShared:= 1;
end;

procedure TCohesive.Second;
begin
  FShared:= FShared + 1;
end;

end.
