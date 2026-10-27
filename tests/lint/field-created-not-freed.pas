unit field_created_not_freed;

{ field-created-not-freed fixture.  HIT marker = the rule must fire on that line,
  OK marker = it must stay silent.  Known FP shape: a field handed to a global
  registry through a non-call (property assignment) is still reported. }

interface

uses
  System.Classes;

type
  TLeaky = class
  private
    FLeak: TStringList;
  public
    constructor Create;
  end;

  TFine = class
  private
    FA: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  TClearer = class
  private
    FB: TStringList;
  public
    constructor Create;
    procedure Clear;
  end;

  TTransfer = class
  private
    FC: TStringList;
  public
    constructor Create;
  end;

  TCompOwner = class(TComponent)
  private
    FD: TComponent;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TIntfHolder = class
  private
    FE: IInterface;
  public
    constructor Create;
  end;

  TControlHolder = class
  private
    FPanel: TComponent;
    FLabel: TLabel;
  public
    constructor Create;
  end;

implementation

procedure Register(AList: TStringList);
begin
  AList.Clear;
end;

constructor TLeaky.Create;
begin
  inherited Create;
  FLeak:= TStringList.Create; {HIT}
end;

constructor TFine.Create;
begin
  inherited Create;
  FA:= TStringList.Create; {OK}
end;

destructor TFine.Destroy;
begin
  FreeAndNil(FA);
  inherited Destroy;
end;

constructor TClearer.Create;
begin
  inherited Create;
  FB:= TStringList.Create; {OK}
end;

procedure TClearer.Clear;
begin
  FB.Free;
end;

constructor TTransfer.Create;
begin
  inherited Create;
  FC:= TStringList.Create; {OK}
  Register(FC);
end;

constructor TCompOwner.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FD:= TComponent.Create(Self); {OK}
end;

constructor TIntfHolder.Create;
begin
  inherited Create;
  FE:= TInterfacedObject.Create; {OK}
end;

constructor TControlHolder.Create;
begin
  inherited Create;
  FLabel:= TLabel.Create(FPanel); {OK}
end;

end.
