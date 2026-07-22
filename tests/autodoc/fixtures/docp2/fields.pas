unit fields;

// Fixture for Auto-Document Phase 2 Task 4 (Reads/Writes fields fact).
// TCounter's methods exercise every classification rule the fact's brief
// specifies:
//   * Bump reads FName (an 'if' guard) and writes FCount (an Inc target in
//     one branch, a plain ':=' in the other) -- its managed block must carry
//     'Reads: FName' and 'Writes: FCount' with NO overlap between the two.
//   * AddN ('FCount := FCount + N') reads AND writes the SAME field in one
//     statement -- FCount must appear in BOTH Reads and Writes.
//   * TouchMany writes NINE distinct fields (FA..FH, FCount) and reads none
//     -- proves the display cap (8 shown) + ' (+N more)' suffix, and that an
//     empty side (Reads, here) is omitted from the rendered line entirely
//     rather than rendered as an empty 'Reads: '.
// N (AddN's own parameter) shares no name with any field, so it never
// appears in either list.
// NOTE: FA..FH are declared ONE PER LINE deliberately -- a multi-name field
// declaration ('FA, FB: Integer;') is a PRE-EXISTING, unrelated indexer
// limitation (DRagLint.Parser.Delphi13's declField walk emits only the
// FIRST name of the list as a skField symbol), so this fixture avoids it
// rather than tripping over it.
// NOTE: Bump's if/then/else branches are wrapped in begin/end deliberately --
// a BARE (non-begin/end) 'if C then Inc(X) else Y := Z;' is a PRE-EXISTING,
// unrelated tree-sitter-delphi13 grammar ambiguity (the whole construct
// misparses as one 'assignment' node wrapping a malformed 'exprIf', so Y
// reads back as a READ instead of a WRITE) -- this fixture avoids it rather
// than tripping over it.

interface

type
  TCounter = class
  private
    FCount: Integer;
    FName : string;
    FA: Integer;
    FB: Integer;
    FC: Integer;
    FD: Integer;
    FE: Integer;
    FF: Integer;
    FG: Integer;
    FH: Integer;
  public
    procedure Bump;
    procedure AddN(N: Integer);
    procedure TouchMany;
  end;

implementation

procedure TCounter.Bump;
begin
  if FName <> '' then
  begin
    Inc(FCount);
  end
  else
  begin
    FCount := 0;
  end;
end;

procedure TCounter.AddN(N: Integer);
begin
  FCount := FCount + N;
end;

procedure TCounter.TouchMany;
begin
  FA := 1;
  FB := 1;
  FC := 1;
  FD := 1;
  FE := 1;
  FF := 1;
  FG := 1;
  FH := 1;
  FCount := 1;
end;

end.
