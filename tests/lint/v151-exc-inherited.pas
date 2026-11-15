unit v151_exc_inherited;

interface

type
  TBase = class(TObject)
  protected
    procedure Loaded; virtual;
    procedure Speichern; virtual;
    procedure Rest; virtual;
  end;

  TKid = class(TBase)
  private
    FList: TObject;
    FOther: TObject;
  protected
    procedure Loaded; override;
    procedure Speichern; override;
    procedure Rest; override;
    procedure Vorbereiten;
    procedure Plain;
    procedure WMSize(var Msg: TMessage); message WM_SIZE;
    procedure WMPaint(var Msg: TMessage); message WM_PAINT;
    procedure WMMove(var Msg: TMessage); message WM_MOVE;
  public
    destructor Destroy; override;
    procedure CreateParams(var P: Integer); override;
  end;

implementation

procedure TBase.Loaded;
begin
end;

procedure TBase.Speichern;
begin
end;

procedure TBase.Rest;
begin
end;

procedure TKid.Loaded;
begin
  Plain;
end;

procedure TKid.Speichern;
begin
  inherited Laden;
  Plain;
end;

procedure TKid.Rest;
begin
  inherited;
end;

procedure TKid.Vorbereiten;
begin
  inherited;
  FList.Clear;
end;

procedure TKid.Plain;
begin
  inherited Rest;
end;

procedure TKid.WMSize(var Msg: TMessage);
begin
  Plain;
end;

procedure TKid.WMPaint(var Msg: TMessage);
begin
  inherited;
end;

procedure TKid.WMMove(var Msg: TMessage);
begin
  Msg.Result := 0;
end;

destructor TKid.Destroy;
begin
  inherited;
  FList.Free;
  FOther.Free;
end;

procedure TKid.CreateParams(var P: Integer);
begin
  P := 1;
end;

end.
