unit uSrc;

interface

type
  TBag = class
  strict private
    FBig: Int64;
  public
    property Big: Int64 read FBig write FBig;
  end;

function Total: Int64;

implementation

function Total: Int64;
begin
  Result := 1;
end;

end.