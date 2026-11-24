unit FlowInit;

// redundant-field-init (G-33)

interface

uses
  System.Classes;

type
  TInner = class
  end;
  TRec2 = record
    A: Integer;
    constructor Create(N: Integer);
  end;
  TPlain = class
  private
    FCount: Integer;
    FName: string;
    FItem: TInner;
    FOn: Boolean;
    FOther: Integer;
    FLate: Integer;
    FStart: Integer;
    class var FShared: Integer;
    procedure SetValue(N: Integer);
  public
    constructor Create;
    constructor Make(N: Integer);
    constructor Named(FCount: Integer);
    property Value: Integer read FCount write SetValue;
  end;
  TKid = class(TPlain)
  protected
    FOwn: Integer;
  public
    constructor Create;
  end;
  THook = class(TComponent)
  private
    FDepth: Integer;
    FSafe: Integer;
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;
  TPool = class
  private
    FA: Integer;
  public
    class function NewInstance: TObject; override;
    constructor Create;
  end;

implementation

constructor TRec2.Create(N: Integer);
begin
  A := 0;
end;

constructor TPlain.Create;
begin
  inherited Create;
  FCount := 0; // FIRE redundant-field-init
  FName := ''; // FIRE redundant-field-init
  FItem := nil; // FIRE redundant-field-init
  Self.FOn := False; // FIRE redundant-field-init
  FOther := 1;
  FOther := 0;
  FShared := 0;
  Value := 0;
  FLate := 0;
end;

constructor TPlain.Make(N: Integer);
begin
  SetValue(N);
  FCount := 0;
  if N = 1 then FLate := 0;
end;

constructor TPlain.Named(FCount: Integer);
begin
  FCount := 0; // FIRE value-param-assigned
  FStart := FCount;
end;

procedure TPlain.SetValue(N: Integer);
begin
  FCount := N;
end;

constructor TKid.Create;
begin
  FOwn := 0; // FIRE redundant-field-init
  inherited Create;
  FName := '';
end;

constructor THook.Create(AOwner: TComponent);
begin
  FSafe := 0; // FIRE redundant-field-init
  inherited Create(AOwner);
  FDepth := 0;
end;

procedure THook.Loaded;
begin
  inherited;
  FDepth := 2;
end;

class function TPool.NewInstance: TObject;
begin
  Result := inherited NewInstance;
end;

constructor TPool.Create;
begin
  FA := 0;
end;

end.