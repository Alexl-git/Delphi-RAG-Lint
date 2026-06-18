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
  ImplOnlyHelper(KNOWN_CONST);   { v0.48: call the impl-only free routine }
end;

{ v0.48: an IMPLEMENTATION-ONLY free routine -- declared nowhere in the interface.
  Before v0.48 the indexer emitted no symbol for it (interface-decl-is-source-of-
  truth dedup), so `query --name ImplOnlyHelper` returned nothing. This fixture +
  the smoke assertions guard that. The body spans several lines so the v0.48 body
  line-range (impl_start_line/impl_end_line) is non-trivial. }
procedure ImplOnlyHelper(AValue: Integer);
begin
  if AValue > 0 then
    ImplOnlyHelper(AValue - 1);   { self-call -> find-callers also has a ref }
end;

end.


