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

function MakeBase: TRtBase;
function MakeLeaf: TRtLeaf;

implementation

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
