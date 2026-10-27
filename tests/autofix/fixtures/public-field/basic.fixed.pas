unit basic;

interface

type
  TWithPrivate = class
  private
    FSize: Integer;
    FName: string;
    FOther: Integer;
  public
    property Name: string read FName write FName;
    property Size: Integer read FSize write FSize;
  end;

  TNoPrivate = class
  private
    FTag: Integer;
  public
    property Tag: Integer read FTag write FTag;
  end;

implementation

end.
