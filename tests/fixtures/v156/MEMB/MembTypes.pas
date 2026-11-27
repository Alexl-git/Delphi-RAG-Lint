unit MembTypes;

{ v156 MEM-B fixture: the callees. What each one does with its parameter decides the callers in MembFresh. }

interface

type
  TFoo = class
  public
    Name: string;
    procedure Touch;
  end;

  IBar = interface
    ['{6E1B0C0A-55F1-4D0B-9C0B-1D5C1E5A7B01}']
    procedure Ping;
  end;

  TBar = class(TInterfacedObject, IBar)
  public
    procedure Ping;
  end;

  TDeepBar = class(TBar)
  end;

  { not reference counted: its own _AddRef / _Release }
  TPlainBar = class(TObject, IBar)
  public
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
    procedure Ping;
  end;

  { stands in for the VCL class: the fixture is indexed without a library }
  TComponent = class
  public
    constructor Create(AOwner: TComponent);
  end;

  TWidget = class(TComponent)
  end;

  TKeeper = class
  private
    FFoo: TFoo;
  public
    constructor Create(AFoo: TFoo);
    procedure Keep(AFoo: TFoo);
    procedure Show(AFoo: TFoo);
    procedure ShowConst(const AFoo: TFoo);
    function Same(AFoo: TFoo): TFoo;
    procedure Eat(AFoo: TFoo);
    procedure Pass(AFoo: TFoo);
    procedure Later(AFoo: TFoo);
    procedure Hook(AFoo: TFoo); virtual;
    procedure Second(ACount: Integer; AFoo: TFoo);
  end;

procedure ReadOnly(AFoo: TFoo);
procedure StoreGlobal(AFoo: TFoo);
procedure ReleaseIt(AFoo: TFoo);
procedure UseBar(const ABar: IBar);
procedure TakeBar(ABar: IBar);
procedure ShowObject(AObject: TObject);

implementation

var
  GFoo: TFoo;

procedure TFoo.Touch;
begin
  Name:= Name + '.';
end;

procedure TBar.Ping;
begin
end;

function TPlainBar.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then Result:= 0 else Result:= E_NOINTERFACE;
end;

function TPlainBar._AddRef: Integer;
begin
  Result:= -1;
end;

function TPlainBar._Release: Integer;
begin
  Result:= -1;
end;

procedure TPlainBar.Ping;
begin
end;

constructor TComponent.Create(AOwner: TComponent);
begin
  inherited Create;
  if AOwner = nil then Exit;
end;

constructor TKeeper.Create(AFoo: TFoo);
begin
  inherited Create;
  FFoo:= AFoo;
end;

procedure TKeeper.Keep(AFoo: TFoo);
begin
  FFoo:= AFoo;
end;

procedure TKeeper.Show(AFoo: TFoo);
begin
  Writeln(AFoo.Name);
  AFoo.Touch;
end;

procedure TKeeper.ShowConst(const AFoo: TFoo);
begin
  if AFoo <> nil then Writeln(AFoo.Name);
end;

function TKeeper.Same(AFoo: TFoo): TFoo;
begin
  Result:= AFoo;
end;

procedure TKeeper.Eat(AFoo: TFoo);
begin
  Writeln(AFoo.Name);
  AFoo.Free;
end;

procedure TKeeper.Pass(AFoo: TFoo);
begin
  Keep(AFoo);
end;

procedure TKeeper.Later(AFoo: TFoo);
var
  Held: TFoo;
begin
  Held:= AFoo;
  FFoo:= Held;
end;

procedure TKeeper.Hook(AFoo: TFoo);
begin
  Writeln(AFoo.Name);
end;

procedure TKeeper.Second(ACount: Integer; AFoo: TFoo);
begin
  Writeln(ACount, AFoo.Name);
end;

procedure ReadOnly(AFoo: TFoo);
begin
  Writeln(AFoo.Name);
end;

procedure StoreGlobal(AFoo: TFoo);
begin
  GFoo:= AFoo;
end;

procedure ReleaseIt(AFoo: TFoo);
begin
  FreeAndNil(AFoo);
end;

procedure UseBar(const ABar: IBar);
begin
  ABar.Ping;
end;

procedure TakeBar(ABar: IBar);
begin
  ABar.Ping;
end;

procedure ShowObject(AObject: TObject);
begin
  Writeln(AObject.ClassName);
end;

end.
