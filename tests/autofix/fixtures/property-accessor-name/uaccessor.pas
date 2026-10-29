unit uaccessor;

interface

type
  TBox = class
  private
    FWidth: Integer;
    function Reader: Integer;
    procedure Writer(AValue: Integer);
  public
    property Count: Integer read Reader write Writer;
    property Size: Integer read FWidth;
  end;

implementation

function TBox.Reader: Integer;
begin
  Result:= FWidth * 2;
end;

procedure TBox.Writer(AValue: Integer);
begin
  FWidth:= AValue div 2;
end;

end.
