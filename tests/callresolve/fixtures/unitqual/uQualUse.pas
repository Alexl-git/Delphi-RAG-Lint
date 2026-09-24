unit uQualUse;

{ Fixture for run_unit_qualified_call_bind.ps1 (ENG-16, resolver 1.8.0-alpha).
  POS-* markers: the unit-qualified call must own ONE certain call_edges row to
  the named routine. NEG-* markers must own none. The script reads every line
  number from these markers. }

interface

procedure Driver;
procedure DriverShadowTyped;
procedure DriverShadowUntyped;

implementation

uses
  Qual.Lib, uQualHelp;

type
  TLocal = class
  public
    procedure DoIt(A: Integer);
  end;

procedure TLocal.DoIt(A: Integer);
begin
end;

procedure Helper(A: Integer);
begin
end;

procedure Driver;
var
  N: Integer;
begin
  Qual.Lib.DoIt(1);                                 // POS-CALL
  N:= Qual.Lib.Twice(2);                            // POS-FUNC
  if Qual.Lib.Ready then N:= 0;                     // POS-PARENLESS
  Qual.Lib.Over(1, 2);                              // POS-OVERLOAD
  uQualUse.Helper(N);                               // POS-OWN-UNIT
  uQualHelp.DoIt(N);                                // POS-SIMPLE-UNIT
  Qual.Lib.Missing(3);                              // NEG-MISSING
end;

procedure DriverShadowTyped;
var
  uQualHelp: TLocal;
begin
  uQualHelp:= TLocal.Create;
  uQualHelp.DoIt(1);                                // SHADOW-TYPED
  uQualHelp.Free;
end;

procedure DriverShadowUntyped;
var
  uQualHelp: TNotIndexed;
begin
  uQualHelp.DoIt(1);                                // NEG-SHADOW-UNTYPED
end;

end.
