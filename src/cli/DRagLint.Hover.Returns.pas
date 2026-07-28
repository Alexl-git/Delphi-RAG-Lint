unit DRagLint.Hover.Returns;

/// <summary>Mine a routine body for the distinct expressions it returns, so the
/// hover "Returns" section can show real Result:= / Exit(...) values without an
/// LLM. Pure text: the caller supplies the routine's own body lines.</summary>

interface

/// <summary>Distinct right-hand sides of `Result := &lt;rhs>` and value-form
/// `Exit(&lt;rhs>)` in ABodyLines, in first-seen source order.</summary>
/// <param name="ABodyLines">The routine's implementation body lines
///   (impl_start_line..impl_end_line), one string per source line.</param>
/// <param name="AQualifiedName">The documented routine's QUALIFIED name
///   (TSymbol.QualifiedName -- 'returns.TBox.ClassLag', not 'ClassLag'). Used
///   only to confirm that a span whose first line is not the header
///   nevertheless begins at THIS routine's header, which is a test the SIMPLE
///   name cannot carry: two classes with a method of the same name sit
///   adjacent in the implementation section and their headers' last components
///   are identical. Pass '' when there is no name to give, which costs the
///   recovery of such a span and never mis-attributes one.</param>
/// <returns>Distinct RHS strings, trimmed, dedup'd. EMPTY when none was found
///   AND empty when the routine mutates Result in a way this enumeration
///   cannot express -- see the remarks.</returns>
/// <remarks>Not authoritative -- a display aid. It says nothing rather than
///   something it cannot state correctly, because the same text is read through
///   Help Insight and LSP hover:
///   <para>* WHOLE-Result assignments only. `Result.Field := x` and
///   `Result[i] := x` build the result, they are not return values, and
///   enumerating them does not scale (one real case populates 42 fields).</para>
///   <para>* NOTHING AT ALL when Result is mutated by Inc/Dec/SetLength or by a
///   self-referential `Result := ... Result ...`. The whole-Result assignments
///   are then only a seed, and naming the seed alone claims a value the routine
///   provably does not return. That test reads CODE ONLY -- comments and string
///   literals are blanked first, because suppression DELETES documentation and
///   a `{ old: Inc(Result); }` mutates nothing.</para>
///   <para>* NOTHING for an RHS that does not END on its own line (unbalanced
///   parentheses, a trailing binary operator). The capture is single-line; the
///   alternative to silence is shipping half an expression.</para>
///   <para>* A nested routine's Result belongs to that nested routine. The
///   caller passes the ENCLOSING routine's whole impl span, so local routines
///   and anonymous methods live inside those lines; their scopes are masked out
///   before mining. (This unit used to claim the caller's span excluded them.
///   It never did.)</para>
///   <para>* NOTHING when the span is STALE -- unless it can be proved to be
///   this routine's span. impl_start_line is normally the header line; an index
///   built before the last edit can start it earlier. The header is therefore
///   also accepted as the body's LEAD token (token 0, or the routine keyword of
///   a `class function`, whose `class` token comes first) -- but ONLY when the
///   dotted chain it declares is a component-wise TAIL of AQualifiedName.
///   Without that check the anchor latches onto whatever routine the span
///   happens to head, and the output then names a DIFFERENT routine's return
///   values: measured on one live index, 85 of the 100 spans the anchor was
///   eligible for headed some other routine. Checking the SIMPLE name only is
///   not enough either -- `TAlpha.Same` and `TBeta.Same` share it, and such
///   pairs are adjacent in the implementation section, which is where a stale
///   span lands.</para></remarks>
function MineReturnExpressions(const ABodyLines: TArray<string>;
  const AQualifiedName: string): TArray<string>;

type
  /// <summary>A mined return expression plus the 0-based index (within
  /// ABodyLines) of the line it was FIRST seen on -- so the caller can turn it
  /// into an absolute source line (ImplStartLine + LineOffset) for navigation.</summary>
  TReturnMined = record
    Expr      : string ;
    LineOffset: Integer;
  end;

/// <summary>Same mining as MineReturnExpressions, but also records where each
/// distinct RHS was first seen (0-based offset into ABodyLines), so the hover
/// popup can make each return value clickable and jump to its source line.</summary>
/// <param name="ABodyLines">The routine's implementation body lines.</param>
/// <param name="AQualifiedName">The documented routine's QUALIFIED name -- see
///   MineReturnExpressions.</param>
/// <returns>Distinct mined returns with their first-seen line offset. Expr is
///   always the LITERAL source RHS: the IDE plugin matches on that string to
///   find the line to navigate to, so nothing may be prefixed onto it.</returns>
/// <remarks>Same suppression rules as MineReturnExpressions -- see there.
///   Masking never changes the line COUNT, so LineOffset still indexes
///   ABodyLines.</remarks>
function MineReturnExpressionsEx(const ABodyLines: TArray<string>;
  const AQualifiedName: string): TArray<TReturnMined>;

implementation

uses
  System.SysUtils, System.StrUtils, System.Generics.Collections;

const
  { Stands in for every character of a nested routine's scope. Not a space: a
    run of spaces is indistinguishable from source formatting, and an expression
    that swallowed one would render as a plausible-looking value with a hole in
    it. A character that cannot occur in Pascal source lets the RHS capture
    recognise "this expression spans a nested routine" and say nothing instead. }
  NESTED_MASK = #1;

function IsIdentStart(C: Char): Boolean;
begin
  Result:= (C = '_') or ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z'));
end;

function IsIdentCh(C: Char): Boolean;
begin
  Result:= IsIdentStart(C) or ((C >= '0') and (C <= '9'));
end;

function StripLineComment(const S: string): string;
var
  P: Integer;
begin
  P:= Pos('//', S);
  if P > 0 then Result:= Copy(S, 1, P - 1) else Result:= S;
end;

{ ---------------------------------------------------------------------------
  Nested-scope masking.

  Doc.Facts hands this unit impl_start_line..impl_end_line of the ENCLOSING
  routine, so a local routine or an anonymous method is inside those lines and
  its `Result :=` used to be credited to the host. Blank those scopes out
  first; everything downstream then works on a body that contains only the
  routine's own statements.
  --------------------------------------------------------------------------- }

type
  TMaskTok = record
    Line  : Integer;   // 0-based index into the body-line array
    Col   : Integer;   // 1-based
    EndCol: Integer;   // 1-based, inclusive
    Text  : string ;   // lowercased identifier, or the single symbol character
    IsWord: Boolean;
  end;

  TNestFrame = record
    Line : Integer;
    Col  : Integer;
    Depth: Integer;    // block depth OUTSIDE the nested routine
  end;

// Identifiers plus the four symbols the nested-routine detector needs, with
// Pascal strings and all three comment forms skipped. Comment state carries
// across lines, which is why this is one pass over the whole body rather than
// a per-line scan.
//
// ACodeOnly is the SAME lines with every comment and every string literal
// (delimiters included) replaced by spaces -- same line count, same column
// positions, so a range blanked in one can be blanked in the other. It exists
// because this file has exactly one scanner that knows where code is, and the
// MUTATION test needs that knowledge: `{ old: Inc(Result); }` is parked dead
// code and `Format('Result := Result + 1')` is prose, and a mutation "found"
// in either DELETES a true <returns> from a routine that has none.
//
// The MINING scan deliberately does NOT use this view: mined text is rendered,
// and blanking a `{AReadOnly=}` in the middle of an expression would leave a
// hole in the sentence a reader sees (register K23 -- mining out of a comment
// is a separate, still-open defect).
procedure TokenizeBody(const ALines: TArray<string>; AToks: TList<TMaskTok>;
  out ACodeOnly: TArray<string>);
var
  InBrace, InParenStar: Boolean ;
  Li, I, N, J, Q      : Integer ;
  Ln, Code            : string  ;
  T                   : TMaskTok;

  procedure Blank(AFrom, ATo: Integer);
  var
    K: Integer;
  begin
    if AFrom < 1 then AFrom:= 1;
    if ATo > N then ATo:= N;
    for K:= AFrom to ATo do Code[K]:= ' ';
  end;

begin
  SetLength(ACodeOnly, Length(ALines));
  InBrace:= False;
  InParenStar:= False;
  for Li:= 0 to High(ALines) do
  begin
    Ln:= ALines[Li];
    Code:= Ln;
    N:= Length(Ln);
    I:= 1;
    while I <= N do
    begin
      if InBrace then
      begin
        Blank(I, I);
        if Ln[I] = '}' then InBrace:= False;
        Inc(I);
        Continue;
      end;
      if InParenStar then
      begin
        if (Ln[I] = '*') and (I < N) and (Ln[I + 1] = ')') then
        begin
          Blank(I, I + 1);
          InParenStar:= False;
          Inc(I, 2);
          Continue;
        end;
        Blank(I, I);
        Inc(I);
        Continue;
      end;
      if Ln[I] = '{' then begin InBrace:= True; Blank(I, I); Inc(I); Continue; end;
      if (Ln[I] = '(') and (I < N) and (Ln[I + 1] = '*') then
      begin
        InParenStar:= True;
        Blank(I, I + 1);
        Inc(I, 2);
        Continue;
      end;
      if (Ln[I] = '/') and (I < N) and (Ln[I + 1] = '/') then
      begin
        Blank(I, N);
        Break;
      end;
      if Ln[I] = '''' then
      begin
        Q:= I;                       // the opening quote
        Inc(I);
        while I <= N do
        begin
          if Ln[I] = '''' then
          begin
            if (I < N) and (Ln[I + 1] = '''') then begin Inc(I, 2); Continue; end;
            Inc(I);
            Break;
          end;
          Inc(I);
        end;
        Blank(Q, I - 1);             // the whole literal, delimiters included
        Continue;
      end;
      if IsIdentStart(Ln[I]) then
      begin
        J:= I;
        while (J <= N) and IsIdentCh(Ln[J]) do Inc(J);
        T.Line:= Li; T.Col:= I; T.EndCol:= J - 1;
        T.Text:= LowerCase(Copy(Ln, I, J - I));
        T.IsWord:= True;
        AToks.Add(T);
        I:= J;
        Continue;
      end;
      // ':' is tokenized purely so the nested-routine detector can tell
      // `function: Integer;` (a PARAMETERLESS procedural type -- the token
      // after the keyword is the RETURN TYPE) from `function Twice(...)` (a
      // named nested routine). Nothing else consumes it.
      if CharInSet(Ln[I], ['(', ')', ';', ':']) then
      begin
        T.Line:= Li; T.Col:= I; T.EndCol:= I;
        T.Text:= Ln[I];
        T.IsWord:= False;
        AToks.Add(T);
      end;
      Inc(I);
    end;
    ACodeOnly[Li]:= Code;
  end;
end;

procedure BlankRange(var ALines: TArray<string>; ALine, AFrom, ATo: Integer);
var
  S: string ;
  K: Integer;
begin
  if (ALine < 0) or (ALine > High(ALines)) then Exit;
  S:= ALines[ALine];
  if AFrom < 1 then AFrom:= 1;
  if ATo > Length(S) then ATo:= Length(S);
  for K:= AFrom to ATo do S[K]:= NESTED_MASK;
  ALines[ALine]:= S;
end;

function IsRoutineKeyword(const AWord: string): Boolean;
begin
  Result:= (AWord = 'function') or (AWord = 'procedure') or (AWord = 'constructor')
        or (AWord = 'destructor') or (AWord = 'operator');
end;

function IsBlockOpener(const AWord: string): Boolean;
begin
  Result:= (AWord = 'begin') or (AWord = 'case') or (AWord = 'try')
        or (AWord = 'asm') or (AWord = 'record');
end;

// True when the routine keyword at token index AKw is the body's LEAD header --
// the very first token, or the keyword of a `class function` / `class procedure`
// / `class constructor` / `class operator`, whose `class` token comes first. An
// implementation header has nothing else in front of it, so one leading `class`
// is the whole allowance.
function IsLeadKeyword(AToks: TList<TMaskTok>; AKw: Integer): Boolean;
begin
  Result:= (AKw = 0)
        or ((AKw = 1) and AToks[0].IsWord and (AToks[0].Text = 'class'));
end;

// The WHOLE dotted chain the header at token AKw declares, lowercased, or ''
// when no identifier follows the keyword.
//
//   function PlainSum(A: Integer)        -> 'plainsum'
//   class function TBox.ClassLag(A: ...) -> 'tbox.classlag'
//   constructor TFoo.Create              -> 'tfoo.create'
//
// The chain, not its last component. The last component alone cannot tell
// `TAlpha.Same` from `TBeta.Same`, and same-named methods on sibling classes --
// or two overloads -- sit ADJACENT in the implementation section, which is
// exactly where a stale span lands. Census -- (file, simple-name) groups holding
// more than one distinct impl_start_line, counted as GROUPS / SYMBOL ROWS
// (FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.impl_start_line > 0
// GROUP BY LOWER(f.path), LOWER(s.name) HAVING COUNT(DISTINCT
// s.impl_start_line) > 1): YADF 73 / 158, drag-lint's own index 84 / 200,
// ORM3 98 / 414. The self-index figure COUNTS THIS RULE'S OWN FIXTURE PAIR --
// (tests\autodoc\fixtures\docp3\returns.pas, 'same') -- so an index built
// before that fixture existed reads 83 / 198 instead.
//
// Components must be joined by a literal '.' on the SAME line, so the walk stops
// at the first token that is not part of the qualified name. A GENERIC header
// (`function TList<T>.Add`) therefore yields the TYPE name alone -- '<' is not
// '.' -- and IsQualifiedTail then declines the anchor. That is the safe
// direction (absence over wrong), and it costs nothing measurable: NOT ONE of
// the spans the anchor is eligible for carries a generic header, on any of the
// three corpora. That population is 103 spans, ONE PER SYMBOL ROW -- YADF 100,
// a freshly reindexed drag-lint src\ 0, ORM3 3 (tools/measure/returns_blast.py
// anchor <db> [<prefix>], which prints the count per corpus). The generic
// reading is taken off the RAW SOURCE line the anchor landed on, not off this
// function's chain, which cannot see a '<' at all.
function HeaderChainAt(AToks: TList<TMaskTok>; AKw: Integer;
  const ALines: TArray<string>): string;
var
  J, PrevLine, PrevEnd: Integer ;
  T                   : TMaskTok;
  Ln                  : string  ;
begin
  Result  := '';
  PrevLine:= -1;
  PrevEnd := 0;
  J:= AKw + 1;
  while J < AToks.Count do
  begin
    T:= AToks[J];
    if not T.IsWord then Break;
    if PrevLine >= 0 then
    begin
      if (T.Line <> PrevLine) or (T.Col <> PrevEnd + 2) then Break;
      if (T.Line < 0) or (T.Line > High(ALines)) then Break;
      Ln:= ALines[T.Line];
      if (PrevEnd + 1 > Length(Ln)) or (Ln[PrevEnd + 1] <> '.') then Break;
      Result:= Result + '.' + T.Text;
    end
    else
      Result:= T.Text;
    PrevLine:= T.Line;
    PrevEnd := T.EndCol;
    Inc(J);
  end;
end;

// True when AChain -- the dotted name an implementation header declares -- is a
// COMPONENT-WISE TAIL of AQualifiedName, the index's fully qualified name for
// the routine being documented.
//
//   'plainsum'      vs 'returns.PlainSum'        -> True
//   'tbox.classlag' vs 'returns.TBox.ClassLag'   -> True
//   'talpha.same'   vs 'returns.TBeta.Same'      -> FALSE, and that is the point
//
// A TAIL rather than a fixed component count, because the unit prefix is itself
// dotted and of unknown length ('DRagLint.Hover.Returns.MineReturnExpressions').
// The component BOUNDARY is load-bearing: a plain EndsText would accept 'same'
// as a tail of 'returns.TBeta.NotSame'.
//
// RESIDUAL, disclosed rather than implied: an UNQUALIFIED chain still matches
// the last component of any qualified name, so a plain routine `Same` adjacent
// to a method `TBeta.Same` is not separated by this test. Nothing in the two
// strings can separate them -- 'Unit.Same' and 'Unit.TBeta.Same' differ only by
// a component that may equally be part of a dotted unit name. Measured at 0 on
// YADF, drag-lint's own index and ORM3 (returns_blast.py anchor prints it as
// "ACCEPTED on an UNQUALIFIED header for a `method`"); register K30.
function IsQualifiedTail(const AChain, AQualifiedName: string): Boolean;
var
  L: Integer;
begin
  Result:= False;
  if (AChain = '') or (AQualifiedName = '') then Exit;
  if SameText(AChain, AQualifiedName) then Exit(True);
  L:= Length(AQualifiedName) - Length(AChain);
  if L < 2 then Exit;             // no room for a '.' and a component before it
  Result:= (AQualifiedName[L] = '.')
       and SameText(Copy(AQualifiedName, L + 1, Length(AChain)), AChain);
end;

// Replace every character of every NESTED routine scope with NESTED_MASK,
// leaving the line COUNT and every other column untouched (LineOffset still
// indexes the caller's array). ACodeOnly comes back masked over the same
// ranges, so the mutation test sees the same scopes.
//
// A routine keyword ARMS a candidate; the next block opener CONFIRMS it and the
// matching 'end' closes it. Two things must not be swallowed:
//
//   * the routine's OWN header, AND ONLY THAT. impl_start_line is USUALLY the
//     header line, so body line 0 is the primary anchor. But an index built
//     before the last edit starts the span somewhere else, and then the header
//     reads as a nested routine and the whole body is blanked. So the header is
//     also accepted as the body's LEAD token -- token 0, or the routine keyword
//     of a `class function`, whose `class` token comes first (IsLeadKeyword).
//
//     The lead-token anchor is NAME-CHECKED, and that is the load-bearing half.
//     Comments and blank lines emit no tokens, so "the body's first token" can
//     sit arbitrarily many lines down and head a COMPLETELY DIFFERENT routine.
//     Measured on the shipping YADF index (returns_blast.py anchor): the clause
//     is eligible on 100 spans and 85 of them -- 85% -- head some other routine,
//     because that index holds duplicate `files` rows for one path differing
//     only in drive-letter case, so spans land 26 to 63 lines out. Accepting
//     those did not recover a lost <returns>; it published another routine's
//     return values under this routine's name, which is the exact defect this
//     unit exists to prevent. With the name check the same index recovers one
//     row (YADF.Groups.ParseGroups) and mis-attributes none.
//
//     The check is on the WHOLE dotted chain against the QUALIFIED name, not
//     on the simple name. `class function TBeta.Same` over a span that begins
//     above `class function TAlpha.Same` finds a header whose last component
//     is `same` too, so a simple-name check reports a match and hands back the
//     sibling's return value. That adjacency is the normal one for overloads
//     and for same-named methods on sibling classes: YADF holds 73 (file,
//     simple-name) groups with more than one distinct impl_start_line over 158
//     symbol rows, drag-lint's own index 84 / 200 -- one of those groups being
//     this rule's own fixture pair -- and ORM3 98 / 414.
//
//     What is deliberately NOT done is accepting the first routine keyword
//     ANYWHERE: over the same corpora that re-reads spans starting deep inside
//     the PREVIOUS routine -- garbage in, unpredictable out -- and one row stops
//     emitting altogether. The name check would reject most of those too, but a
//     span that starts mid-routine has no honest reading at all.
//
//   * a PROCEDURAL TYPE -- `var F: function(X: Integer): Integer;` spells the
//     keyword and opens no scope. It is told apart by having no identifier
//     after the keyword AND by reaching a ';' (or leaving its parentheses)
//     before any block opener; a NAMED nested routine has the identifier, so
//     the ';' ending its own header must not disarm it. The PARAMETERLESS form
//     `var F: function: Integer;` has no parentheses either, and the token
//     after the keyword is its RETURN TYPE -- a word, which read as a name made
//     the ';' stop disarming and the routine's own begin confirm the frame,
//     blanking the entire body. Hence ':' is a token: after the keyword it says
//     "return type follows", i.e. no name.
function MaskNestedRoutines(const ABodyLines: TArray<string>;
  const AQualifiedName: string; out ACodeOnly: TArray<string>): TArray<string>;
var
  Toks     : TList<TMaskTok> ;
  Stk      : TStack<TNestFrame>;
  Fr       : TNestFrame      ;
  T, Nx    : TMaskTok        ;
  Ti       : Integer         ;
  Depth    : Integer         ;
  Paren    : Integer         ;
  HeaderSeen, HavePend, PendNamed: Boolean;
  PendLine, PendCol, PendParen   : Integer;
  X, A, B                        : Integer;
begin
  SetLength(Result, Length(ABodyLines));
  for Ti:= 0 to High(ABodyLines) do Result[Ti]:= ABodyLines[Ti];
  ACodeOnly:= nil;
  if Length(ABodyLines) = 0 then Exit;

  Toks:= TList<TMaskTok>.Create;
  Stk := TStack<TNestFrame>.Create;
  try
    TokenizeBody(ABodyLines, Toks, ACodeOnly);
    Depth:= 0; Paren:= 0;
    HeaderSeen:= False; HavePend:= False; PendNamed:= False;
    PendLine:= 0; PendCol:= 0; PendParen:= 0;
    for Ti:= 0 to Toks.Count - 1 do
    begin
      T:= Toks[Ti];
      if not T.IsWord then
      begin
        if T.Text = '(' then Inc(Paren)
        else if T.Text = ')' then
        begin
          Dec(Paren);
          if HavePend and (not PendNamed) and (Paren < PendParen) then HavePend:= False;
        end
        else if T.Text = ';' then
        begin
          if HavePend and (not PendNamed) and (Paren = PendParen) then HavePend:= False;
        end;
        Continue;
      end;
      if IsRoutineKeyword(T.Text) then
      begin
        // The documented routine's own header -- see above. Body line 0 is the
        // unconditional anchor; the LEAD-TOKEN anchor must additionally prove
        // the header it found is THIS routine's, or it anchors a foreign one.
        // An empty AQualifiedName proves nothing, and IsQualifiedTail returns
        // False for it, so it declines rather than silently re-enabling the
        // unchecked form.
        if (not HeaderSeen) and (Stk.Count = 0)
           and ((T.Line = 0)
                or (IsLeadKeyword(Toks, Ti)
                    and IsQualifiedTail(HeaderChainAt(Toks, Ti, ABodyLines),
                                        AQualifiedName))) then
        begin
          HeaderSeen:= True;
          Continue;
        end;
        if Stk.Count > 0 then Continue;   // already inside a masked scope
        PendNamed:= False;
        if Ti + 1 < Toks.Count then
        begin
          Nx:= Toks[Ti + 1];
          PendNamed:= Nx.IsWord and (Nx.Text <> 'of');
        end;
        PendLine:= T.Line; PendCol:= T.Col; PendParen:= Paren;
        HavePend:= True;
        Continue;
      end;
      if IsBlockOpener(T.Text) then
      begin
        if HavePend then
        begin
          Fr.Line:= PendLine; Fr.Col:= PendCol; Fr.Depth:= Depth;
          Stk.Push(Fr);
          HavePend:= False;
        end;
        Inc(Depth);
        Continue;
      end;
      if T.Text = 'end' then
      begin
        Dec(Depth);
        if (Stk.Count > 0) and (Depth <= Stk.Peek.Depth) then
        begin
          Fr:= Stk.Pop;
          for X:= Fr.Line to T.Line do
          begin
            if X = Fr.Line then A:= Fr.Col else A:= 1;
            if X = T.Line then B:= T.EndCol else B:= MaxInt;
            BlankRange(Result, X, A, B);
            BlankRange(ACodeOnly, X, A, B);
          end;
        end;
      end;
    end;
  finally
    Stk.Free;
    Toks.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Where the right-hand side ends.
  --------------------------------------------------------------------------- }

function IsBlockStopWord(const AWord: string): Boolean;
begin
  // Keywords that can legally follow a statement WITHOUT a ';' between them.
  // `begin Result := X end` has no ';' at all, and without these the capture
  // ran on into `end else begin Result := 0 end`.
  Result:= (AWord = 'end') or (AWord = 'else') or (AWord = 'until')
        or (AWord = 'finally') or (AWord = 'except');
end;

function IsTailOperator(const AWord: string): Boolean;
begin
  Result:= (AWord = 'and') or (AWord = 'or') or (AWord = 'not') or (AWord = 'xor')
        or (AWord = 'div') or (AWord = 'mod') or (AWord = 'shl') or (AWord = 'shr')
        or (AWord = 'in')  or (AWord = 'is')  or (AWord = 'as')
        or (AWord = 'to')  or (AWord = 'downto');
end;

// An RHS that simply ran out of line is only trustworthy if it could be a whole
// expression: balanced brackets (checked by the caller) and not left dangling
// on an operator. `Result := True` is complete; `Result := (A > 0) and` is the
// first half of something.
function LooksComplete(const S: string): Boolean;
var
  T, W: string ;
  J   : Integer;
begin
  T:= TrimRight(S);
  if T = '' then Exit(False);
  if CharInSet(T[Length(T)], ['+', '-', '*', '/', ',', '=', '<', '>', '@', '^', '.', ':', '&', '|']) then
    Exit(False);
  J:= Length(T);
  while (J > 0) and IsIdentCh(T[J]) do Dec(J);
  W:= LowerCase(Copy(T, J + 1, MaxInt));
  Result:= not IsTailOperator(W);
end;

// The expression text of ARest, and whether it actually ENDED on this line.
// String- and bracket-aware: a ';' inside a literal is not a terminator, and a
// stop keyword only counts at bracket depth zero.
function CutRhs(const ARest: string; out ATerminated: Boolean): string;
var
  I, N, J, Paren: Integer;
  Closed        : Boolean;
begin
  ATerminated:= False;
  Paren:= 0;
  I:= 1;
  N:= Length(ARest);
  while I <= N do
  begin
    if ARest[I] = '''' then
    begin
      Inc(I);
      Closed:= False;
      while I <= N do
      begin
        if ARest[I] = '''' then
        begin
          if (I < N) and (ARest[I + 1] = '''') then begin Inc(I, 2); Continue; end;
          Inc(I);
          Closed:= True;
          Break;
        end;
        Inc(I);
      end;
      if not Closed then Exit(ARest);   // unterminated literal: never complete
      Continue;
    end;
    if CharInSet(ARest[I], ['(', '[']) then Inc(Paren)
    else if CharInSet(ARest[I], [')', ']']) then
    begin
      Dec(Paren);
      if Paren < 0 then
      begin
        ATerminated:= True;
        Exit(Copy(ARest, 1, I - 1));
      end;
    end
    else if (ARest[I] = ';') and (Paren = 0) then
    begin
      ATerminated:= True;
      Exit(Copy(ARest, 1, I - 1));
    end
    else if IsIdentStart(ARest[I]) then
    begin
      J:= I;
      while (J <= N) and IsIdentCh(ARest[J]) do Inc(J);
      if (Paren = 0) and IsBlockStopWord(LowerCase(Copy(ARest, I, J - I))) then
      begin
        ATerminated:= True;
        Exit(Copy(ARest, 1, I - 1));
      end;
      I:= J;
      Continue;
    end;
    Inc(I);
  end;
  ATerminated:= (Paren = 0) and LooksComplete(ARest);
  Result:= ARest;
end;

// Extract '<rhs>' from 'Result := <rhs> ;', including a guarded form like
// 'if X then Result := <rhs>;' on the same line, or '' if the line has no
// top-level bare-Result assignment, if the RHS does not end on this line, or
// if it spans a masked nested routine.
function ResultRhs(const ALine: string): string;
var
  T, Low, Rest, Cut: string ;
  P, ScanFrom      : Integer;
  PrevOk, NextOk   : Boolean;
  Terminated       : Boolean;
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
      // require ':=' immediately (tolerating spaces) after this 'result'.
      // `Result.Field :=` and `Result[i] :=` fail here, which is how member and
      // element assignments stay out of the enumeration.
      Rest:= TrimLeft(Copy(T, P + 6, MaxInt));
      if StartsStr(':=', Rest) then
      begin
        Rest:= Trim(Copy(Rest, 3, MaxInt));
        Cut:= CutRhs(Rest, Terminated);
        if not Terminated then Exit('');
        if Pos(NESTED_MASK, Cut) > 0 then Exit('');
        Exit(Trim(Cut));
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
      if Depth = 0 then
      begin
        Result:= Trim(Copy(T, StartI, i - StartI));
        if Pos(NESTED_MASK, Result) > 0 then Result:= '';
        Exit;
      end;
    end;
  end;
end;

{ ---------------------------------------------------------------------------
  Mutation detection.
  --------------------------------------------------------------------------- }

// True when ALow (already lowercased) calls AName with Result as its FIRST
// argument. Only the three RTL intrinsics whose first parameter is var by
// language definition are asked about, so no name resolution is needed.
function CallsIntrinsicOnResult(const ALow, AName: string): Boolean;
var
  P, L      : Integer;
  Rest, Tail: string ;
begin
  Result:= False;
  L:= Length(AName);
  P:= 1;
  repeat
    P:= Pos(AName, ALow, P);
    if P = 0 then Exit;
    if (P = 1) or not IsIdentCh(ALow[P - 1]) then
    begin
      Rest:= TrimLeft(Copy(ALow, P + L, MaxInt));
      if StartsStr('(', Rest) then
      begin
        Rest:= TrimLeft(Copy(Rest, 2, MaxInt));
        if StartsStr('result', Rest) then
        begin
          Tail:= TrimLeft(Copy(Rest, 7, MaxInt));
          if (Tail = '') or CharInSet(Tail[1], [',', ')']) then Exit(True);
        end;
      end;
    end;
    Inc(P, L);
  until False;
end;

// True when S mentions Result as a whole identifier.
function MentionsResult(const S: string): Boolean;
var
  Low           : string ;
  P             : Integer;
  PrevOk, NextOk: Boolean;
begin
  Result:= False;
  Low:= LowerCase(S);
  P:= 1;
  repeat
    P:= Pos('result', Low, P);
    if P = 0 then Exit;
    PrevOk:= (P = 1) or not IsIdentCh(Low[P - 1]);
    NextOk:= (P + 6 > Length(Low)) or not IsIdentCh(Low[P + 6]);
    if PrevOk and NextOk then Exit(True);
    Inc(P, 6);
  until False;
end;

// True when the body changes Result by something other than a whole-Result
// assignment, which makes the enumeration of those assignments a seed rather
// than an account of the return value.
//
// ACodeOnly MUST be TokenizeBody's code-only view, not the raw body. This
// function only ever DELETES a <returns>, so every false positive silently
// destroys true documentation -- and a `{ old: Inc(Result); }` or a
// `Format('Result := Result + 1')` are not mutations of anything. Passing raw
// lines here suppressed three such routines.
//
// DELIBERATELY NOT DETECTED: Result handed to a USER routine's var/out
// parameter. That needs the callee's signature, which a pure text miner does
// not have, and the naive text test ("Result appears as a whole argument") is
// dominated by pure READS -- measured over drag-lint's own src, 135 of 251 such
// sites are Length/SizeOf/Exists. Suppressing on those would delete correct
// <returns> sections to catch a form neither corpus contains.
function HasResultMutation(const ACodeOnly: TArray<string>): Boolean;
var
  Ln, Low, Rhs: string ;
  I           : Integer;
begin
  for I:= 0 to High(ACodeOnly) do
  begin
    Ln:= ACodeOnly[I];
    Low:= LowerCase(Ln);
    if CallsIntrinsicOnResult(Low, 'inc')       then Exit(True);
    if CallsIntrinsicOnResult(Low, 'dec')       then Exit(True);
    if CallsIntrinsicOnResult(Low, 'setlength') then Exit(True);
    Rhs:= ResultRhs(Ln);
    if (Rhs <> '') and MentionsResult(Rhs) then Exit(True);
  end;
  Result:= False;
end;

function MineReturnExpressionsEx(const ABodyLines: TArray<string>;
  const AQualifiedName: string): TArray<TReturnMined>;
var
  Masked : TArray<string>               ;
  Code   : TArray<string>               ;
  Seen   : TDictionary<string, Boolean> ;
  Ordered: TList<TReturnMined>          ;
  Rhs    : string                       ;
  M      : TReturnMined                 ;
  i      : Integer                      ;
begin
  Result:= nil;
  Masked:= MaskNestedRoutines(ABodyLines, AQualifiedName, Code);
  // Absence over wrong: a mutated Result makes every whole-Result assignment
  // below a seed, and naming a seed claims a value the routine may never return.
  // Asked of the CODE-ONLY view -- suppression is destructive, so a mutation
  // that only exists in a comment or inside a string literal must not fire.
  if HasResultMutation(Code) then Exit;
  Seen:= TDictionary<string, Boolean>.Create;
  Ordered:= TList<TReturnMined>.Create;
  try
    for i:= 0 to High(Masked) do
    begin
      Rhs:= ResultRhs(Masked[i]);
      if Rhs = '' then Rhs:= ExitRhs(Masked[i]);
      if (Rhs <> '') and not Seen.ContainsKey(Rhs) then
      begin
        Seen.Add(Rhs, True);
        M.Expr:= Rhs;
        M.LineOffset:= i;
        Ordered.Add(M);
      end;
    end;
    Result:= Ordered.ToArray;
  finally
    Ordered.Free;
    Seen.Free;
  end;
end;

function MineReturnExpressions(const ABodyLines: TArray<string>;
  const AQualifiedName: string): TArray<string>;
var
  Mined: TArray<TReturnMined>;
  i    : Integer             ;
begin
  { Thin wrapper over the line-aware miner -- callers that only need the RHS text
    (e.g. the auto-document facts builder) stay on this signature. }
  Mined:= MineReturnExpressionsEx(ABodyLines, AQualifiedName);
  SetLength(Result, Length(Mined));
  for i:= 0 to High(Mined) do Result[i]:= Mined[i].Expr;
end;

end.
