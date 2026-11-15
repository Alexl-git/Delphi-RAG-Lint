unit MissingInheritedHooksClean;
{ look-alikes: hooks that call inherited, and a plain procedure whose name only
  contains the hook name. }
interface
type
  TWatcher = class(TObject)
  public
    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;
    procedure AfterConstructionDone;
  end;

implementation

procedure TWatcher.AfterConstruction;
begin
  inherited;
  Register(Self);
end;

procedure TWatcher.BeforeDestruction;
begin
  Unregister(Self);
  inherited BeforeDestruction;
end;

procedure TWatcher.AfterConstructionDone;
begin
  Register(Self);
end;

type
  TCountedStream = class(TMemoryStream)
  protected
    FRefCount: Integer;
  public
    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;
  end;

{ its own reference count, the TInterfacedObject idiom: no inherited needed }
procedure TCountedStream.AfterConstruction;
begin
  AtomicDecrement(FRefCount);
end;

procedure TCountedStream.BeforeDestruction;
begin
  if FRefCount <> 0 then Error(reInvalidPtr);
end;

end.
