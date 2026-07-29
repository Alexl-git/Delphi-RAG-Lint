unit inherited_bare;

// Fixture for the inherited-bare rule (register K32). Before the fix the query
// was `((inherited) @warn)` and fired on EVERY form below; the rule's message
// and rules/README.md both say BARE.

interface

type
  TBase = class
    constructor Create; virtual;
    procedure Paint; virtual;
    function Fetch(pIndex: Integer): Integer; virtual;
  end;

  TDerived = class(TBase)
    constructor Create; override;
    procedure Paint; override;
    function Fetch(pIndex: Integer): Integer; override;
    procedure Refresh;
  end;

implementation

constructor TBase.Create;
begin
end;

procedure TBase.Paint;
begin
end;

function TBase.Fetch(pIndex: Integer): Integer;
begin
  Result:= pIndex;
end;

constructor TDerived.Create;
begin
  inherited Create;                     // QUALIFIED, paren-less -- must NOT fire
end;

procedure TDerived.Paint;
begin
  inherited;                            // BARE -- must fire
end;

function TDerived.Fetch(pIndex: Integer): Integer;
begin
  Result:= inherited Fetch(pIndex);     // QUALIFIED with args -- must NOT fire
end;

procedure TDerived.Refresh;
begin
  Paint;
end;

end.
