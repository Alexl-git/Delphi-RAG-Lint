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

// Extract '<rhs>' from 'Result := <rhs> ;' (drops trailing ';'), or '' if the
// line is not a Result assignment.
function ResultRhs(const ALine: string): string;
var
  T, Low: string;
  P, SemiP: Integer;
begin
  Result:= '';
  T:= Trim(StripLineComment(ALine));
  Low:= LowerCase(T);
  if not StartsStr('result', Low) then Exit;
  // require ':=' after 'result' (tolerate spaces)
  P:= Pos(':=', T);
  if P = 0 then Exit;
  if Trim(Copy(T, 1, P - 1)).ToLower <> 'result' then Exit; // not a bare Result
  T:= Trim(Copy(T, P + 2, MaxInt));
  SemiP:= Pos(';', T);
  if SemiP > 0 then T:= Copy(T, 1, SemiP - 1);
  Result:= Trim(T);
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
