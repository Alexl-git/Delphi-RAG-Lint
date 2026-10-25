unit uEnumPersist;

{ Fixture for tests\lint-project\enum-ordinal-persisted\run_enum_ordinal_persisted.ps1.
  One enum type per case: the rule reports per TYPE, at its declaration. }

interface

uses
  Classes, DB;

type
  TKindOut = (koA, koB, koC); // TRIGGER-OUT
  TKindIn = (kiA, kiB); // TRIGGER-IN
  TKindComment = (kcA = 0, kcB { kcB = 1 }, // TRIGGER-COMMENT
    kcC // kcC = 2
  );
  TKindPinned = (kpA = 0, kpB = 1, kpC = 2); // CONTROL-PINNED
  TKindIndex = (kxA, kxB); // CONTROL-NOSINK
  TKindSplit = (ksA, ksB); // CONTROL-SPLIT

procedure SaveOut(pS: TStream; pK: TKindOut);
function LoadIn(pQ: TDataSet): TKindIn;
procedure SaveComment(pS: TStream);
procedure SavePinned(pS: TStream);
function IndexOnly(pK: TKindIndex): Integer;
function SplitCast(pI: Integer): TKindSplit;
procedure SplitSink(pS: TStream; pI: Integer);

implementation

procedure SaveOut(pS: TStream; pK: TKindOut);
var
  B: Byte;
begin
  B := Ord(pK);
  pS.WriteBuffer(B, 1);
end;

function LoadIn(pQ: TDataSet): TKindIn;
begin
  Result := TKindIn(pQ.FieldByName('KIND').AsInteger);
end;

procedure SaveComment(pS: TStream);
var
  B: Byte;
begin
  B := Byte(kcC);
  pS.WriteBuffer(B, 1);
end;

procedure SavePinned(pS: TStream);
var
  B: Byte;
begin
  B := Ord(kpB);
  pS.WriteBuffer(B, 1);
end;

function IndexOnly(pK: TKindIndex): Integer;
begin
  Result := Ord(pK) + 1;
end;

function SplitCast(pI: Integer): TKindSplit;
begin
  Result := TKindSplit(pI);
end;

procedure SplitSink(pS: TStream; pI: Integer);
begin
  pS.WriteBuffer(pI, 4);
end;

end.
