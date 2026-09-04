unit objleaksplitapp;

// The PROJECT half of the split-chain fixture (FP2b).
//
// TMyForm's ancestor TForm lives in objleaksplitlib, which is indexed into a
// SEPARATE database. So in the project index the `TMyForm -> TForm` ancestor
// edge is a name-only unresolved leaf: the project walk stops at TForm and
// never reaches TComponent, and TMyForm does not exist in the library index at
// all. Both halves of ConstructorTransfersOwnership's ancestry test therefore
// answer False, ownership is not detected, and an owner-parented form is
// reported as a leak.

interface

uses
  objleaksplitlib;

type
  TMyForm = class(TForm)
  end;

  // NOT a TComponent descendant by any route -- the control that proves the
  // rule is still alive.
  TPlainThing = class
  end;

implementation

// The false positive under test: a project-local class whose ancestry crosses
// into the library index, constructed WITH a non-nil owner. Must NOT be
// flagged -- the owner frees it.
procedure MakeOwnedSplitForm(AOwner: TComponent);
var
  f: TMyForm;
begin
  f := TMyForm.Create(AOwner);
end;

// Control 1: same split chain, explicit nil owner -- no owner, genuine leak.
procedure LeakNilOwnedSplitForm;
var
  f: TMyForm;
begin
  f := TMyForm.Create(nil);
end;

// Control 2: not a component at all -- genuine leak, unaffected by the bridge.
procedure LeakPlainThing;
var
  p: TPlainThing;
begin
  p := TPlainThing.Create;
end;

end.
