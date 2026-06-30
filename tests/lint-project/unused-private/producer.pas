unit producer;

interface

type
  TProducer = class
  private
    FUnusedField: Integer;
    procedure UnusedPrivateMethod;
  public
    procedure UsedPublicMethod;
  end;

  { TCounter: a class with a property whose read/write accessors are private
    methods referenced ONLY by the property's read/write clause.  The rule
    unused-private-member must NOT flag GetCount or SetCount (or FCount)
    because they serve as property accessors, even though the symbol index
    records zero FindReferencesTo / FindCallersByName for them.  This is the
    regression fixture for the property-accessor guard introduced in v0.68. }
  TCounter = class
  private
    FCount: Integer;
    function GetCount: Integer;
    procedure SetCount(AValue: Integer);
  public
    property Count: Integer read GetCount write SetCount;
  end;

implementation

procedure TProducer.UnusedPrivateMethod;
begin
end;

procedure TProducer.UsedPublicMethod;
begin
end;

function TCounter.GetCount: Integer;
begin
  Result := FCount;
end;

procedure TCounter.SetCount(AValue: Integer);
begin
  FCount := AValue;
end;

end.
