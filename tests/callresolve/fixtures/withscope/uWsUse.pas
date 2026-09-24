unit uWsUse;

{ Fixture for run_with_scope_bind.ps1 (resolver 1.8.0-alpha, D14 + D16a). Every
  asserted line carries a marker; the guard reads line numbers from them.

  W-*    : a bare name inside a `with` body. Delphi binds it to the with
           target's member first (innermost target, last-listed entity first)
           and only then to the ordinary scope. Each binds to the MEMBER, or --
           when the target's type or surface cannot be known -- to NOTHING.
  OWN-*  : a bare property read inside its own class (D16a).
  SELF-* : an explicit `Self.X` read -- a member of the class whatever is local,
           property OR field (`Self.X` names the member as `Obj.X` does).
  CTRL-* : the same names OUTSIDE any with, which keep their ordinary binding. }

interface

uses
  uWsLib, Classes;

type
  TWsHost = class
  private
    FCountH: Integer;
    function GetTotalP: Integer;
  public
    procedure Execute;
    procedure Run(AObj: TWsObj; var ARec: TWsRec; AList: TStringList;
      ADer: TWsDerived; AOther: TWsOther);
    procedure Shadow;
    procedure SelfRefs;
    property TotalP: Integer read GetTotalP;
  end;

implementation

procedure TWsHost.Execute;
begin
  FCountH := 1;
end;

function TWsHost.GetTotalP: Integer;
begin
  Result := FCountH;
end;

procedure TWsHost.Run(AObj: TWsObj; var ARec: TWsRec; AList: TStringList;
  ADer: TWsDerived; AOther: TWsOther);
var
  N: Integer;
  M: TWsMode;
begin
  with AObj do
    Execute; // W-CALL-OBJ
  with ARec do
    Reset; // W-CALL-REC
  with ARec do
    N := Count; // W-READ-FIELD
  with ARec do
    N := Total; // W-PARENLESS
  with AObj do
    Inner.Ping; // W-RCV
  with AObj, ARec do
    N := Count; // W-ORDER
  with ARec, AObj do
    N := Count; // W-ORDER2
  with AObj do
    with AOther do
      Execute; // W-NESTED
  with ARec do
    M := Kind; // W-ENUM
  with AList do
    Execute; // W-UNKNOWN
  with ADer do
    Execute; // W-INCOMPLETE
  with ADer do
    Own; // W-INCOMPLETE-OWN
  with TWsObj.Create do
    try
      Execute; // W-CREATE
    finally
      Free; // W-FREE
    end;
  with AObj do
    N := Size; // W-PROP
  with AList do
    M := wmBeta; // W-ENUM-UNDECIDED
  Execute; // CTRL-OUTSIDE
  N := TotalP; // OWN-PROP
  N := N + FCountH; // OWN-FIELD
  M := Kind; // CTRL-ENUM
  if (N > 0) and (M = wmAlpha) then
    FCountH := N;
end;

procedure TWsHost.Shadow;
var
  TotalP: Integer;
begin
  TotalP := 2;
  FCountH := TotalP; // OWN-SHADOW
  FCountH := Self.FCountH + 1; // SELF-FIELD
end;

procedure TWsHost.SelfRefs;
var
  FCountH, N: Integer;
begin
  FCountH := 1;
  N := Self.FCountH; // SELF-FIELD-LOCAL
  N := N + Self.TotalP; // SELF-PROP
  FCountH := N + FCountH;
end;

end.