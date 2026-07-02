unit sample;

interface

type
  ISomething = interface
    function Alpha: Integer;
    procedure Beta;
    function Gamma(A: Integer): string;
    procedure Delta;
  end;

  { TMiddle: 4 body methods, 3 of them pure one-line delegations to FImpl (a
    strict majority: 3*2 > 4). Must fire middle-man at the class decl line. }
  TMiddle = class
  private
    FImpl: ISomething;
    FTag : Integer;
  public
    function Alpha: Integer;
    procedure Beta;
    function Gamma(A: Integer): string;
    procedure DoWork;
  end;

  { TReal: 3 body methods, each real multi-statement work -- no delegation.
    Must NOT fire. }
  TReal = class
  private
    FImpl: ISomething;
    FSum : Integer;
  public
    procedure Accumulate;
    procedure Reset;
    function Total: Integer;
  end;

  { TTiny: only 2 delegating methods (below MIDDLE_MAN_MIN_METHODS=3).
    Must NOT fire even though both delegate to FImpl. }
  TTiny = class
  private
    FImpl: ISomething;
  public
    function Alpha: Integer;
    procedure Beta;
  end;

implementation

{ TMiddle }

function TMiddle.Alpha: Integer;
begin
  Result := FImpl.Alpha;
end;

procedure TMiddle.Beta;
begin
  FImpl.Beta;
end;

function TMiddle.Gamma(A: Integer): string;
begin
  Result := FImpl.Gamma(A);
end;

procedure TMiddle.DoWork;
begin
  FTag := FTag + 1;
  if FTag > 10 then
    FTag := 0;
end;

{ TReal }

procedure TReal.Accumulate;
begin
  FSum := FSum + 1;
  FImpl.Beta;
end;

procedure TReal.Reset;
begin
  FSum := 0;
  FImpl.Delta;
end;

function TReal.Total: Integer;
begin
  Result := FSum * 2;
  Result := Result + 1;
end;

{ TTiny }

function TTiny.Alpha: Integer;
begin
  Result := FImpl.Alpha;
end;

procedure TTiny.Beta;
begin
  FImpl.Beta;
end;

end.
