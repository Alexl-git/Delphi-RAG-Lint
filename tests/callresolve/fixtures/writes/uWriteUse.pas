unit uWriteUse;

{ Fixture for run_write_refs_bind.ps1 (defect D13, resolver 1.8.0-alpha).
  Every `X:= ...` below with a bare identifier on the left is a `write` ref.
  W-* markers must bind refs.symbol_id to the named declaration; NEG-* markers
  must stay NULL. The script reads every line number from these markers. }

interface

uses
  uWriteLib, uWriteLib2;

type
  TBase = class
  protected
    FBase: Integer;
  end;

  TThing = class(TBase)
  private
    FCount: Integer;
    FName: string;
    procedure SetName(const AValue: string);
  public
    class var Instances: Integer;
    procedure Run(AParam: Integer);
    function Compute: Integer;
    property Name: string read FName write SetName;
  end;

var
  GOwn: Integer;

procedure FreeWriter;

implementation

var
  GImpl: Integer;

procedure TThing.SetName(const AValue: string);
begin
  FName:= AValue;                                   // W-FIELD-SETTER
end;

procedure TThing.Run(AParam: Integer);
var
  L: Integer;
  GOwn: Integer;

  procedure Inner;
  begin
    L:= 5;                                          // W-OUTER-LOCAL
  end;

begin
  L:= 1;                                            // W-LOCAL
  AParam:= 2;                                       // W-PARAM
  FCount:= 3;                                       // W-OWN-FIELD
  FBase:= 4;                                        // W-ANCESTOR-FIELD
  Name:= 'x';                                       // W-PROPERTY
  Instances:= 1;                                    // W-CLASS-VAR
  GOwn:= 6;                                         // W-SHADOW-LOCAL
  GShared:= 7;                                      // W-USED-UNIT
  GClash:= 8;                                       // NEG-AMBIGUOUS
  GUnknown:= 9;                                     // NEG-NOT-FOUND
  Inner;
  with Self do
    FCount:= 10;                                    // W-WITH-MEMBER
  with Self do
    L:= 13;                                         // W-WITH-FALLTHROUGH
  with TNotIndexed(nil) do
    GOwn:= 11;                                      // NEG-WITH-UNDECIDED
  L:= 12;                                           // W-AFTER-WITH
end;

function TThing.Compute: Integer;
begin
  Result:= 1;                                       // NEG-RESULT
  Compute:= 2;                                      // NEG-OWN-NAME
end;

procedure FreeWriter;
begin
  GOwn:= 1;                                         // W-OWN-UNIT-IFACE
  GImpl:= 2;                                        // W-OWN-UNIT-IMPL
end;

end.
