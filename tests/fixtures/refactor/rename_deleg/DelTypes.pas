unit DelTypes;

interface

type
  IFoo = interface
    ['{6F1E3C70-5B5A-4C0E-9C11-0D1E3F6A7B01}']
    procedure Bar;
  end;

  { A class that does NOT list IFoo: only a delegating property reaches it. }
  TBare = class
  public
    procedure Bar;
  end;

  { Delegation to a CLASS-typed field: TAgg answers IFoo.Bar through TBare.Bar. }
  TAgg = class(TInterfacedObject, IFoo)
  private
    FImpl: TBare;
  public
    constructor Create;
    destructor Destroy; override;
    property Impl: TBare read FImpl implements IFoo;
  end;

  { Delegation to an INTERFACE-typed field: the implementor lists IFoo itself. }
  TFull = class(TInterfacedObject, IFoo)
  public
    procedure Bar;
  end;

  TAgg2 = class(TInterfacedObject, IFoo)
  private
    FInner: IFoo;
  public
    constructor Create;
    property Inner: IFoo read FInner implements IFoo;
  end;

implementation

procedure TBare.Bar;
begin
  Writeln('bare bar');
end;

constructor TAgg.Create;
begin
  inherited Create;
  FImpl:= TBare.Create;
end;

destructor TAgg.Destroy;
begin
  FImpl.Free;
  inherited;
end;

procedure TFull.Bar;
begin
  Writeln('full bar');
end;

constructor TAgg2.Create;
begin
  inherited Create;
  FInner:= TFull.Create;
end;

end.
