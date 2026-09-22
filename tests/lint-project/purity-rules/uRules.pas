unit uRules;

{ Fixture for the two purity v2 lint rules (plan C6.1 Task 7; spec
  docs\superpowers\specs\2026-09-15-interprocedural-purity.md section 14):

    discarded-effect-free-result (14.1)
    query-name-with-effect       (14.2)

  Every routine below is either a TRIGGERING case or a deliberate NON-triggering
  control, and the controls are the point: a rule that fires on GetCount (a
  proven getter) or on IsReady (a BINDING GAP, not an effect) would be reporting
  the absence of proof as a defect. run_purity_rules.ps1 asserts both halves. }

interface

type
  TBox = class
  private
    FCount: Integer;
  public
    { 14.2 control: query-named and PROVEN effect-free -- no finding. }
    function GetCount: Integer;
    { 14.2 trigger: query-named, writes its own field -- summary 's'. }
    function GetAndBump: Integer;
    { 14.2 control: query-named, but the only blocker is an UNBOUND callee --
      summary '?', which is a gap in the proof and not a proven effect. }
    function IsReady: Boolean;
  end;

function Twice(A: Integer): Integer;
procedure FillOut(out V: Integer);
procedure Driver;

implementation

function TBox.GetCount: Integer;
begin
  Result:= FCount;
end;

function TBox.GetAndBump: Integer;
begin
  FCount:= FCount + 1;
  Result:= FCount;
end;

function TBox.IsReady: Boolean;
begin
  Result:= Assigned(Self) and (Trim('x') <> '');
end;

function Twice(A: Integer): Integer;
begin
  Result:= A * 2;
end;

procedure FillOut(out V: Integer);
begin
  V:= 1;
end;

procedure Driver;
var
  X: Integer;
begin
  Twice(3);                        { 14.1 trigger: statement position, result discarded }
  X:= Twice(4);                    { 14.1 control: the result is used }
  if Twice(5) > 0 then FillOut(X); { 14.1 control: inside an expression, not a whole statement }
  FillOut(X);                      { 14.1 control: p0, not effect-free -- the out-parameter idiom }
end;

end.
