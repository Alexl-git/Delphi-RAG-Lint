unit fiRunner;

interface

type
  TRunner = class
  private
    FQueue: TObject;
  public
    constructor Create;
    procedure Init;
    procedure Run;
  end;

  TRunner2 = class
  private
    FQueue: TObject;
    FCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Init;
    procedure Run;
    procedure Reset;
  end;

implementation

constructor TRunner.Create;
begin
  inherited Create;
end;

procedure TRunner.Init;
begin
  FQueue:= TObject.Create;
end;

procedure TRunner.Run;
begin
  FQueue.ToString;    // USE-RUN
end;

constructor TRunner2.Create;
begin
  inherited Create;
  Init;
end;

destructor TRunner2.Destroy;
begin
  FQueue.ToString;    // USE-DESTROY
  FQueue.Free;        // USE-FREE
  inherited Destroy;
end;

procedure TRunner2.Init;
begin
  FQueue:= TObject.Create;
  FCount:= 1;
end;

procedure TRunner2.Run;
begin
  FQueue.ToString;    // USE-RUN2
end;

procedure TRunner2.Reset;
begin
  FQueue:= nil;
end;

end.