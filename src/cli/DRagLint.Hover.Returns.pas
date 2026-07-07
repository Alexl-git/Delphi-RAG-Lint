unit DRagLint.Hover.Returns;

/// <summary>Mine a routine body for the distinct expressions it returns, so the
/// hover "Returns" section can show real Result:= / Exit(...) values without an
/// LLM. Pure text: the caller supplies the routine's own body lines.</summary>

interface

/// <summary>Distinct right-hand sides of `Result := <rhs>` and value-form
/// `Exit(<rhs>)` in ABodyLines, in first-seen source order.</summary>
/// <param name="ABodyLines">The routine's implementation body lines
///   (impl_start_line..impl_end_line), one string per source line.</param>
/// <returns>Distinct RHS strings, trimmed, dedup'd. Empty when none found.</returns>
/// <remarks>Best-effort, single-line RHS captured up to the terminating ';'.
///   Skips `//` line comments. Does not descend into nested routines (caller
///   passes only this routine's span). Not authoritative -- a display aid.</remarks>
function MineReturnExpressions(const ABodyLines: TArray<string>): TArray<string>;

implementation

uses
  System.SysUtils, System.StrUtils, System.Generics.Collections;

function StripLineComment(const S: string): string;
var
  P: Integer;
begin
  P:= Pos('//', S);
  if P > 0 then Result:= Copy(S, 1, P - 1) else Result:= S;
end;

// Extract '<rhs>' from 'Result := <rhs> ;', including a guarded form like
// 'if X then Result := <rhs>;' on the same line (drops trailing ';'), or ''
// if the line has no top-level bare-Result assignment.
function ResultRhs(const ALine: string): string;
var
  T, Low: string;
  P, SemiP, ScanFrom: Integer;
  PrevOk, NextOk: Boolean;
begin
  Result:= '';
  T:= Trim(StripLineComment(ALine));
  Low:= LowerCase(T);
  ScanFrom:= 1;
  while True do
  begin
    P:= Low.IndexOf('result', ScanFrom - 1) + 1; // 1-based Pos-style
    if P = 0 then Exit;
    // word boundary on both sides: not part of a longer identifier
    // (MyResult, Result2, ResultSet, ...).
    PrevOk:= (P = 1) or not CharInSet(Low[P - 1], ['a'..'z', 'A'..'Z', '0'..'9', '_']);
    NextOk:= (P + 6 > Length(Low)) or not CharInSet(Low[P + 6], ['a'..'z', 'A'..'Z', '0'..'9', '_']);
    if PrevOk and NextOk then
    begin
      // require ':=' immediately (tolerating spaces) after this 'result'
      var Rest: string:= TrimLeft(Copy(T, P + 6, MaxInt));
      if StartsStr(':=', Rest) then
      begin
        Rest:= Trim(Copy(Rest, 3, MaxInt));
        SemiP:= Pos(';', Rest);
        if SemiP > 0 then Rest:= Copy(Rest, 1, SemiP - 1);
        Exit(Trim(Rest));
      end;
    end;
    ScanFrom:= P + 6;
  end;
end;

// Extract '<rhs>' from 'Exit(<rhs>)', or '' if not a value-form Exit.
function ExitRhs(const ALine: string): string;
var
  T, Low: string;
  P, Depth, i, StartI: Integer;
begin
  Result:= '';
  T:= Trim(StripLineComment(ALine));
  Low:= LowerCase(T);
  if not StartsStr('exit', Low) then Exit;
  // Word-boundary check: the char right after 'exit' must not be alnum/underscore,
  // else this is an identifier call like ExitLoop(x)/Exitial, not a value-form Exit.
  if Length(Low) > Length('exit') then
  begin
    var NextCh: Char:= Low[Length('exit') + 1];
    if CharInSet(NextCh, ['a'..'z', '0'..'9', '_']) then Exit;
  end;
  P:= Pos('(', T);
  if P = 0 then Exit; // bare Exit; -- no value
  // capture balanced parens content
  Depth:= 0; StartI:= P + 1;
  for i:= P to Length(T) do
  begin
    if T[i] = '(' then Inc(Depth)
    else if T[i] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then Exit(Trim(Copy(T, StartI, i - StartI)));
    end;
  end;
end;

function MineReturnExpressions(const ABodyLines: TArray<string>): TArray<string>;
var
  Seen: TDictionary<string, Boolean>;
  Ordered: TList<string>;
  Line, Rhs: string;
begin
  Seen:= TDictionary<string, Boolean>.Create;
  Ordered:= TList<string>.Create;
  try
    for Line in ABodyLines do
    begin
      Rhs:= ResultRhs(Line);
      if Rhs = '' then Rhs:= ExitRhs(Line);
      if (Rhs <> '') and not Seen.ContainsKey(Rhs) then
      begin
        Seen.Add(Rhs, True);
        Ordered.Add(Rhs);
      end;
    end;
    Result:= Ordered.ToArray;
  finally
    Ordered.Free;
    Seen.Free;
  end;
end;

end.
