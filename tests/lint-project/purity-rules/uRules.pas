unit uRules;

{ Fixture for the two purity v2 lint rules (plan C6.1 Task 7; spec
  docs\superpowers\specs\2026-09-15-interprocedural-purity.md section 14):

    discarded-effect-free-result (14.1)
    query-name-with-effect       (14.2)

  Every routine below is either a TRIGGERING case or a deliberate NON-triggering
  control, and the controls are the point: a rule that fires on GetCount (a
  proven getter), on IsReady (a BINDING GAP, not an effect) or on a call whose
  result is USED ACROSS A LINE WRAP would be reporting noise. Both halves are
  asserted by run_purity_rules.ps1. }

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
    { 14.2 trigger, and the WITNESS JOIN control: symbol_facts.touches is the
      two-field wire string 'resources|transactions' with the separator always
      present, so a ONE-SIDED value is stored as 'file system|'. This one is
      one-sided and its witness must carry NO separator. }
    function GetPath: string;
    { 14.2 trigger, and the other half of the join control: BOTH sides
      populated ('file system|starts, commits'). }
    function GetLog: string;
  end;

function Twice(A: Integer): Integer;
procedure FillOut(out V: Integer);
procedure Driver;

var
  { Deliberately opaque so the transaction verbs stay UNBOUND: the Touches fact
    is what must reach the witness here, not a resolved callee. }
  GTx: TObject;

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

function TBox.GetPath: string;
begin
  Result:= TPath.GetTempPath;
end;

function TBox.GetLog: string;
begin
  if TFile.Exists('x') then
    GTx.StartTransaction;
  GTx.Commit;
  Result:= '';
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
  X:= X +
      Twice(6);                    { 14.1 control: WRAPPED -- this line alone trims to
                                     `Twice(6);` and passes every whole-statement test, but
                                     the previous line ends in '+', so the result IS used }
end;

end.
