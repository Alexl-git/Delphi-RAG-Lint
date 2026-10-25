unit dispatchtest;

// Fixture for run_doc_covered_by_dispatch.ps1 -- the TESTS.
//
// The unit name ends in 'test', so rule (a) of IsTestRoutine treats these
// methods as tests without needing a DUnitX attribute or TTestCase ancestry.
//
// Three call shapes, chosen because they differ in exactly the property the
// marking is about -- whether the call site recorded a RECEIVER:
//
//   Beta_direct         B.TransferFile('x')   receiver 'B'   -> anchored
//   Alpha_via_interface M.TransferFile('x')   receiver 'M'   -> anchored
//   Alpha_with          with A do TransferFile receiver ''   -> anchored by the resolver (X2)
//   Unknown_with        with X do TransferFile receiver ''   -> NOT anchored
//
// X2 (resolver 1.14.0-alpha): a `with` over a TYPED target now binds -- A is a
// TAlpha, so Alpha_with is TAlpha.TransferFile and nothing else. Unknown_with
// keeps the unprovable shape: X is of a type the index does not hold, so the
// resolver declines and only the name bucket sees the call.
//
// The `with` form is the one that matters. It is ordinary Delphi, it is the
// only legal way to call a method with no receiver text at the call site, and
// it reproduces the report deterministically: the walk cannot tell which
// TransferFile it reached, so it attributes the test to ALL of them --
// including TBeta, which Alpha_with never touches.

interface

uses
  dispatch;

type
  TDispatchTests = class
  public
    procedure Alpha_via_interface;
    procedure Beta_direct;
    procedure Helper_bare;
    procedure Alpha_with;
    procedure Unknown_with;
  end;

implementation

procedure Chk(const AOk: Boolean; const AMsg: string);
begin
end;

procedure TDispatchTests.Alpha_via_interface;
var
  M: ICopy;
begin
  M:= TAlpha.Create;
  Chk(M.TransferFile('x'), 'alpha');
end;

procedure TDispatchTests.Beta_direct;
var
  B: TBeta;
begin
  B:= TBeta.Create;
  B.TransferFile('x');
  B.Free;
end;

procedure TDispatchTests.Helper_bare;
begin
  Chk(PlainHelper('x'), 'plain');
end;

procedure TDispatchTests.Alpha_with;
var
  A: TAlpha;
begin
  A:= TAlpha.Create;
  with A do
    Chk(TransferFile('x'), 'with');
end;

procedure TDispatchTests.Unknown_with;
var
  X: TForeignCopier; // declared in a unit this index does not hold
begin
  with X do
    Chk(TransferFile('x'), 'unknown');
end;

end.
