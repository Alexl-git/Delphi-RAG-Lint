unit UwCases;

{ `with` statements unwith must CANDIDATE and rewrite. RunCases prints a line per case; the guard compares the program's
  output before and after the rewrite. }

interface

uses
  UwTypes;

type
  THost = class
  private
    FOwner: TOwner;
    FPt: TPoint3;
    FMid: TMid;
  public
    Value: Integer;
    constructor Create;
    destructor Destroy; override;
    procedure CaseFieldChain;
    procedure CaseEnclosingClassMember;
    procedure CaseRecordField;
  end;

procedure RunCases;

implementation

constructor THost.Create;
begin
  inherited Create;
  FOwner:= TOwner.Create;
  FMid:= TMid.Create;
  Value:= 500;
end;

destructor THost.Destroy;
begin
  FMid.Free;
  FOwner.Free;
  inherited Destroy;
end;

{ A field chain through a read-field property. Value is ALSO THost.Value: the with target wins. }
procedure THost.CaseFieldChain;
begin
  with FOwner.Stable do
  begin
    Value:= 11;
    Count:= Value + 1;
  end;
  Writeln('field-chain ', FOwner.Stable.Value, ' ', FOwner.Stable.Count, ' host ', Self.Value);
end;

{ A name the target does not declare stays the enclosing class's. }
procedure THost.CaseEnclosingClassMember;
var
  Mid: TMid;
begin
  Mid:= FMid;
  with Mid do
    Count:= Self.Value + 1;
  Writeln('enclosing ', Mid.Count, ' host ', Value);
end;

{ A record FIELD of the enclosing class. }
procedure THost.CaseRecordField;
begin
  with FPt do
  begin
    X:= 1;
    Y:= X + 1;
    Z:= Sum;
  end;
  Writeln('record-field ', FPt.X, ' ', FPt.Y, ' ', FPt.Z);
end;

{ THE SILENT REBIND. Count and Value are locals AND members (Count of the ancestor TBase, Value of TMid): `with` binds
  them to the members, so an unprefixed copy compiles and reads the locals. }
procedure CaseSilentRebind;
var
  M: TMid;
  Count, Value: Integer;
begin
  M:= TMid.Create;
  try
    Count:= 1000;
    Value:= 2000;
    M.Count:= 3;
    M.Value:= 4;
    with M do
      Writeln('silent-rebind ', Count + Value, ' tag ', Tag);
    Writeln('locals ', Count, ' ', Value);
  finally
    M.Free;
  end;
end;

{ Library member through the chain (TObject.ClassName), same-named overload of an ancestor, a method call. }
procedure CaseAncestorAndObject;
var
  M: TMid;
begin
  M:= TMid.Create;
  try
    with M do
    begin
      Writeln('object ', ClassName, ' ', Twice(21));
      Free;
    end;
  finally
    M:= nil;
  end;
  Writeln('ancestor ', M = nil);
end;

{ A record local, on one line, in the else branch: the shape keeps its statement position. }
procedure CaseRecordLocal(pFlag: Boolean);
var
  R: TPoint3;
begin
  R.X:= 0;
  R.Y:= 0;
  R.Z:= 0;
  if pFlag then
    R.X:= 5
  else
    with R do Y:= 6;
  Writeln('record-local ', R.X, ' ', R.Y);
end;

{ A class helper's member is in the closure. }
procedure CaseHelper;
var
  H: THelped;
  HelperOnly: Integer;
begin
  HelperOnly:= -1;
  H:= THelped.Create;
  try
    H.Label1:= 41;
    with H do
      Writeln('helper ', HelperOnly);
    Writeln('helper-local ', HelperOnly);
  finally
    H.Free;
  end;
end;

{ Nested: the inner one is a candidate (B's members win over A's), the outer refuses until the inner is gone. }
procedure CaseNested;
var
  A: TPoint3;
  B: TMid;
begin
  A.X:= 7;
  A.Y:= 8;
  A.Z:= 9;
  B:= TMid.Create;
  try
    B.Value:= 10;
    with A do
    begin
      with B do
        Count:= Value + X;
      Y:= B.Count;
    end;
    Writeln('nested ', A.Y);
  finally
    B.Free;
  end;
end;

{ The with is the then-branch: its begin..end stays (an else follows). The variant fields rebind silently too. }
procedure CaseIfBlock(pFlag: Boolean);
var
  S: TShape;
  AsInt, Lo: Integer;
begin
  AsInt:= -5;
  Lo:= -6;
  S.Tag:= 0;
  S.AsInt:= 0;
  if pFlag then
    with S do
    begin
      AsInt:= 70000;
      Tag:= Lo;
    end
  else
    S.Tag:= 1;
  Writeln('if-block ', S.AsInt, ' ', S.Tag, ' locals ', AsInt, ' ', Lo);
end;

{ `as` on a stable param, the shape of a generated Assign: the prefix needs parentheses, and Count is a local too. }
procedure CaseAs(pO: TObject);
var
  Count: Integer;
begin
  Count:= -1;
  with pO as TMid do
  begin
    Value:= 5;
    Writeln('as ', Value + 1, ' ', Count);
  end;
  Writeln('as-local ', Count);
end;

{ Param target, no block, followed by more statements. }
procedure CaseParam(pMid: TMid);
begin
  with pMid do
    Value:= 99;
  Writeln('param ', pMid.Value);
end;

procedure RunCases;
var
  Host: THost;
  Mid: TMid;
begin
  Host:= THost.Create;
  try
    Host.CaseFieldChain;
    Host.CaseEnclosingClassMember;
    Host.CaseRecordField;
  finally
    Host.Free;
  end;
  CaseSilentRebind;
  CaseAncestorAndObject;
  CaseRecordLocal(False);
  CaseHelper;
  CaseNested;
  CaseIfBlock(True);
  Mid:= TMid.Create;
  try
    CaseAs(Mid);
    CaseParam(Mid);
  finally
    Mid.Free;
  end;
end;

end.