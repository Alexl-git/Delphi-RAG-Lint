unit uDiShapes;

interface

type
  TDiCache = class
  public
    procedure Register(const AKey, AValue: string);
    function RegisterType(const AName: string): TDiCache;
  end;

procedure UseCache(C: TDiCache);
procedure UseContainer;

implementation

procedure TDiCache.Register(const AKey, AValue: string);
begin
end;

function TDiCache.RegisterType(const AName: string): TDiCache;
begin
  Result:= Self;
end;

procedure UseCache(C: TDiCache);
begin
  C.Register('k', 'v');
  C.RegisterType('x').Register('a', 'b');
end;

procedure UseContainer;
begin
  GlobalContainer.RegisterInstance<IFoo>(Foo);
  FContainer.RegisterType(TypeInfo(TFoo));
  GlobalContainer.RegisterType<TFoo>.Implements<IFoo>.AsSingleton;
  GlobalContainer.RegisterType<TBar>;
end;

end.
