unit uprivspec;

{ Private members used ONLY in a property's stored / index / default
  specifier (the index stores no ref from a property declaration). They
  must not be flagged and the fix must not delete them; FDead is the
  positive control. }

interface

type
  TSpec = class
  private
    const IDX_Y = 3;
    const DEF_X = 7;
  private
    FX: Integer;
    FDead: Integer;
    function IsXStored: Boolean;
    function GetY(AIndex: Integer): Integer;
    procedure SetX(AValue: Integer);
  published
    property X: Integer read FX write SetX stored IsXStored default DEF_X;
    property Y: Integer index IDX_Y read GetY;
  end;

implementation

function TSpec.IsXStored: Boolean;
begin
  Result:= FX <> DEF_X;
end;

function TSpec.GetY(AIndex: Integer): Integer;
begin
  Result:= AIndex;
end;

procedure TSpec.SetX(AValue: Integer);
begin
  FX:= AValue;
end;

end.