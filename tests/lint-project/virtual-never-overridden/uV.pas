unit uV;

interface

type
  TVnoShape = class
  public
    procedure DrawA; virtual;
    procedure DrawB; virtual;
    procedure DrawC; virtual; abstract;
    procedure DrawD; dynamic;
    constructor Create; virtual;
  end;

  TCircle = class(TVnoShape)
  public
    procedure DrawB; override;
  end;

implementation

constructor TVnoShape.Create;
begin
end;

procedure TVnoShape.DrawA;
begin
end;

procedure TVnoShape.DrawB;
begin
end;

procedure TVnoShape.DrawD;
begin
end;

procedure TCircle.DrawB;
begin
end;

end.
