unit uWsLib;

{ Library half of the with-scope fixture (run_with_scope_bind.ps1). Every type
  here is a possible `with` target; the member names deliberately collide with
  names the host class, the unit and the enum also declare, so a binding that
  ignores the with scope lands on the WRONG declaration and the guard can see it. }

interface

type
  TWsMode = (wmAlpha, wmBeta, Kind);

  TWsRec = record
    Kind : Integer;
    Count: Integer;
    function Total: Integer;
    procedure Reset;
  end;

  TWsInner = class
  public
    Value: Integer;
    procedure Ping;
  end;

  TWsObj = class
  private
    FInner: TWsInner;
    function GetSize: Integer;
  public
    Name: string;
    procedure Execute;
    function Count: Integer;
    property Size: Integer read GetSize;
    property Inner: TWsInner read FInner;
  end;

  TWsOther = class
  public
    Name: string;
    procedure Execute;
  end;

  TWsDerived = class(TUnknownBase)
  public
    procedure Own;
  end;

procedure Execute;

implementation

function TWsRec.Total: Integer;
begin
  Result := Count + 1;
end;

procedure TWsRec.Reset;
begin
  Count := 0;
end;

procedure TWsInner.Ping;
begin
  Value := Value + 1;
end;

function TWsObj.GetSize: Integer;
begin
  Result := 3;
end;

procedure TWsObj.Execute;
begin
  Name := 'x';
end;

function TWsObj.Count: Integer;
begin
  Result := 2;
end;

procedure TWsOther.Execute;
begin
  Name := 'y';
end;

procedure TWsDerived.Own;
begin
end;

procedure Execute;
begin
end;

end.