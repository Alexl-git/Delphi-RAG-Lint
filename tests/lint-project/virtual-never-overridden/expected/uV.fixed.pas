unit uV;

interface

type
  TShape = class
  public
    procedure DrawA;
    procedure DrawB; virtual;
    procedure DrawC; virtual; abstract;
    procedure DrawD;
    constructor Create; virtual;
  end;

  TCircle = class(TShape)
  public
    procedure DrawB; override;
  end;

implementation

constructor TShape.Create;
begin
end;

procedure TShape.DrawA;
begin
end;

procedure TShape.DrawB;
begin
end;

procedure TShape.DrawD;
begin
end;

procedure TCircle.DrawB;
begin
end;

end.
