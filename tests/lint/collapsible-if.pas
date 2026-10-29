unit CollapsibleIf;

interface

implementation

procedure Bad(A, B: Boolean; var N: Integer);
begin
  if A then
    if B then
      Inc(N);                               // HIT_A: nested if, no else on either
  if A then
  begin
    if B then
      Inc(N);                               // HIT_B: same, single statement in begin/end
  end;
end;

procedure Good(A, B: Boolean; var N: Integer);
begin
  if A then
    if B then
      Inc(N)
    else
      Dec(N);                               // NOT_A: inner has else
  if A then
  begin
    if B then
      Inc(N);
    Dec(N);                                 // NOT_B: block has a second statement
  end
  else
    N := 0;                                 // NOT_C: outer has else
  if A and B then
    Inc(N);                                 // NOT_D: already collapsed
  if A then
  begin
    if B then
      Inc(N);
    Inc(N);                                 // NOT_E: block holds two statements (the anchor-free text check must see the second)
  end;
  if A then
  begin
    if B then
      Writeln('it can never end');
    Exit;                                   // NOT_F: an 'end' inside the first statement must not pass the single-statement check
  end;
end;

end.
