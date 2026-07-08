unit objleakowned;

interface

type
  // Minimal self-contained VCL-like stub hierarchy so IsDescendantOf(TLabel,
  // TComponent) resolves without depending on the real VCL being indexed.
  TComponent = class
    constructor Create(AOwner: TComponent);
  end;

  TLabel = class(TComponent)
    Parent: TComponent;
  end;

  // NOT a TComponent descendant: its Create has no AOwner, so it is never
  // owner-managed -- an unfreed instance is a genuine leak.
  TStringList = class
  end;

implementation

constructor TComponent.Create(AOwner: TComponent);
begin
end;

// Owner-parented local: created with a non-nil owner (Self), never stored in
// a field/array, never explicitly freed. This must NOT be flagged: TLabel is
// a TComponent descendant and Self (non-nil) owns it, so Self's destructor
// frees it. An explicit lbl.Free here would risk a double-free.
procedure MakeOwnedLabel(Self: TComponent; X: TComponent);
var
  lbl: TLabel;
begin
  lbl := TLabel.Create(Self);
  lbl.Parent := X;
end;

// Genuine leak control #1: TStringList is not a TComponent descendant, so the
// owner-transfer rule must not suppress it. Never freed -> must still flag.
procedure LeakStringList;
var
  sl: TStringList;
begin
  sl := TStringList.Create;
end;

// Genuine leak control #2: explicit nil owner on a TComponent descendant is
// NOT an ownership transfer (there is no owner) -- must still flag.
procedure LeakNilOwnedLabel;
var
  c: TLabel;
begin
  c := TLabel.Create(nil);
end;

end.
