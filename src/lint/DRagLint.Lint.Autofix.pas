unit DRagLint.Lint.Autofix;

{ The autofix registry: which lint rules carry a fix, which of those fixes are
  opt-in, risky or single-fix-only, and the builder that turns findings into
  TTextEdit records. Moved verbatim out of DRagLint.CLI (autofix wave lane A0,
  2026-10-27) so a lane that adds a fix never edits CLI.pas: the CLI keeps only
  the call sites. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Refactor.TextEdit
  ;

/// <summary>Is ARuleId a rule with a registered autofix?</summary>
/// <param name="ARuleId">A lint rule id; compared case-insensitively.</param>
/// <returns>True for every id in FIXABLE_RULE_IDS.</returns>
/// <remarks>The single source of truth for `rules --json`.fixable, the
/// `--fix --json` row's `fixable` and what the fix verbs attempt.</remarks>
function IsFixableRule(const ARuleId: string): Boolean;

/// <summary>Is ARuleId a fixable rule whose fix applies only when opted in?</summary>
/// <param name="ARuleId">A lint rule id; compared case-insensitively.</param>
/// <returns>True for the naming fixes in OPT_IN_FIX_RULE_IDS.</returns>
function IsOptInFixRule(const ARuleId: string): Boolean;

/// <summary>Every rule id with a registered autofix, in declaration order.</summary>
/// <returns>A fresh copy of FIXABLE_RULE_IDS; the caller owns the array.</returns>
function FixableRuleIds: TArray<string>;

/// <summary>True iff the rule's registered fix is behaviour-CHANGING (not merely
/// a redundant-code cleanup).</summary>
/// <param name="ARuleId">A lint rule id; compared case-insensitively.</param>
/// <returns>True for the ids in RISKY_FIX_RULE_IDS.</returns>
/// <remarks>Such fixes are still applied, but callers surface a 'risky' flag so
/// a human/AI reviews before trusting a batch apply.</remarks>
function IsRiskyFixRule(const ARuleId: string): Boolean;

/// <summary>True iff the rule's registered fix is SINGLE-FIX-ONLY: applied for a
/// single targeted finding but excluded from the blanket batch.</summary>
/// <param name="ARuleId">A lint rule id; compared case-insensitively.</param>
/// <returns>True for the ids in SINGLE_FIX_ONLY_RULE_IDS (today missing-doc).</returns>
function IsSingleFixOnlyRule(const ARuleId: string): Boolean;

/// <summary>Builds the pure-text quick-fix edits for the subset of AFindings whose
/// rule has a registered autofix.</summary>
/// <param name="AFindings">The findings to fix; rules without a fix are skipped.</param>
/// <param name="AFixableCount">Out: how many findings produced a fix.</param>
/// <returns>The edits, unordered; TTextEditApplier orders and applies them.</returns>
/// <remarks>Store-backed fixes (doc-drift, missing-doc, the naming renames,
/// raise-bare-exception) are NOT built here -- see the implementation comment.</remarks>
function BuildAutofixEdits(const AFindings: TArray<TLintFinding>; out AFixableCount: Integer): TArray<TTextEdit>;

implementation

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.StrUtils
  , System.Generics.Collections
  , DRagLint.Diagnostics.AstChecks
  ;
{ The set of rule-ids that have a registered, mechanical, side-effect-free
  quick-fix. Single source of truth for both the rules-catalog 'fixable' flag
  and the fix verbs. Widening AutoFix = add an id here AND a branch in
  BuildAutofixEdits (kept in lockstep; a guard test asserts they agree).
  EXCEPTION: store-backed fixes (doc-drift, missing-doc, method-pascalcase,
  local-var-casing, const-casing, field-name-prefix, param-name-prefix,
  type-name-prefix, raise-bare-exception) are fixable but have NO
  BuildAutofixEdits branch --
  doc-drift/missing-doc edits come from TDocumenter.BuildFor and the naming
  re-casing/prefix-adding edits come from DRagLint.Refactor.NamingFix.Build-
  NamingFixEdits (the rename engine), both via a store-backed append in
  FinalizeAndOutput, not from the pure-text edit builder.
  raise-bare-exception joins them: its replacement class NAME is read out of
  the exceptions unit's managed block, so a pure-text builder could not know
  it -- BuildExceptionRewriteEdits supplies those edits the same way. }
const
  FIXABLE_RULE_IDS: array[0..22] of string = (
    'self-assignment', 'redundant-parentheses', 'redundant-cast', 'redundant-not-not', 'redundant-as-tobject', 'boolean-comparison-true', 'reserved-word-casing',
    'redundant-assigned-free', 'off-by-one-count', 'doc-drift', 'missing-doc',
    'method-pascalcase', 'local-var-casing', 'const-casing',
    'field-name-prefix', 'param-name-prefix', 'type-name-prefix',
    'nil-comparison', 'uppercase-compare', 'uppercase-compare-always-false', 'unused-local',
    { local-field-prefix: strips an F prefix off a LOCAL. Safest rename in the
      family -- single-routine scope, so no call site can be affected. }
    'local-field-prefix',
    { raise-bare-exception: `raise Exception.Create('x')` -> the generated
      class for that message, plus the uses entry. Gated on exceptions-sync
      having run, and it SKIPS any file that tests the class exactly. }
    'raise-bare-exception');

function IsFixableRule(const ARuleId: string): Boolean;
var
  S: string;
begin
  for S in FIXABLE_RULE_IDS do
    if SameText(S, ARuleId) then Exit(True);
  Result:= False;
end;

{ The NAMING fixes. Each rewrites a declaration and every use the index knows
  about -- project-wide -- so `lint --fix` applies one only when the config
  opts it in ("autofix": [...] in drag-lint-lint.json) AND a store is open.
  One list, read by the fixer AND by `rules --json` (`fix_opt_in`): the IDE
  counted these as fixable, offered "Fix all in unit (78)" on ORM3's
  BASICS.PAS, and the run then reported "no fixable findings" (2026-10-13). }
const
  OPT_IN_FIX_RULE_IDS: array[0..6] of string = (
    'method-pascalcase', 'local-var-casing', 'const-casing', 'field-name-prefix',
    'param-name-prefix', 'type-name-prefix', 'local-field-prefix');

/// <summary>Is ARuleId a fixable rule whose fix applies only when opted in?</summary>
/// <param name="ARuleId">A lint rule id; compared case-insensitively.</param>
/// <returns>True for the naming fixes in OPT_IN_FIX_RULE_IDS.</returns>
function IsOptInFixRule(const ARuleId: string): Boolean;
var
  S: string;
begin
  for S in OPT_IN_FIX_RULE_IDS do
    if SameText(S, ARuleId) then Exit(True);
  Result:= False;
end;

function FixableRuleIds: TArray<string>;
var
  i: Integer;
begin
  SetLength(Result, Length(FIXABLE_RULE_IDS));
  for i:= 0 to High(FIXABLE_RULE_IDS) do Result[i]:= FIXABLE_RULE_IDS[i];
end;

{ Behaviour-CHANGING fixes: still applied by Fix-it/Fix-all, but tagged so a
  human/AI orchestrator is warned. off-by-one-count appends ' - 1' to a loop
  bound, which breaks an intentionally-inclusive loop.
  uppercase-compare-always-false recases the literal so a comparison that could
  NEVER be true becomes capable of being true -- that is the whole point of the
  fix, but it means a previously-dead branch starts executing, so a human has to
  confirm the branch was meant to run. }
const
  RISKY_FIX_RULE_IDS: array[0..1] of string = ('off-by-one-count', 'uppercase-compare-always-false');

  /// <summary>True iff the rule's registered fix is behaviour-CHANGING (not merely
  /// a redundant-code cleanup). Such fixes are still applied, but callers surface a
  /// 'risky' flag so a human/AI reviews before trusting a batch apply.</summary>
function IsRiskyFixRule(const ARuleId: string): Boolean;
var
  S: string;
begin
  for S in RISKY_FIX_RULE_IDS do
    if SameText(S, ARuleId) then Exit(True);
  Result:= False;
end;

{ Fixable rules whose fix is offered ONLY for a single targeted finding (the IDE
  "Fix it" on one decl, or `lint-all --fix --fix-line/--fix-rule`), and DELIBERATELY
  EXCLUDED from the blanket batch (`lint-all --fix` / "Fix all"). Currently only
  missing-doc: batch-documenting every undocumented decl project-wide is what
  `document --project` is for (facts-only default + --stubs control); folding it
  into the blanket batch would inject TODO stubs across a whole project. }
const
  SINGLE_FIX_ONLY_RULE_IDS: array[0..0] of string = ('missing-doc');

  /// <summary>True iff the rule's registered fix is SINGLE-FIX-ONLY: applied for a
  /// single targeted finding (IDE "Fix it" / --fix-line + --fix-rule) but excluded
  /// from the blanket `lint-all --fix` batch so it does not mass-inject edits.</summary>
function IsSingleFixOnlyRule(const ARuleId: string): Boolean;
var
  S: string;
begin
  for S in SINGLE_FIX_ONLY_RULE_IDS do
    if SameText(S, ARuleId) then Exit(True);
  Result:= False;
end;

/// <summary>True iff S (trimmed) needs NO extra parentheses to be the operand of
/// a unary 'not'. That holds when S is either (a) a lone primary term -- an
/// identifier or dotted chain, optionally followed only by balanced call '(...)'
/// / index '[...]' groups and '.ident' segments, with NO top-level operator and
/// NO top-level whitespace -- OR (b) already a single fully-enclosing '(...)'
/// group (the opening paren balances exactly at the last character).
/// Errs toward False (compound): over-wrapping 'not (X)' is harmless, but
/// under-wrapping 'not a and b' silently changes meaning.</summary>
function IsSingleTokenAtom(const S: string): Boolean;
var
  T    : string                           ;
  i    : Integer                          ;
  Depth: Integer                          ;
  C    : Char                             ;
  function IsIdentStart(Ch: Char): Boolean;
  begin Result:= CharInSet(Ch, ['A'..'Z','a'..'z','_']); end;
  function IsIdentChar(Ch: Char): Boolean;
  begin Result:= CharInSet(Ch, ['A'..'Z','a'..'z','_','0'..'9']); end;
begin
  T:= Trim(S);
  if T = '' then Exit(False);

  { (b) already a single fully-enclosing '(...)' group: the leading '(' must
    balance to depth 0 only at the very last character (so '(a) and (b)' does
    NOT qualify -- its first '(' closes mid-string). }
  if T[1] = '(' then
  begin
    Depth:= 0;
    for i:= 1 to Length(T) do
    begin
      if T[i]      = '(' then Inc(Depth)
      else if T[i] = ')' then
      begin
        Dec(Depth);
        if (Depth = 0) then Exit(i = Length(T)); { balanced only at the end => atomic }
      end;
    end;
    Exit(False); { unbalanced }
  end;

  { (a) lone primary term. }
  if not IsIdentStart(T[1]) then Exit(False);
  Depth:= 0;
  i    := 1;
  while i <= Length(T) do
  begin
    C:= T[i];
    if (C = '(') or (C = '[') then Inc(Depth)
    else if (C = ')') or (C = ']') then begin Dec(Depth); if Depth < 0 then Exit(False); end
    else if Depth = 0 then
    begin
      { at top level, only identifier chars and a '.' between segments are allowed;
        anything else (whitespace, operator char, ',', ':', etc.) => compound. }
      if not (IsIdentChar(C) or (C = '.')) then Exit(False);
    end;
    Inc(i);
  end;
  Result:= (Depth = 0);
end; // begin

/// <summary>Builds the quick-fix text edits for the subset of AFindings whose
/// rule has a registered autofix (the FIXABLE_RULE_IDS set). Mechanical, no
/// type info:
///   self-assignment       -> delete the offending statement line(s);
///   redundant-parentheses -> strip the outer '(' ')' of the flagged span;
///   redundant-cast        -> strip a 'TFoo(x)' cast where x is one identifier;
///   redundant-not-not     -> strip the two leading 'not' keywords;
///   redundant-as-tobject  -> strip the ' as TObject' suffix;
///   boolean-comparison-true -> X=True/X&lt;&gt;False->X; X=False/X&lt;&gt;True->not X;
///   reserved-word-casing  -> lowercase the keyword token;
///   redundant-assigned-free -> drop the 'if Assigned(X) then' guard;
///   off-by-one-count      -> append ' - 1' to the loop bound (RISKY);
///   unused-local          -> remove the dead declaration (AST-driven, grouped
///                            per file -- see below).
/// AFixableCount returns how many findings produced a fix. Rules without a fix
/// are silently skipped.</summary>
/// <remarks>Deliberately conservative: only rules whose fix is an exact,
/// side-effect-free text edit are wired. redundant-parentheses is fixed only
/// when the flagged span is single-line and literally starts with '(' and ends
/// with ')'. Best for non-overlapping findings; same-line multi-fixes are not
/// column-reconciled (the applier orders by line).
/// unused-local is the ONE rule here that is NOT per-finding: it is delegated,
/// once per file, to TAstChecker.BuildUnusedLocalFixEdits. Several dead names can
/// share one declaration, so whether that declaration may be deleted outright or
/// must have its name list spliced depends on every finding against it -- and the
/// emptied-'var'-block collapse depends on the whole section. Per-finding edits
/// here would delete still-used variables and stack overlapping deletes on one
/// line, so that grouping is load-bearing, not a tidiness choice.</remarks>
function BuildAutofixEdits(const AFindings: TArray<TLintFinding>; out AFixableCount: Integer): TArray<TTextEdit>;
var
  F    : TLintFinding                    ;
  E    : TTextEdit                       ;
  EndL : Integer                         ;
  Cache: TDictionary<string, TStringList>;
  SL   : TStringList                     ;
  Ln   : string                          ;
  Span : string                          ;
  Repl : string                          ;

  function LinesFor(const APath: string): TStringList;
  begin
    if not Cache.TryGetValue(APath, Result) then
    begin
      Result:= TStringList.Create;
      if TFile.Exists(APath) then Result.Text:= TEncoding.ANSI.GetString(TFile.ReadAllBytes(APath));
      Cache.Add(APath, Result);
    end;
  end;
begin
  Result:= nil;
  AFixableCount:= 0;
  Cache:= TDictionary<string, TStringList>.Create;
  try
    for F in AFindings do
    begin
      if SameText(F.RuleId, 'self-assignment') then
      begin
        EndL:= F.EndLine;
        if EndL < F.StartLine then EndL:= F.StartLine;
        E:= Default(TTextEdit);
        E.FilePath:= F.FilePath;
        E.Kind:= tekDeleteLines;
        E.Line:= F.StartLine;
        E.EndLine:= EndL;
        Result:= Result + [E];
        Inc(AFixableCount);
      end
      else if SameText(F.RuleId, 'redundant-parentheses') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          if (Length(Span) >= 2) and (Span[1] = '(') and (Span[Length(Span)] = ')') then
          begin
            Repl:= Copy(Span, 2, Length(Span) - 2); { strip the outer parens }
            E:= Default(TTextEdit);
            E.FilePath:= F.FilePath;
            E.Kind:= tekReplaceInLine;
            E.Line  := F.StartLine;
            E.Col   := F.StartCol;
            E.EndCol:= F.EndCol;
            E.Text:= Repl;
            Result:= Result + [E];
            Inc(AFixableCount);
          end;
        end; // if
      end // if
      { v(autofix-compare): `X = nil` -> `not Assigned(X)`, `X <> nil` -> `Assigned(X)`.
        The rule pins @warn to the whole exprBinary, so the span is the complete
        comparison. Note the polarity inversion: `= nil` means NOT assigned. }
      else if SameText(F.RuleId, 'nil-comparison') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          var NcOpAt : Integer:= Pos('<>', Span);
          var NcOpLen: Integer:= 2;
          var NcNeg  : Boolean:= False;   { True -> the fix needs a leading `not` }
          if NcOpAt <= 0 then
          begin
            NcOpAt := Pos('=', Span);
            NcOpLen:= 1;
            NcNeg  := True;               { `X = nil` is "not assigned" }
          end;
          if NcOpAt > 1 then
          begin
            var NcLhs: string:= Trim(Copy(Span, 1, NcOpAt - 1));
            var NcRhs: string:= Trim(Copy(Span, NcOpAt + NcOpLen, MaxInt));
            if SameText(NcRhs, 'nil') and (NcLhs <> '') then
            begin
              Repl:= 'Assigned(' + NcLhs + ')';
              if NcNeg then Repl:= 'not ' + Repl;
              E:= Default(TTextEdit);
              E.FilePath:= F.FilePath;
              E.Kind    := tekReplaceInLine;
              E.Line    := F.StartLine;
              E.Col     := F.StartCol;
              E.EndCol  := F.EndCol;
              E.Text    := Repl;
              Result:= Result + [E];
              Inc(AFixableCount);
            end;
          end;
        end; // if
      end
      { v(autofix-compare): `UpperCase(X) = 'ABC'` -> `SameText(X, 'ABC')` (and
        `<>` -> `not SameText(...)`). Only the STYLE variant of the rule reaches
        here -- the always-false variant is a separate rule id below, because
        rewriting THAT one to SameText would silently turn a never-matching test
        into a sometimes-matching one.
        The operator is located in the text BEFORE the first quote, so a literal
        containing '=' or '<>' ('a<>b') cannot be mistaken for the operator. }
      else if SameText(F.RuleId, 'uppercase-compare') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          var UcOpen: Integer:= Pos('(', Span);
          var UcClose: Integer:= 0;
          if UcOpen > 0 then
          begin
            var UcDepth: Integer:= 0;
            for var UcQ: Integer:= UcOpen to Length(Span) do
            begin
              if Span[UcQ] = '(' then Inc(UcDepth)
              else if Span[UcQ] = ')' then
              begin
                Dec(UcDepth);
                if UcDepth = 0 then begin UcClose:= UcQ; Break; end;
              end;
            end;
          end;
          if UcClose > UcOpen then
          begin
            var UcInner: string := Trim(Copy(Span, UcOpen + 1, UcClose - UcOpen - 1));
            var UcRest : string := Copy(Span, UcClose + 1, MaxInt);
            var UcQuote: Integer:= Pos('''', UcRest);
            if (UcInner <> '') and (UcQuote > 1) then
            begin
              var UcNeg: Boolean:= Pos('<>', Copy(UcRest, 1, UcQuote - 1)) > 0;
              var UcLit: string := Trim(Copy(UcRest, UcQuote, MaxInt));
              if UcLit <> '' then
              begin
                Repl:= 'SameText(' + UcInner + ', ' + UcLit + ')';
                if UcNeg then Repl:= 'not ' + Repl;
                E:= Default(TTextEdit);
                E.FilePath:= F.FilePath;
                E.Kind    := tekReplaceInLine;
                E.Line    := F.StartLine;
                E.Col     := F.StartCol;
                E.EndCol  := F.EndCol;
                E.Text    := Repl;
                Result:= Result + [E];
                Inc(AFixableCount);
              end;
            end;
          end; // if
        end; // if
      end
      { v(autofix-compare): the always-false variant. The fix RECASES THE LITERAL
        to agree with the conversion (`UpperCase(X) = 'abc'` -> `... = 'ABC'`),
        which preserves the author's evident intent and makes the comparison
        capable of being true. Deliberately NOT a SameText rewrite: that also
        works, but it changes case-sensitivity as well as fixing the dead branch,
        and one behaviour change at a time is enough. Registered RISKY -- a test
        that could never pass can now pass, which is the point, but a human must
        confirm that was the intent. }
      else if SameText(F.RuleId, 'uppercase-compare-always-false') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          var AfOpen: Integer:= Pos('(', Span);
          if AfOpen > 1 then
          begin
            var AfFn   : string := Trim(Copy(Span, 1, AfOpen - 1));
            var AfClose: Integer:= 0;
            var AfDepth: Integer:= 0;
            for var AfQ: Integer:= AfOpen to Length(Span) do
            begin
              if Span[AfQ] = '(' then Inc(AfDepth)
              else if Span[AfQ] = ')' then
              begin
                Dec(AfDepth);
                if AfDepth = 0 then begin AfClose:= AfQ; Break; end;
              end;
            end;
            if AfClose > AfOpen then
            begin
              var AfRest : string := Copy(Span, AfClose + 1, MaxInt);
              var AfQuote: Integer:= Pos('''', AfRest);
              if AfQuote > 0 then
              begin
                var AfLit: string:= Trim(Copy(AfRest, AfQuote, MaxInt));
                var AfNew: string;
                { Recase toward the conversion the code already performs. }
                if ContainsText(AfFn, 'upper') then AfNew:= UpperCase(AfLit)
                else                                AfNew:= LowerCase(AfLit);
                if (AfLit <> '') and (AfNew <> AfLit) then
                begin
                  E:= Default(TTextEdit);
                  E.FilePath:= F.FilePath;
                  E.Kind    := tekReplaceInLine;
                  E.Line    := F.StartLine;
                  E.Col     := F.StartCol;
                  E.EndCol  := F.EndCol;
                  E.Text    := Copy(Span, 1, AfClose + AfQuote - 1) + AfNew;
                  Result:= Result + [E];
                  Inc(AFixableCount);
                end;
              end;
            end;
          end; // if
        end; // if
      end
      else if SameText(F.RuleId, 'redundant-cast') and (F.StartLine = F.EndLine) then
      begin
        { redundant-cast fires only on 'TFoo(x)' with x a SINGLE identifier (the
          rule's precondition), so there is no nested paren: the ')' is the first
          one after the '('. The finding span [StartCol, EndCol) covers the entity
          name 'TFoo'; scan on to '(' then to ')' and replace 'TFoo(x)' with 'x'. }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          var OpenP: Integer:= F.EndCol; { 1-based; '(' expected at/after the name }
          while (OpenP <= Length(Ln)) and (Ln[OpenP] <> '(') do Inc(OpenP);
          if (OpenP <= Length(Ln)) and (Ln[OpenP] = '(') then
          begin
            var CloseP: Integer:= OpenP + 1;
            while (CloseP <= Length(Ln)) and (Ln[CloseP] <> ')') do Inc(CloseP);
            if (CloseP <= Length(Ln)) and (Ln[CloseP] = ')') then
            begin
              var Inner: string:= Trim(Copy(Ln, OpenP + 1, CloseP - OpenP - 1));
              if Inner <> '' then
              begin
                E:= Default(TTextEdit);
                E.FilePath:= F.FilePath;
                E.Kind:= tekReplaceInLine;
                E.Line:= F.StartLine;
                E.Col := F.StartCol;
                E.EndCol:= CloseP + 1; { exclusive end -- one past the ')' }
                E.Text:= Inner;
                Result:= Result + [E];
                Inc(AFixableCount);
              end;
            end;
          end; // if
        end; // if
      end // if
      else if SameText(F.RuleId, 'redundant-not-not') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        { span covers 'not not X' (the outer exprUnary). Strip the two leading
          'not' keywords + their trailing whitespace; the remainder is X. }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          var Rest: string:= Span;
          var Ok: Boolean:= True ;
          { consume 'not' then >=1 whitespace, twice }
          for var Pass: Integer:= 1 to 2 do
          begin
            var LR: string:= TrimLeft(Rest);
            if (Length(LR) >= 3) and SameText(Copy(LR, 1, 3), 'not') and ((Length(LR) = 3) or (LR[4] <= ' ')) then Rest:= TrimLeft(Copy(LR, 4, MaxInt))
            else
            begin Ok:= False; Break; end;
          end;
          if Ok and (Rest <> '') then
          begin
            E:= Default(TTextEdit);
            E.FilePath:= F.FilePath;
            E.Kind:= tekReplaceInLine;
            E.Line  := F.StartLine;
            E.Col   := F.StartCol;
            E.EndCol:= F.EndCol;
            E.Text:= Rest;
            Result:= Result + [E];
            Inc(AFixableCount);
          end;
        end; // if
      end // if
      else if SameText(F.RuleId, 'redundant-as-tobject') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        { span covers 'X as TObject' (the exprBinary). Find the depth-0 whole-word
          'as' keyword; the lhs before it is X. }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          { scan for ' as ' at bracket depth 0 (whole word, case-insensitive) }
          var Depth: Integer:= 0;
          var AsPos: Integer:= 0;
          for var K: Integer:= 2 to Length(Span) - 2 do
          begin
            var Ch: Char:= Span[K];
            if (Ch = '(') or (Ch = '[') then Inc(Depth)
            else if (Ch = ')') or (Ch = ']') then Dec(Depth)
            else if (Depth = 0) and (Span[K - 1] <= ' ') and SameText(Copy(Span, K, 2), 'as') and ((K + 2 > Length(Span)) or (Span[K + 2] <= ' ')) then
            begin AsPos:= K; Break; end;
          end;
          if AsPos > 1 then
          begin
            Repl:= TrimRight(Copy(Span, 1, AsPos - 1));
            if Repl <> '' then
            begin
              E:= Default(TTextEdit);
              E.FilePath:= F.FilePath;
              E.Kind:= tekReplaceInLine;
              E.Line  := F.StartLine;
              E.Col   := F.StartCol;
              E.EndCol:= F.EndCol;
              E.Text:= Repl;
              Result:= Result + [E];
              Inc(AFixableCount);
            end;
          end;
        end; // if
      end // if
      else if SameText(F.RuleId, 'boolean-comparison-true') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        { span covers 'X op bool', op is '=' or '<>', bool is True or False.
          Scan for the LAST depth-0 '=' or '<>' operator; split into lhs/op/rhs.
          positive (= True / <> False) -> lhs; negative (= False / <> True) ->
          'not ' + (lhs, parenthesized when not a single-token atom). }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          var Depth: Integer:= 0;
          var OpPos: Integer:= 0;
          var OpLen: Integer:= 0;
          for var K: Integer:= 1 to Length(Span) do
          begin
            var Ch: Char:= Span[K];
            if (Ch = '(') or (Ch = '[') then Inc(Depth)
            else if (Ch = ')') or (Ch = ']') then Dec(Depth)
            else if Depth = 0 then
            begin
              if (K < Length(Span)) and (Ch = '<') and (Span[K + 1] = '>') then
              begin OpPos:= K; OpLen:= 2; end
              else if Ch = '=' then
              begin OpPos:= K; OpLen:= 1; end;
            end;
          end;
          if OpPos > 1 then
          begin
            var LhsText: string:= Trim(Copy(Span, 1, OpPos - 1))         ;
            var OpText : string:= Copy(Span, OpPos, OpLen)               ;
            var RhsText: string:= Trim(Copy(Span, OpPos + OpLen, MaxInt));
            var IsTrue : Boolean:= SameText(RhsText, 'True' );
            var IsFalse: Boolean:= SameText(RhsText, 'False');
            var Positive: Boolean                                        ;
            if (LhsText <> '') and (IsTrue or IsFalse) then
            begin
              { (= True) or (<> False) => positive; (= False) or (<> True) => negative }
              if OpText = '=' then Positive:= IsTrue else Positive:= IsFalse;
              if Positive then Repl:= LhsText
              else if IsSingleTokenAtom(LhsText) then Repl:= 'not ' + LhsText
              else Repl:= 'not (' + LhsText + ')';
              E:= Default(TTextEdit);
              E.FilePath:= F.FilePath;
              E.Kind:= tekReplaceInLine;
              E.Line  := F.StartLine;
              E.Col   := F.StartCol;
              E.EndCol:= F.EndCol;
              E.Text:= Repl;
              Result:= Result + [E];
              Inc(AFixableCount);
            end; // if
          end; // if
        end; // if
      end // if
      else if SameText(F.RuleId, 'reserved-word-casing') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        { span covers the keyword token; keywords are case-insensitive and have no
          reference sites, so lowercasing the span is a safe local edit. }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          if (Span <> '') and (Span <> LowerCase(Span)) then
          begin
            E:= Default(TTextEdit);
            E.FilePath:= F.FilePath;
            E.Kind:= tekReplaceInLine;
            E.Line  := F.StartLine;
            E.Col   := F.StartCol;
            E.EndCol:= F.EndCol;
            E.Text:= LowerCase(Span);
            Result:= Result + [E];
            Inc(AFixableCount);
          end;
        end; // if
      end // if
      else if SameText(F.RuleId, 'redundant-assigned-free') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        { span covers 'if Assigned(X) then <stmt>;'. Take the text after the
          delimited 'then' keyword (whole word, not a substring of an identifier)
          to end of span. The Assigned guard is redundant -- Free is nil-safe. }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          var Depth  : Integer:= 0;
          var ThenEnd: Integer:= 0; { 1-based index one past the 'then' }
          var LS: string:= LowerCase(Span);
          for var K: Integer:= 1 to Length(Span) - 3 do
          begin
            var Ch: Char:= Span[K];
            if (Ch = '(') or (Ch = '[') then Inc(Depth)
            else if (Ch = ')') or (Ch = ']') then Dec(Depth)
            else if (Depth = 0) and (Copy(LS, K, 4) = 'then') and ((K = 1) or (Span[K - 1] <= ' ') or (Span[K - 1] = ')')) and ((K + 4 > Length(Span)) or (Span[K + 4] <= ' ')) then
            begin ThenEnd:= K + 4; Break; end;
          end;
          if ThenEnd > 0 then
          begin
            Repl:= TrimLeft(Copy(Span, ThenEnd, MaxInt));
            if Repl <> '' then
            begin
              E:= Default(TTextEdit);
              E.FilePath:= F.FilePath;
              E.Kind:= tekReplaceInLine;
              E.Line  := F.StartLine;
              E.Col   := F.StartCol;
              E.EndCol:= F.EndCol;
              E.Text:= Repl;
              Result:= Result + [E];
              Inc(AFixableCount);
            end;
          end;
        end; // if
      end // if
      else if SameText(F.RuleId, 'off-by-one-count') and (F.StartLine = F.EndLine) and (F.EndCol > F.StartCol) then
      begin
        { span covers the loop end-bound (X.Count / Length(X)). Append ' - 1'.
          BEHAVIOUR-CHANGING (tagged risky via IsRiskyFixRule). The bound is
          isolated by 'to .. do', so no precedence hazard. }
        SL:= LinesFor(F.FilePath);
        if (F.StartLine >= 1) and (F.StartLine <= SL.Count) then
        begin
          Ln:= SL[F.StartLine - 1];
          Span:= Copy(Ln, F.StartCol, F.EndCol - F.StartCol);
          if Trim(Span) <> '' then
          begin
            E:= Default(TTextEdit);
            E.FilePath:= F.FilePath;
            E.Kind:= tekReplaceInLine;
            E.Line  := F.StartLine;
            E.Col   := F.StartCol;
            E.EndCol:= F.EndCol;
            E.Text:= Span + ' - 1';
            Result:= Result + [E];
            Inc(AFixableCount);
          end;
        end; // if
      end; // if
    end; // for

    { unused-local is handled per FILE, not per finding: several dead names can
      share one declaration, and whether a declaration may be deleted outright
      (vs. having its name list spliced) depends on ALL the findings against it.
      Emitting one edit per finding -- the obvious shape -- deletes live
      variables and stacks overlapping deletes on the same line. Grouping also
      keeps at most one edit per declaration, so the applier never sees an
      overlap. Driven off the AST in TAstChecker, next to the check itself. }
    var ULFiles: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
    try
      for F in AFindings do
        if SameText(F.RuleId, 'unused-local') and (F.FilePath <> '') then
          ULFiles.AddOrSetValue(F.FilePath, True);
      for var ULPath: string in ULFiles.Keys do
      begin
        var ULFixed: Integer:= 0;
        var ULEdits: TArray<TTextEdit>:=
          DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits(ULPath, AFindings, ULFixed);
        if Length(ULEdits) > 0 then
        begin
          Result:= Result + ULEdits;
          Inc(AFixableCount, ULFixed);
        end;
      end;
    finally
      ULFiles.Free;
    end;
  finally
    for SL in Cache.Values do SL.Free;
    Cache.Free;
  end; // try
end; // begin

end.
