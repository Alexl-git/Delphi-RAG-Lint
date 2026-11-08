unit EiWidget;

// Fixture of extract-interface. The trailing comment on a member says what must happen to it when the class is extracted
// from its uses: IN, LEFT <kind>, or OUT (unused). A class's marker sits on its declaration line.

interface

type
  TEiKindFwd = (ekOne, ekTwo);

  /// <summary>The main case.</summary>
  TEiWidget = class(TInterfacedObject) // EXTRACT
  public type
    TKind = (kA, kB);
  strict private
    FCount: Integer;
    FDirect: Integer;
    function GetCount: Integer;
    procedure SetCount(pValue: Integer);
    function Hidden: Integer; // OUT
  protected
    procedure ForDescendants; // OUT
  public
    Tag: Integer; // LEFT field
    function Value: Integer; // IN
    function Sum(pA, // IN
      pB: Integer): Integer;
    procedure Over(pA: Integer); overload; // IN
    procedure Over(const pA: string); overload; // IN
    function Virt: string; virtual; // IN
    function Clone: TEiWidget; // IN
    function Conv(pKind: TEiKindFwd): Integer; // IN
    function KindOf(pKind: TKind): Integer; // LEFT class-scope-name
    function Gen<T>(const pV: T): T; // LEFT generic-method
    class function Make: TEiWidget; // LEFT class-member
    constructor Create; // LEFT class-member
    function Unused: Integer; // OUT
    function SelfOnly: Integer; // OUT
    property Count: Integer read GetCount write SetCount; // IN
    property Direct: Integer read FDirect write FDirect; // LEFT field-backed-property
  end;

  TEiDesc = class(TEiWidget)
  public
    function Virt: string; override;
    procedure Go;
  end;

  TEiPlain = class // PLAIN
  public
    function Ping: Integer;
  end;

  TEiDeep = class(TEiPlain) // DEEP
  public
    function Pong: Integer;
  end;

  TEiGeneric<T> = class(TInterfacedObject) // REFUSE generic-class
  public
    function Item: Integer;
  end;

  TEiOuter = class(TInterfacedObject)
  public type
    TInner = class(TInterfacedObject) // REFUSE nested-class
    public
      function Item: Integer;
    end;
  end;

  TEiIfdef = class(TInterfacedObject) // REFUSE ifdef-in-class
  public
    {$IFDEF NEVER_DEFINED}
    function Absent: Integer;
    {$ENDIF}
    function Item: Integer;
  end;

  IEiTaken = interface
    ['{7A2B1C10-1111-4222-8333-444455556666}']
  end;

  TEiTaken = class(TInterfacedObject) // REFUSE name-taken
  public
    function Item: Integer;
  end;

  TEiNothing = class(TInterfacedObject) // REFUSE no-used-members
  public
    function Item: Integer;
  end;

  TEiScopeBase = class(TInterfacedObject)
  strict protected type
    TProt = Integer;
  end;

  // The plan cannot see that TProt is strict protected in the ancestor: legal here, not in front of the class. Only a build can tell.
  TEiBroken = class(TEiScopeBase) // BROKEN
  public
    function Item(pV: TEiScopeBase.TProt): Integer;
  end;

implementation

function TEiWidget.GetCount: Integer;
begin
  Result:= FCount;
end;

procedure TEiWidget.SetCount(pValue: Integer);
begin
  FCount:= pValue;
end;

function TEiWidget.Hidden: Integer;
begin
  Result:= 1;
end;

procedure TEiWidget.ForDescendants;
begin
  FDirect:= 2;
end;

function TEiWidget.Value: Integer;
begin
  Result:= Hidden + SelfOnly;
end;

function TEiWidget.Sum(pA, pB: Integer): Integer;
begin
  Result:= pA + pB;
end;

procedure TEiWidget.Over(pA: Integer);
begin
  FCount:= pA;
end;

procedure TEiWidget.Over(const pA: string);
begin
  FCount:= Length(pA);
end;

function TEiWidget.Virt: string;
begin
  Result:= 'widget';
end;

function TEiWidget.Clone: TEiWidget;
begin
  Result:= TEiWidget.Create;
end;

function TEiWidget.Conv(pKind: TEiKindFwd): Integer;
begin
  Result:= Ord(pKind);
end;

function TEiWidget.KindOf(pKind: TKind): Integer;
begin
  Result:= Ord(pKind);
end;

function TEiWidget.Gen<T>(const pV: T): T;
begin
  Result:= pV;
end;

class function TEiWidget.Make: TEiWidget;
begin
  Result:= TEiWidget.Create;
end;

constructor TEiWidget.Create;
begin
  inherited Create;
  FCount:= 7;
end;

function TEiWidget.Unused: Integer;
begin
  Result:= 0;
end;

function TEiWidget.SelfOnly: Integer;
begin
  Result:= 41;
end;

function TEiDesc.Virt: string;
begin
  Result:= 'desc';
end;

procedure TEiDesc.Go;
begin
  ForDescendants;
end;

function TEiPlain.Ping: Integer;
begin
  Result:= 3;
end;

function TEiDeep.Pong: Integer;
begin
  Result:= 4;
end;

function TEiGeneric<T>.Item: Integer;
begin
  Result:= 0;
end;

function TEiOuter.TInner.Item: Integer;
begin
  Result:= 0;
end;

function TEiIfdef.Item: Integer;
begin
  Result:= 0;
end;

function TEiTaken.Item: Integer;
begin
  Result:= 0;
end;

function TEiNothing.Item: Integer;
begin
  Result:= 0;
end;

function TEiBroken.Item(pV: TEiScopeBase.TProt): Integer;
begin
  Result:= pV;
end;

end.