unit uAfHost;

{ Fixture of run_ast_f1_operands.ps1 (lane 145 la, rows 1 and 18-20 of the F1/F2 survey):
  operands that are dotted chains or call results, which the declared-type map of
  TAstChecker.CheckTypeAware cannot type. A TRIGGER-<TAG>-n line must fire, a CONTROL-<TAG>-n
  line must stay silent, a TODAY-<TAG>-n line fires with and without the F1 fact. }

interface

type
  IAfSvc = interface
  end;

  TAfKind = (akOne, akTwo, akThree);

  TAfRec = record
    Total: Double;
    Count: Integer;
    Name : string;
  end;

  TAfNode = class
  public
    Data  : Pointer;
    Handle: NativeInt;
    Size  : Integer;
  end;

  TAfHost = class
  public
    FItems: string;
    FName : string;
    FArr  : TArray<Integer>;
    Svc   : IAfSvc;
    State : TAfKind;
    Rec   : TAfRec;
    Node  : TAfNode;
    function GetKind: TAfKind;
    function GetTotal: Double;
    procedure Run(Other: TAfHost);
  end;

implementation

function TAfHost.GetKind: TAfKind;
begin
  Result:= State;
end;

function TAfHost.GetTotal: Double;
begin
  Result:= Rec.Total;
end;

procedure TAfHost.Run(Other: TAfHost);
var
  D: Double;
  N: Integer;
begin
  if Rec.Total = Other.Rec.Total then Exit; // TRIGGER-FLOAT-1
  if GetTotal() = Rec.Total then Exit; // TRIGGER-FLOAT-2
  if Rec.Count = Other.Rec.Count then Exit; // CONTROL-FLOAT-1
  if D = 1.5 then Exit; // TODAY-FLOAT-1
  if Length(Self.FItems) = 0 then Exit; // TRIGGER-LENZ-1
  if Length(Self.FArr) = 0 then Exit; // CONTROL-LENZ-1
  FreeAndNil(Other.Svc); // TRIGGER-FANI-1
  FreeAndNil(Other.Node); // CONTROL-FANI-1
  N:= Integer(Node.Data); // TRIGGER-W64-1
  N:= Integer(Node.Size); // CONTROL-W64-1
  N:= Integer(Node.Handle); // TRIGGER-NINT-1
  N:= Integer(Other.Node.Size); // CONTROL-NINT-1
  if AnsiString(Rec.Name) = '' then Exit; // TRIGGER-LOSSY-1
  if AnsiString(Other.FArr) = '' then Exit; // CONTROL-LOSSY-1
  if Rec.Name = Other.FName then Exit; // TRIGGER-STREQ-1
  if Node.Size = Other.Node.Size then Exit; // CONTROL-STREQ-1
  case Self.State of akOne: Exit; end; // TRIGGER-ENUM-1
  case GetKind() of akOne: Exit; end; // TRIGGER-ENUM-2
  case Self.State of akOne: Exit; akTwo: Exit; akThree: Exit; end; // CONTROL-ENUM-1
end;

end.
