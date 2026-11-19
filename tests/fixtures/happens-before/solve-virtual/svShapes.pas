unit svShapes;

interface

type
  TBaseInit = class
  public
    procedure Init; virtual;
  end;

  TAInit = class(TBaseInit)
  public
    procedure Init; override;
  end;

  TBInit = class(TBaseInit)
  public
    procedure Init; override;
  end;

var
  GAll: Integer;
  GPart: Integer;

procedure UseShapes;

implementation

procedure TBaseInit.Init;
begin
  GAll:= 1;
  GPart:= 1;
end;

procedure TAInit.Init;
begin
  GAll:= 2;
  GPart:= 2;
end;

procedure TBInit.Init;
begin
  GAll:= 3;
end;

procedure UseShapes;
begin
  Writeln(GAll + GPart); // USE-VIRTUAL
end;

end.
