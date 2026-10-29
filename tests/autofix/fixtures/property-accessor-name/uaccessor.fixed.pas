unit uaccessor;

interface

type
  TBox = class
  private
    FSize: Integer;
    function GetCount: Integer;
    procedure SetCount(AValue: Integer);
  public
    property Count: Integer read GetCount write SetCount;
    property Size: Integer read FSize;
  end;

implementation

function TBox.GetCount: Integer;
begin
  Result:= FSize * 2;
end;

procedure TBox.SetCount(AValue: Integer);
begin
  FSize:= AValue div 2;
end;

end.
