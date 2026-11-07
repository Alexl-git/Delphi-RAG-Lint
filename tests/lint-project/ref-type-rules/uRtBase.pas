unit uRtBase;

interface

type
  TRtBase = class
  public
    Tag: Integer;
  end;

  TRtMid = class(TRtBase)
  end;

  TdlgLocal = class(TRtBase)
  end;

  TRtLeaf = class(TRtMid)
  public
    Link: TRtLeaf;
    Base: TRtBase;
    function Self2: TRtLeaf;
  end;

  TRtOther = class
  end;

  IRtFace = interface
  end;

  IRtOther = interface
  end;

  TRtSealed = class sealed(TRtBase)
  end;

  TRtFaced = class sealed(TRtBase, IRtFace)
  end;

  TRtOpen = class(TRtBase)
  end;

  { An ancestor no index holds: the closure is incomplete, so nothing is proved about it. }
  TRtUnfollowed = class(TNotIndexedAnywhere)
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

var
  GShadow: TRtBase;

function MakeBase: TRtBase;
function MakeLeaf: TRtLeaf;

type
  TRtKey = Int64;
  TRtKey2 = TRtKey;

procedure TakeInt(AValue: Integer);
procedure TakeTwo(const AFirst: Int64; ASecond: Byte = 0);
procedure TakeVar(var AValue: Integer);
procedure TakeOver(AValue: Integer); overload;
procedure TakeOver(AValue: Int64); overload;
procedure TakeSingle(AValue: Single);
function WideResult: Int64;

implementation

procedure TakeInt(AValue: Integer);
begin
end;

procedure TakeTwo(const AFirst: Int64; ASecond: Byte);
begin
end;

procedure TakeVar(var AValue: Integer);
begin
end;

procedure TakeOver(AValue: Integer);
begin
end;

procedure TakeOver(AValue: Int64);
begin
end;

procedure TakeSingle(AValue: Single);
begin
end;

function WideResult: Int64;
begin
  Result:= 0;
end;

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
