unit returns;

interface

// Auto-Document Phase 3, Task 4b -- the <returns> MINING fixture.
//
// Source: docs/INBOX-autodoc-returns-section-incomplete.md. The generated
// <returns> line "names a value the function provably does not return", and
// that same text is read every day through Help Insight and LSP hover. Every
// routine below is a small stand-in for a VERIFIED real case in
// C:\Projects\YADF, named in the comment above it.
//
// THE RULE THE FIXTURE ENCODES: absence over wrong. Where the miner cannot
// state the returned value correctly it states nothing -- it never guesses,
// and it never leaks a fragment of raw syntax into prose.
//
// FIVE GROUPS, plus the controls that keep each of them falsifiable. TWO MORE
// scenarios live in the runner rather than here, because they are properties of
// the INDEX and not of the source -- a STALE span, which is what an index built
// before the last edit holds:
//
//   * a span that begins EARLY but still inside the routine's own header --
//     PlainSum, AnonHost, LocalHost and TBox.ClassLag, hovered again against a
//     copy of the index whose impl_start_line was moved back by one line. The
//     routine's own header must still be recognised, ClassLag included: for a
//     `class function` the FIRST token of the body is `class`, not the routine
//     keyword.
//
//   * a span that begins inside a DIFFERENT ROUTINE -- ForeignB, hovered
//     against a copy of the index whose impl_start_line was moved onto the
//     blank line above ForeignA's header. Measured on the shipping
//     C:\Projects\YADF\YADF.sqlite, that is what the majority of stale spans
//     look like: 85 of the 100 spans eligible for the first-token rule -- one
//     per SYMBOL ROW, tools\measure\returns_blast.py anchor <db> -- head
//     some OTHER routine, several of them tens of lines away. The required
//     answer is ABSENCE. Emitting ForeignA's return value under ForeignB's
//     name is the exact defect this whole task exists to remove, and a
//     "recovery" that does it is a regression.
//
//   * the same, where the two routines SHARE A SIMPLE NAME -- TAlpha.Same and
//     TBeta.Same. An anchor that compares only the LAST dotted component of
//     the header it found cannot tell them apart, so TBeta.Same adopts
//     TAlpha.Same's value while the check that is supposed to prevent exactly
//     that reports a match. It is not an exotic shape: overloads and
//     same-named methods on sibling classes are usually ADJACENT in the
//     implementation section, which is precisely where a stale span lands.
//     Census over the three live indexes -- (file, simple-name) groups holding
//     more than one distinct impl_start_line -- YADF 73 groups / 158 symbol
//     rows, drag-lint's own index 84 / 200, ORM3 98 / 414. One of the
//     self-index groups is THIS FILE's own TAlpha.Same / TBeta.Same pair, so a
//     self-index built before this fixture reads 83 / 198. The anchor is
//     therefore checked against the symbol's QUALIFIED-NAME TAIL, not its
//     simple name.
//
//   MUTATION   PrevIdx / Accum -- Result is changed by something other than a
//              whole-Result assignment (Dec(Result); Result := Result + x), so
//              the enumeration of whole-Result assignments is not an account
//              of what comes back. Suppressed entirely.
//   NESTED     AnonHost / LocalHost -- an anonymous method and a named local
//              routine live INSIDE the enclosing routine's indexed impl span,
//              so their own Result assignments used to be credited to the
//              enclosing routine. Both hosts still return a real value of
//              their own, deliberately: an absent <returns> would make
//              "the nested Result is not here" vacuous.
//   CAPTURE    OneLiner / MultiLineRhs / NestedCallRhs -- where the RHS ends.
//              A `begin Result := X end` line has no ';' at all and used to
//              swallow `end else begin Result := 0 end`; an RHS continued on
//              the next line used to emit the unbalanced first half.
//   MEMBERS    DefaultCfg -- Result.<Field> := is NOT a return value and must
//              never be enumerated (YADF's DefaultOptions populates 42 fields
//              in a row). This already works; it is here as a regression.
//   NOT-CODE   BraceCommentInc / BraceCommentSelfRef / ParenStarSetLength /
//              StrLiteralResult -- the mutation that suppresses must be a
//              mutation IN CODE. A `{ old: Inc(Result); }` is parked dead code
//              and 'Result := Result + 1' inside a format string is prose;
//              suppressing on either DELETES a true <returns> from a routine
//              that mutates nothing. Suppression is the destructive direction,
//              so these four are the controls that bound it.
//
// CONTROLS: PlainSum, DoubleIt, ConcatPath, NestedCallRhs, OneLiner, AnonHost,
// LocalHost, InlineProcVar, ParamlessProcVar, LocalProcTypeDecl,
// BraceCommentInc, BraceCommentSelfRef, ParenStarSetLength, StrLiteralResult,
// TBox.ClassLag, ForeignA, ForeignB, TAlpha.Same and TBeta.Same must ALL still
// render an Observed: line. A rule that simply stopped emitting <returns> would
// satisfy every absence check in this file and fail these nineteen.
//
// InlineProcVar / ParamlessProcVar / LocalProcTypeDecl are the guard on the
// nested-routine detector itself: a local PROCEDURAL-TYPE spells the `function`
// keyword inside the routine's declaration part but opens no scope. A detector
// that armed on the keyword and confirmed on the next `begin` would swallow the
// whole routine body and the routine's own return would vanish. THREE of them,
// because the forms are told apart by different tokens and a guard over one
// form is not a guard over the others: InlineProcVar's `function(X: Integer)`
// is disarmed by its parentheses, while ParamlessProcVar's `function: Integer`
// and LocalProcTypeDecl's `type TGetter = function: Integer` have none -- the
// token after the keyword is their RETURN TYPE, and reading it as a routine
// NAME is exactly what made the detector eat both of them.

type
  TCfg = record
    Alpha  : Integer;
    Beta   : Integer;
    Gamma  : Integer;
    Delta  : Integer;
    Sigma  : Integer;
    Omega  : Integer;
  end;

  TIntGetter = reference to function(const ARec: TCfg): Integer;

  // The `class function` carrier. A class method's implementation header
  // begins with the `class` token, NOT with the routine keyword, so a span
  // that starts one line early leaves the routine keyword as the body's
  // SECOND token. Hovered against a lagged span in the runner.
  TBox = class
    class function ClassLag(A: Integer): Integer;
  end;

  // The same-simple-name pair. Both classes declare a method called `Same`, and
  // their implementations are ADJACENT in that order with a blank line above
  // TAlpha's -- the arrangement a compiler encourages and a stale span lands
  // in. Their return values are deliberately distinct and unique in this file,
  // so "TBeta.Same adopted TAlpha.Same's value" is a check that can only pass
  // one way. Hovered against a doctored span in the runner.
  TAlpha = class
    class function Same(A: Integer): Integer;
  end;

  TBeta = class
    class function Same(A: Integer): Integer;
  end;

// Plain, complete, unmutated, no nesting. The load-bearing control.
`r`nfunction PlainSum(A, B: Integer): Integer;

// Second control, and the callee InlineProcVar assigns to its local.
`r`nfunction DoubleIt(X: Integer): Integer;

// Third control, and the callee NestedCallRhs nests twice over.
`r`nfunction ConcatPath(const A, B: string): string;

function PrevIdx(const AItems: TArray<Integer>; AFrom: Integer): Integer;

function Accum(const AItems: TArray<Integer>): Integer;

function DefaultCfg(ASeed: Integer): TCfg;

// YADF.Options.pas:796 SharedAppDataIniPath -- a nested call with a space
// after the open paren, on ONE physical line, ending in ';'.
`r`nfunction NestedCallRhs(const ADir, AName: string): string;

function MultiLineRhs(A, B: Integer): Boolean;

// YADF.Options.pas OptionTable's second defect -- a Result assignment with no
// ';' anywhere on its line.
`r`nfunction OneLiner(A: Integer): Integer;

// YADF.Options.pas OptionTable -- an anonymous method's Result inside the
// enclosing routine's span.
`r`nfunction AnonHost(const ACfg: TCfg): Integer;

// The same, for a NAMED local routine.
`r`nfunction LocalHost(A: Integer): Integer;

// The nested-routine detector's own guard -- see the header note.
`r`nfunction InlineProcVar(A: Integer): Integer;

// The PARAMETERLESS procedural-type variable. No parentheses to disarm the
// detector, and the word after `function` is the RETURN TYPE.
`r`nfunction ParamlessProcVar(A: Integer): Integer;

// The same shape declared as a local TYPE rather than a var.
`r`nfunction LocalProcTypeDecl(A: Integer): Integer;

// A mutation of Result parked in a {...} comment is not a mutation: this
// routine's CODE contains no Inc(Result), and it returns exactly A + 100.
`r`nfunction BraceCommentInc(A: Integer): Integer;

// The same for a self-referential assignment left behind in a comment.
`r`nfunction BraceCommentSelfRef(A: Integer): Integer;

// ... and for the (*..*) comment form, with the third detected intrinsic.
`r`nfunction ParenStarSetLength(A: Integer): string;

// 'Result := Result + 1' as PROSE inside a format string. Nothing is mutated
// and the whole expression, semicolon and all, is one physical line.
`r`nfunction StrLiteralResult(A: Integer): string;

// ForeignA and ForeignB are ADJACENT, in this order, with a blank line above
// ForeignA's header. The runner moves ForeignB's indexed impl_start_line onto
// that blank line, so ForeignB's span then begins one line above ANOTHER
// routine's header and covers ForeignA's whole body. ForeignA's return value
// is deliberately unique in this file, so "ForeignB adopted it" is a check
// that can only pass one way.
`r`nfunction ForeignA(A: Integer): Integer;

// The victim of the doctored span. With its TRUE span it returns A - 7; with
// the doctored one it must return NOTHING.
`r`nfunction ForeignB(A: Integer): Integer;

// Driver exists so that every declaration above is actually DOCUMENTED.
// `document --unit` writes no comment at all for a decl whose facts block
// would come out empty, so an absence assertion ("this routine's block has no
// Observed:") over an uncalled routine would be an assertion over a block that
// was never written. Driver gives each of them one caller, which is enough.
`r`nprocedure Driver;

implementation

uses
  System.SysUtils;

function PlainSum(A, B: Integer): Integer;
begin
  Result := A + B;
end;

function DoubleIt(X: Integer): Integer;
begin
  Result := X * 2;
end;

function ConcatPath(const A, B: string): string;
begin
  Result := A + '.' + B;
end;

function PrevIdx(const AItems: TArray<Integer>; AFrom: Integer): Integer;
begin
  Result := AFrom;
  while (Result >= 0) and (AItems[Result] = 0) do
    Dec(Result);
end;

function Accum(const AItems: TArray<Integer>): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(AItems) do
    Result := Result + AItems[I];
end;

function DefaultCfg(ASeed: Integer): TCfg;
begin
  Result.Alpha := ASeed + 1;
  Result.Beta  := ASeed + 2;
  Result.Gamma := ASeed + 3;
  Result.Delta := ASeed + 4;
  Result.Sigma := ASeed + 5;
  Result.Omega := ASeed + 6;
end;

function NestedCallRhs(const ADir, AName: string): string;
begin
  Result := ConcatPath( ConcatPath(ADir, 'sub'), AName);
end;

function MultiLineRhs(A, B: Integer): Boolean;
begin
  Result := (A > 0) and
            (B > 0);
end;

function OneLiner(A: Integer): Integer;
begin
  if A > 0 then begin Result := A * 3 end else begin Result := 0 end;
end;

function AnonHost(const ACfg: TCfg): Integer;
var
  F: TIntGetter;
begin
  F := function(const AInner: TCfg): Integer begin Result := AInner.Beta end;
  Result := F(ACfg) + 1;
end;

function LocalHost(A: Integer): Integer;

  function Twice(X: Integer): Integer;
  begin
    Result := X * 5;
  end;

begin
  Result := Twice(A) + 1;
end;

function InlineProcVar(A: Integer): Integer;
var
  F: function(X: Integer): Integer;
begin
  F := DoubleIt;
  Result := F(A) + 9;
end;

function ParamlessProcVar(A: Integer): Integer;
var
  F: function: Integer;
begin
  F := nil;
  Result := F() + A;
end;

function LocalProcTypeDecl(A: Integer): Integer;
type
  TGetter = function: Integer;
var
  G: TGetter;
begin
  G := nil;
  Result := G() + A;
end;

function BraceCommentInc(A: Integer): Integer;
begin
  { old implementation: Inc(Result); }
  Result := A + 100;
end;

function BraceCommentSelfRef(A: Integer): Integer;
begin
  { was: Result := Result + 1; }
  Result := A + 200;
end;

function ParenStarSetLength(A: Integer): string;
begin
  (* dead: SetLength(Result, A); *)
  Result := 'p' + IntToStr(A);
end;

function StrLiteralResult(A: Integer): string;
begin
  Result := Format('Result := Result + 1; %d', [A]);
end;

class function TBox.ClassLag(A: Integer): Integer;
begin
  Result := A + 41;
end;

function ForeignA(A: Integer): Integer;
begin
  Result := A * 7;
end;

function ForeignB(A: Integer): Integer;
begin
  Result := A - 7;
end;

class function TAlpha.Same(A: Integer): Integer;
begin
  Result := A * 11;
end;

class function TBeta.Same(A: Integer): Integer;
begin
  Result := A * 22;
end;

procedure Driver;
var
  C: TCfg;
begin
  C := DefaultCfg(0);
  if MultiLineRhs(PlainSum(1, 2), DoubleIt(3)) then
    C.Alpha := OneLiner(4);
  C.Beta  := PrevIdx([0], 1) + Accum([1]) + AnonHost(C) + LocalHost(1) + InlineProcVar(2);
  C.Gamma := Length(NestedCallRhs('a', 'b')) + Length(ConcatPath('a', 'b'));
  C.Delta := ParamlessProcVar(5) + LocalProcTypeDecl(6) + BraceCommentInc(7) + BraceCommentSelfRef(8);
  C.Omega := Length(ParenStarSetLength(9)) + Length(StrLiteralResult(10));
  C.Sigma := C.Alpha + C.Beta + C.Gamma + C.Delta + C.Omega
           + TBox.ClassLag(11) + ForeignA(12) + ForeignB(13)
           + TAlpha.Same(14) + TBeta.Same(15);
end;

end.
