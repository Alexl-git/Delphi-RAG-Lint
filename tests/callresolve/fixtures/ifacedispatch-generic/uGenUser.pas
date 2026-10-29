unit uGenUser;

{ Fixture for run_interface_dispatch_generic.ps1 -- the CALL SITES.
  Every IS<n> site calls through a receiver typed as an INSTANCE of the generic
  interface IStore<T>; the owner ruling (2026-09-16) attributes it to the
  interface method IStore.Get / IStore.Put, never to an implementor. OT1 is the
  positive control: the non-generic IOther binds IOther.Get. }

interface

uses
  uGenStore;

type
  TGenUser = class
  private
    FStore: IStore<string>;
  public
    procedure Run(P: IStore<Integer>);
  end;

implementation

procedure TGenUser.Run(P: IStore<Integer>);
var
  L: IStore<Integer>;
  O: IOther;
  N: Integer;
begin
  L:= TIntStore.Create;
  N:= L.Get(1);
  N:= P.Get(2);
  FStore.Put('field');
  P.Put(N);
  O:= TOtherStore.Create;
  N:= O.Get(3);
end;

end.