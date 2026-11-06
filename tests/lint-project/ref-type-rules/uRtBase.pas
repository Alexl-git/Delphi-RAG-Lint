unit uRtBase;

interface

type
  TRtBase = class
  public
    Tag: Integer;
  end;

  TRtMid = class(TRtBase)
  end;

  TRtLeaf = class(TRtMid)
  public
    Link: TRtLeaf;
    Base: TRtBase;
    function Self2: TRtLeaf;
  end;

  TRtOther = class
  end;

  { Stand-ins for the library classes the rules climb to: the fixture runs without a library index. }
  TComponent = class
  public
    Tag: Integer;
    constructor Create(AOwner: TComponent);
    procedure Free;
  end;

  TRtComp = class(TComponent)
  end;

  TThread = class
  public
    Tag: Integer;
  end;

  TRtWorker = class(TThread)
  public
    constructor Create(ASuspended: Boolean);
  end;

  TRtPlain = class
  public
    Tag: Integer;
    constructor Create(AValue: Integer = 0);
    procedure Free;
  end;

  IRtThing = interface
  end;

  TRtCompThing = class(TRtComp, IRtThing)
  public
    Holder: IRtThing;
    procedure Hook;
    procedure HookOther(const AThing: IRtThing);
  end;

  TRtCountedThing = class(TComponent, IRtThing)
  public
    function _AddRef: Integer; stdcall;
  end;

  TRtRefThing = class(TRtPlain, IRtThing)
  public
    Holder: IRtThing;
    procedure Hook;
  end;

function MakeBase: TRtBase;
function MakeLeaf: TRtLeaf;

implementation

procedure TRtCompThing.Hook;
begin
  Holder:= Self;  // TRIGGER-HOLDER-SELF
end;

procedure TRtCompThing.HookOther(const AThing: IRtThing);
begin
  Holder:= AThing;  // CONTROL-HOLDER-INTERFACE
end;

function TRtCountedThing._AddRef: Integer;
begin
  Result:= 1;
end;

procedure TRtRefThing.Hook;
begin
  Holder:= Self;  // CONTROL-HOLDER-SELFCOUNTED
end;

constructor TComponent.Create(AOwner: TComponent);
begin
end;

procedure TComponent.Free;
begin
end;

constructor TRtWorker.Create(ASuspended: Boolean);
begin
end;

constructor TRtPlain.Create(AValue: Integer);
begin
end;

procedure TRtPlain.Free;
begin
end;

function TRtLeaf.Self2: TRtLeaf;
begin
  Result:= Link;
end;

function MakeBase: TRtBase;
begin
  Result:= nil;
end;

function MakeLeaf: TRtLeaf;
begin
  Result:= nil;
end;

end.
