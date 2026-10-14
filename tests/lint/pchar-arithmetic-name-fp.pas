unit PCharArithNameFp;

{ pchar-arithmetic must decide on the DECLARED type, never on a P-prefixed
  name (INBOX-bare-call-in-if-else-and-pchar-name-fp section 2). Every
  operand below is P-named and none is a character pointer. An operand whose
  type cannot be read (an untyped inline var) stays silent -- no guess. }

interface

type
  TRow = record
    Id: Integer;
  end;

implementation

function NewRow(AId: Integer): TRow;
begin
  Result.Id := AId;
end;

procedure ArrayConcat;
var
  PCount: Integer;
begin
  var PRows: TArray<TRow> := [];
  PRows := PRows + [NewRow(1)];
  PCount := PCount + 1;
  var PName: string := 'a';
  PName := PName + 'b';
end;

procedure ParamAndUntyped(const PLen: Integer);
begin
  var PGuess := PLen;
  PGuess := PGuess + 1;
  if PLen - 1 > 0 then Exit;
end;

procedure Shadowed;
var
  PBuf: Integer;
  procedure Inner;
  var
    PBuf: Double;
  begin
    PBuf := PBuf + 1;
  end;
begin
  PBuf := PBuf + 1;
  Inner;
end;

end.