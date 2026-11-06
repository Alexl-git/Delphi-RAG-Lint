unit uAfLoop;

{ Fixture of run_ast_f1_operands.ps1, row 2 (concat-in-loop): CONTROL-CONCAT lines are numeric
  accumulations the declared-type maps cannot type (a field
  of an ancestor in another unit); with the F1 fact the rule drops them, without it it still
  reports them. TRIGGER-CONCAT lines are real string accumulations and fire in every run. }

interface

uses
  uAfHost;

type
  TAfLoop = class(TAfHost)
  public
    procedure Sum(Count: Integer);
  end;

implementation

procedure TAfLoop.Sum(Count: Integer);
var
  S: string;
begin
  var Txt := '';
  for var I := 0 to Count do
  begin
    FCost := FCost + I; // CONTROL-CONCAT-1
    Txt := Txt + 'x'; // TRIGGER-CONCAT-1
    S := S + 'y'; // TRIGGER-CONCAT-2
  end;
end;

end.
