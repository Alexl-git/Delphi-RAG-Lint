unit uGenStore;

{ Fixture for run_interface_dispatch_generic.ps1 -- the TARGETS.
  IStore<T> is a GENERIC interface with two implementors: TIntStore lists the
  closed instance IStore<Integer>, TListStore<T> lists the open IStore<T>.
  IOther is a NON-generic interface declaring the same member names, implemented
  by TOtherStore, so a resolver that binds by bare member name is visible. }

interface

type
  IStore<T> = interface
    ['{2C3A1B10-0000-4000-8000-00000000C001}']
    function Get(Index: Integer): T;
    procedure Put(const AValue: T);
  end;

  IOther = interface
    ['{2C3A1B10-0000-4000-8000-00000000C002}']
    function Get(Index: Integer): Integer;
    procedure Put(const AValue: Integer);
  end;

  TIntStore = class(TInterfacedObject, IStore<Integer>)
  public
    function Get(Index: Integer): Integer;
    procedure Put(const AValue: Integer);
  end;

  TListStore<T> = class(TInterfacedObject, IStore<T>)
  public
    function Get(Index: Integer): T;
    procedure Put(const AValue: T);
  end;

  TOtherStore = class(TInterfacedObject, IOther)
  public
    function Get(Index: Integer): Integer;
    procedure Put(const AValue: Integer);
  end;

implementation

function TIntStore.Get(Index: Integer): Integer;
begin
  Result:= Index;
end;

procedure TIntStore.Put(const AValue: Integer);
begin
end;

function TListStore<T>.Get(Index: Integer): T;
begin
  Result:= Default(T);
end;

procedure TListStore<T>.Put(const AValue: T);
begin
end;

function TOtherStore.Get(Index: Integer): Integer;
begin
  Result:= -Index;
end;

procedure TOtherStore.Put(const AValue: Integer);
begin
end;

end.