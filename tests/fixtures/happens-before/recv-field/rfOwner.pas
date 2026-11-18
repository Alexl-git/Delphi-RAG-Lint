unit rfOwner;

{ check-init fixture recv-field (lane HBRECV, spec 5.6): the receiver is a FIELD of the caller's object,
  set and initialized in the owner's constructor. TOwner (SET) is the twin of every MAY case:
  TOwnerB never calls Init, TOwnerR re-assigns the field outside the constructor, TOwnerC calls Go from
  its constructor before the Init. }

interface

type
  TFw = class
  private
    FData: TObject;
  public
    procedure Init;
    procedure Run;
  end;

  TFwB = class
  private
    FData: TObject;
  public
    procedure Init;
    procedure Run;
  end;

  TFwR = class
  private
    FData: TObject;
  public
    procedure Init;
    procedure Run;
  end;

  TFwC = class
  private
    FData: TObject;
  public
    procedure Init;
    procedure Run;
  end;

  TOwner = class
  private
    FW: TFw;
  public
    constructor Create;
    procedure Go;
  end;

  TOwnerB = class
  private
    FW: TFwB;
  public
    constructor Create;
    procedure Go;
  end;

  TOwnerR = class
  private
    FW: TFwR;
  public
    constructor Create;
    procedure Go;
    procedure Replace;
  end;

  TOwnerC = class
  private
    FW: TFwC;
  public
    constructor Create;
    procedure Go;
  end;

implementation

procedure TFw.Init;
begin
  FData:= TObject.Create;
end;

procedure TFw.Run;
begin
  FData.ToString;    // USE-FW
end;

procedure TFwB.Init;
begin
  FData:= TObject.Create;
end;

procedure TFwB.Run;
begin
  FData.ToString;    // USE-FWB
end;

procedure TFwR.Init;
begin
  FData:= TObject.Create;
end;

procedure TFwR.Run;
begin
  FData.ToString;    // USE-FWR
end;

procedure TFwC.Init;
begin
  FData:= TObject.Create;
end;

procedure TFwC.Run;
begin
  FData.ToString;    // USE-FWC
end;

constructor TOwner.Create;
begin
  inherited Create;
  FW:= TFw.Create;
  FW.Init;
end;

procedure TOwner.Go;
begin
  FW.Run;
end;

constructor TOwnerB.Create;    // SITE-FWB
begin
  inherited Create;
  FW:= TFwB.Create;
end;

procedure TOwnerB.Go;
begin
  FW.Run;
end;

constructor TOwnerR.Create;
begin
  inherited Create;
  FW:= TFwR.Create;
  FW.Init;
end;

procedure TOwnerR.Go;
begin
  FW.Run;
end;

procedure TOwnerR.Replace;
begin
  FW:= TFwR.Create;    // SITE-FWR
end;

constructor TOwnerC.Create;
begin
  inherited Create;
  FW:= TFwC.Create;
  Go;    // SITE-FWC
  FW.Init;
end;

procedure TOwnerC.Go;
begin
  FW.Run;
end;

end.
