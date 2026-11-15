unit MethodOrder;

interface

type
  TKunde = class
  public
    constructor Create;
    procedure Speichern;
    procedure Laden;
  end;

  TOrdered = class
  public
    procedure A;
    procedure B;
  end;

implementation

{ TKunde }

procedure TKunde.Speichern;
begin
end;

constructor TKunde.Create;
begin
end;

procedure TKunde.Laden;
begin
end;

{ TOrdered }

procedure TOrdered.A;
begin
end;

procedure TOrdered.B;
begin
end;

end.
