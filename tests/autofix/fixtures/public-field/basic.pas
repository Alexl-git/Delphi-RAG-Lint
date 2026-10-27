unit basic;

interface

type
  TWithPrivate = class
  private
    FOther: Integer;
  public
    Name: string;
    Size: Integer;
  end;

  TNoPrivate = class
  public
    Tag: Integer;
  end;

implementation

end.
