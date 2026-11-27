unit UConfig;

{ G-61: a registrar. It declares no class of its own, has no initialization section, nothing uses it and the
  program code never names it; it registers a class of another unit with the Spring4D container. }

interface

procedure RegisterDependencies;

implementation

uses
  Spring.Container
  , UFoo
  ;

procedure RegisterDependencies;
begin
  GlobalContainer.RegisterType<TFoo>.Implements<IFoo>;
end;

end.