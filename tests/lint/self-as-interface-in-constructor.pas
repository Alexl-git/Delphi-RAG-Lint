unit SelfAsInterfaceInConstructorFixture;

{ self-as-interface-in-constructor: Self handed out as an interface while the
  reference count can still free the object. HIT lines must fire, OK lines must not. }

interface

type
  IListener = interface
    ['{0B7D1B52-3C61-4F0E-8E4A-2D0B9C6A7E01}']
    procedure Notify;
  end;

  TSource = class
  public
    procedure Subscribe(const AListener: IListener);
    procedure SubscribeObj(AObj: TObject);
  end;

  { case 2: TInterfacedObject descendant, after inherited AfterConstruction }
  TWatcher = class(TInterfacedObject, IListener)
  private
    FSource: TSource;
    FSelf  : IListener;
  public
    constructor Create(ASource: TSource);
    procedure AfterConstruction; override;
    procedure Notify;
  end;

  { the fixed order: before inherited }
  TGoodWatcher = class(TInterfacedObject, IListener)
  private
    FSource: TSource;
  public
    procedure AfterConstruction; override;
    procedure Notify;
  end;

  { case 1: own reference counting, _Release frees, no NewInstance }
  TCounted = class(TObject, IListener)
  private
    FCount : Integer;
    FSource: TSource;
  protected
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
  public
    constructor Create(ASource: TSource);
    procedure Notify;
  end;

  { a plain class: no reference counting at all }
  TPlain = class(TObject, IListener)
  private
    FSource: TSource;
  protected
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
  public
    constructor Create(ASource: TSource);
    procedure Notify;
  end;

implementation

procedure TSource.Subscribe(const AListener: IListener);
begin
end;

procedure TSource.SubscribeObj(AObj: TObject);
begin
end;

constructor TWatcher.Create(ASource: TSource);
begin
  inherited Create;
  FSource:= ASource;
  FSource.Subscribe(Self); {OK}
end;

procedure TWatcher.AfterConstruction;
var
  L: IListener;
begin
  FSource.Subscribe(Self); {OK}
  inherited;
  FSource.Subscribe(Self); {HIT}
  L:= Self as IListener; {HIT}
  FSource.SubscribeObj(Self); {OK}
  FSelf:= Self; {HIT}
end;

procedure TWatcher.Notify;
begin
end;

procedure TGoodWatcher.AfterConstruction;
begin
  FSource.Subscribe(Self); {OK}
  inherited;
end;

procedure TGoodWatcher.Notify;
begin
end;

function TCounted.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then Result:= 0 else Result:= E_NOINTERFACE;
end;

function TCounted._AddRef: Integer;
begin
  Inc(FCount);
  Result:= FCount;
end;

function TCounted._Release: Integer;
begin
  Dec(FCount);
  Result:= FCount;
  if Result = 0 then Destroy;
end;

constructor TCounted.Create(ASource: TSource);
begin
  inherited Create;
  FSource:= ASource;
  FSource.Subscribe(Self); {HIT}
end;

procedure TCounted.Notify;
begin
end;

function TPlain.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then Result:= 0 else Result:= E_NOINTERFACE;
end;

function TPlain._AddRef: Integer;
begin
  Result:= -1;
end;

function TPlain._Release: Integer;
begin
  Result:= -1;
end;

constructor TPlain.Create(ASource: TSource);
begin
  inherited Create;
  FSource:= ASource;
  FSource.Subscribe(Self); {OK}
end;

procedure TPlain.Notify;
begin
end;

end.
