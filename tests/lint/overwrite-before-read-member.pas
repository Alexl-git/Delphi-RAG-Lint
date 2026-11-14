unit overwrite_before_read_member;

{ v151 WID-FLOW: overwrite-before-read widened from locals to fields,
  field-backed properties and pointer/record member paths, in straight-line
  code (two ADJACENT stores to the same path, the second one a plain value). }

interface

type
  TRec = record
    X: Integer;
  end;
  PRec = ^TRec;

  TFoo = class
  private
    FA: Integer;
    FB: string;
    FC: Integer;
    procedure SetC(AValue: Integer);
  public
    property B: string read FB write FB;
    property C: Integer read FC write SetC;
    procedure FieldTwice;
    procedure PropTwice;
    procedure PtrTwice(P: PRec);
    procedure SelfTwice;
    procedure ReadBetween;
    procedure SetterProp;
    procedure SecondReadsField;
    procedure SecondCalls;
    procedure NotAdjacent;
    procedure LocalTwice;
  end;

function Compute: Integer;

implementation

function Compute: Integer;
begin
  Result := 3;
end;

procedure TFoo.SetC(AValue: Integer);
begin
  FC := AValue;
end;

procedure TFoo.FieldTwice;
begin
  FA := 1;
  FA := 2;
end;

procedure TFoo.PropTwice;
begin
  B := 'a';
  B := 'b';
end;

procedure TFoo.PtrTwice(P: PRec);
begin
  P^.X := 1;
  P^.X := 2;
end;

procedure TFoo.SelfTwice;
var
  N: Integer;
begin
  N := 7;
  Self.FA := 0;
  Self.FA := N;
end;

procedure TFoo.ReadBetween;
begin
  FA := 1;
  Writeln(FA);
  FA := 2;
end;

procedure TFoo.SetterProp;
begin
  C := 1;
  C := 2;
end;

procedure TFoo.SecondReadsField;
begin
  FA := 1;
  FA := FA + 1;
end;

procedure TFoo.SecondCalls;
begin
  FA := 1;
  FA := Compute;
end;

procedure TFoo.NotAdjacent;
begin
  FA := 1;
  if FB = '' then
    FA := 2;
end;

procedure TFoo.LocalTwice;
var
  L: Integer;
begin
  L := 1;
  L := 2;
  Writeln(L);
end;

end.
