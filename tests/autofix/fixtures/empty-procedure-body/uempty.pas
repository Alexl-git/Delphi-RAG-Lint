unit uempty;

interface

type
  TBox = class
  private
    FCount: Integer;
    /// <summary>A forgotten stub.</summary>
    procedure Stub;
  public
    procedure Run;
  end;

implementation

procedure Lonely;
begin
end;

/// <summary>Body of the stub.</summary>
procedure TBox.Stub;
begin
end;

procedure TBox.Run;
begin
  FCount:= 1;
end;

end.
