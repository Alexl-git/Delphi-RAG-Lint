unit fcData;

interface

type
  TBoth = class
  private
    FList: TObject;
    FHalf: TObject;
    FHelped: TObject;
    procedure Prepare;
  public
    constructor Create;
    constructor CreateFor(pN: Integer);
    constructor CreateChained;
    procedure Run;
  end;

  TPeer = class
  private
    FData: TObject;
  public
    constructor Create;
    procedure Show;
  end;

  TPeerBad = class
  private
    FData: TObject;
  public
    constructor Create(pPeer: TPeerBad);
    procedure Show;
  end;

  TEarly = class
  private
    FLog: TObject;
  public
    constructor Create;
    procedure Peek;
  end;

  TEarly2 = class
  private
    FLog: TObject;
  public
    constructor Create;
    procedure Peek;
  end;

implementation

procedure TBoth.Prepare;
begin
  FHelped:= TObject.Create;
end;

constructor TBoth.Create;
begin
  inherited Create;
  FList:= TObject.Create;
  FHalf:= TObject.Create;
  Prepare;
end;

constructor TBoth.CreateFor(pN: Integer);
begin
  inherited Create;
  Self.FList:= TObject.Create;
  Self.Prepare;
end;

constructor TBoth.CreateChained;
begin
  Create;
end;

procedure TBoth.Run;
begin
  FList.ToString;     // USE-LIST
  FHalf.ToString;     // USE-HALF
  FHelped.ToString;   // USE-HELPED
end;

constructor TPeer.Create;
begin
  inherited Create;
  FData:= TObject.Create;
end;

procedure TPeer.Show;
begin
  FData.ToString;     // USE-PEER
end;

constructor TPeerBad.Create(pPeer: TPeerBad);
begin
  inherited Create;
  pPeer.FData:= TObject.Create;
end;

procedure TPeerBad.Show;
begin
  FData.ToString;     // USE-PEERBAD
end;

constructor TEarly.Create;
begin
  inherited Create;
  Peek;
  FLog:= TObject.Create;
end;

procedure TEarly.Peek;
begin
  FLog.ToString;      // USE-EARLY
end;

constructor TEarly2.Create;
begin
  inherited Create;
  FLog:= TObject.Create;
  FLog.ToString;      // USE-EARLY2-CTOR
  Peek;
end;

procedure TEarly2.Peek;
begin
  FLog.ToString;      // USE-EARLY2
end;

end.
