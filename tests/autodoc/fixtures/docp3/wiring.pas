unit wiring;

interface

type
  IFolderService = interface
    ['{2F1B6A1E-6D9C-4C3A-9A55-0B0C1D2E3F40}']
    procedure Refresh;
  end;

  TFolderService = class(TInterfacedObject, IFolderService)
  public
    procedure Refresh;
  end;

  // The negative control: a class with no DI registration at all. It must get
  // no 'Registered as:' line, which is only meaningful because it HAS a doc
  // block for another reason (its method is called by RegisterAll).
  TUnregistered = class
  public
    procedure Poke;
  end;

procedure RegisterAll;

implementation

uses
  Spring.Container;

procedure TFolderService.Refresh;
begin
end;

procedure TUnregistered.Poke;
begin
end;

procedure RegisterAll;
var
  U: TUnregistered;
begin
  GlobalContainer.RegisterType<TFolderService>.Implements<IFolderService>.AsSingleton;
  U := nil;
  U.Poke;
end;

end.
