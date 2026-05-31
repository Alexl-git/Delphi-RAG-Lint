unit SampleUnit;

interface

uses
  System.SysUtils;

type
  EKnownException = class(Exception);

  IKnownInterface = interface
    ['{12345678-1234-1234-1234-123456789012}']
    procedure KnownInterfaceMethod;
  end;

  TKnownClass = class(TInterfacedObject, IKnownInterface)
  strict private
    FKnownField: Integer;
    function GetKnownProp: string;
    procedure SetKnownProp(const Value: string);
  public
    constructor Create(AInitial: Integer);
    destructor Destroy; override;
    procedure KnownMethod(AParam: Integer);
    procedure KnownInterfaceMethod;
    property KnownProp: string read GetKnownProp write SetKnownProp;
  end;

const
  KNOWN_CONST = 42;

implementation

constructor TKnownClass.Create(AInitial: Integer);
begin
  inherited Create;
  FKnownField := AInitial;
end;

destructor TKnownClass.Destroy;
begin
  inherited Destroy;
end;

function TKnownClass.GetKnownProp: string;
begin
  Result := IntToStr(FKnownField);
end;

procedure TKnownClass.SetKnownProp(const Value: string);
begin
  FKnownField := StrToIntDef(Value, 0);
end;

procedure TKnownClass.KnownMethod(AParam: Integer);
begin
  FKnownField := FKnownField + AParam;
  if AParam > 0 then
    KnownMethod(AParam - 1);
end;

procedure TKnownClass.KnownInterfaceMethod;
begin
  KnownMethod(KNOWN_CONST);
end;

end.


