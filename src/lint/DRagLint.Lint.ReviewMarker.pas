unit DRagLint.Lint.ReviewMarker;

{ The `dl:ok` reviewed-marker: a visible, self-invalidating record that a human
  looked at one finding on one line and accepted it.

    except // dl:ok bare-except@7f3a -- rethrown by the caller

  The `@7f3a` is 4 hex of a hash over the line's CODE TOKENS -- comments
  excluded, whitespace dropped, identifiers lowercased, string-literal content
  preserved verbatim. That normalisation is chosen so YADF's reindentation and
  case normalisation do NOT invalidate a review, while a real edit does. When the
  hash no longer matches, the finding is re-reported rather than silently kept
  suppressed; a review that outlives the code it reviewed is worse than none.

  Everything here is PURE -- no file, store or config access -- so the whole
  contract is testable from a console program (tests\reviewmarker).

  Design: docs\superpowers\specs\2026-08-12-reviewed-marker-design.md }

interface

uses
  System.SysUtils, System.Hash;

type
  /// <summary>One `dl:ok &lt;rule-id&gt;[@&lt;hash&gt;]` entry parsed off a source
  /// line, together with the free-text reason shared by every entry on that
  /// line.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.ApplyLineMarkers (DRagLint.CLI.pas), DRagLint.CLI.DoAllow (DRagLint.CLI.pas), declaration (DRagLint.Lint.ReviewMarker.pas), DRagLint.Lint.ReviewMarker.TReviewMarkers.Parse (DRagLint.Lint.ReviewMarker.pas), DRagLint.Lint.ReviewMarker.TReviewMarkers.InsertInto (DRagLint.Lint.ReviewMarker.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Lint.ReviewMarker</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TReviewMarker = record
    /// <summary>Rule id exactly as written in the marker.</summary>
    RuleId: string;
    /// <summary>4 lowercase hex chars, or '' when the marker carries no
    /// `@hash` (hand-written and therefore unverifiable).</summary>
    Hash: string;
    /// <summary>Free text after the `--` separator; '' when absent.</summary>
    Reason: string;
  end;

  /// <summary>Parsing, hashing and insertion of `dl:ok` reviewed-markers. All
  /// members are pure.</summary>
  /// <remarks>
  /// Thread-safe: no shared state.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.ApplyLineMarkers (DRagLint.CLI.pas), DRagLint.CLI.DoAllow (DRagLint.CLI.pas)</para>
  /// <para>Used in units: DRagLint.CLI</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TReviewMarkers = class
  strict private
    /// <summary>1-based index just past the `//` that opens the line comment,
    /// skipping any `//` that occurs inside a string literal or a block
    /// comment; 0 when the line carries no line comment.</summary>
    /// <param name="ALineText"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Integer -- Observed: 0.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Lint.ReviewMarker.TReviewMarkers.InsertInto (DRagLint.Lint.ReviewMarker.pas), DRagLint.Lint.ReviewMarker.TReviewMarkers.Parse (DRagLint.Lint.ReviewMarker.pas)</para>
    /// <para>Complexity: 20 (cyclomatic, outer body), 47 lines (full implementation)</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.FormatMarker"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.HashLine"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.HashWindow"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.InsertInto"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.MarkerBearingLines"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function LineCommentStart(const ALineText: string): Integer; static;
    /// <summary>Splits the text following the `dl:ok` tag into the comma-separated
    /// rule list and the free-text reason, on whichever separator appears
    /// FIRST: a `--` that follows whitespace, or a `:`.</summary>
    /// <remarks>Both forms are accepted because both are written by hand. The
    /// loser is left in the reason verbatim, so `-- see note: why` keeps its
    /// colon. Rule ids and the 4-hex @hash contain no colon, which is what
    /// makes the first colon unambiguous.</remarks>
    /// <param name="AText"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ARules"><!-- drag-lint:auto type -->out string</param>
    /// <param name="AReason"><!-- drag-lint:auto type -->out string</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Lint.ReviewMarker.TReviewMarkers.Parse (DRagLint.Lint.ReviewMarker.pas)</para>
    /// <para>Calls: CharInSet, Copy, Trim</para>
    /// <para>Mutates: ARules (out), AReason (out)</para>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.FormatMarker"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.HashLine"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.HashWindow"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.InsertInto"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.LineCommentStart"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class procedure SplitReason(const AText: string; out ARules, AReason: string); static;
    /// <summary>Renders `&lt;rule&gt;@&lt;hash&gt;`, or just `&lt;rule&gt;` when
    /// AHash is ''.</summary>
    /// <param name="ARuleId"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AHash"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->string -- Observed: ARuleId.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Lint.ReviewMarker.TReviewMarkers.FormatMarker (DRagLint.Lint.ReviewMarker.pas), DRagLint.Lint.ReviewMarker.TReviewMarkers.InsertInto (DRagLint.Lint.ReviewMarker.pas)</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.FormatMarker"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.HashLine"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.HashWindow"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.InsertInto"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.LineCommentStart"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function RuleToken(const ARuleId, AHash: string): string; static;
  public
    /// <summary>For each line of a whole file, whether a `dl:ok` on that line
    /// could be a REAL marker rather than prose ABOUT one.</summary>
    /// <param name="ALines">Every line of the file, in order, without terminators.</param>
    /// <returns>One flag per input line, same indexing (0-based array, so line N
    /// is Result[N - 1]).</returns>
    /// <remarks>
    /// WHY A WHOLE-FILE PASS AND NOT A PER-LINE TEST. LineCommentStart above
    /// already skips string literals and block comments that open AND close on
    /// the one line it is given, but a single line cannot know that a `{` on an
    /// EARLIER line is still open. `review-marker-unused` walks every line of
    /// every scanned file looking for the tag, so it hit exactly that: two
    /// findings on the unit that DEFINES the marker syntax, neither line
    /// carrying a marker --
    /// * a line inside this unit's own `{ }` header block whose text reads
    /// like code plus a trailing marker, and is entirely commented out;
    /// * a `///` doc-comment line quoting the marker grammar as an example.
    /// The rule said a marker "no longer matches any finding" on lines that
    /// never had one, and advised removing documentation.
    /// "IGNORE MARKERS IN COMMENTS" IS NOT THE TEST -- a real marker is ALWAYS
    /// in a comment. The discriminator is WHICH comment: a `//` reached in code
    /// state can carry one; a `{ }` or `(* *)` block cannot, and neither can a
    /// `///` doc comment.
    /// DELIBERATELY NOT CHECKED: whether code precedes the `//`. A real marker
    /// always trails code, so requiring it would be MORE correct -- and would
    /// also stop reporting a stranded own-line marker as unused, which is a
    /// behaviour change neither reported case needs. Both come out right on
    /// block state and `///` alone, so that is all this does.
    /// SCOPE, and why this is safe: consumed ONLY by the unused-marker
    /// reporter, never by the suppression path. Suppression is decided against
    /// a line that already carries a finding, so this cannot cause a real
    /// `dl:ok` to stop suppressing -- the failure mode that would return every
    /// suppressed finding across every project at once with no signal as to
    /// why. Gating suppression too is a separate, measured change.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.ApplyLineMarkers (DRagLint.CLI.pas)</para>
    /// <para>Complexity: 20 (cyclomatic, outer body), 76 lines (full implementation)</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.FormatMarker"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.HashLine"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.HashWindow"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.InsertInto"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.LineCommentStart"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function MarkerBearingLines(const ALines: TArray<string>): TArray<Boolean>; static;
    /// <summary>The line reduced to its code tokens: comments removed,
    /// whitespace dropped, identifiers lowercased, string-literal content kept
    /// verbatim and case-sensitive. Compiler directives (`{$...}`, `(*$...*)`)
    /// count as CODE, not comment -- `{$IFDEF A}` and `{$IFDEF B}` are different
    /// programs and must not share a hash.</summary>
    /// <param name="ALineText">One source line, without its line terminator.</param>
    /// <returns>The normalized token string; '' for a blank or comment-only line.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Lint.ReviewMarker.TReviewMarkers.HashLine (DRagLint.Lint.ReviewMarker.pas), DRagLint.Lint.ReviewMarker.TReviewMarkers.HashWindow (DRagLint.Lint.ReviewMarker.pas)</para>
    /// <para>Calls: CharInSet, LowerCase</para>
    /// <para>Returns: SB.ToString</para>
    /// <para>Complexity: 34 (cyclomatic, outer body), 115 lines (full implementation)</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.FormatMarker"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.HashLine"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.HashWindow"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.InsertInto"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.LineCommentStart"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function NormalizeLine(const ALineText: string): string; static;
    /// <summary>4 lowercase hex characters over <see cref="NormalizeLine"/>.</summary>
    /// <param name="ALineText">One source line, without its line terminator.</param>
    /// <returns>Exactly 4 chars from [0-9a-f].</returns>
    /// <remarks>
    /// A staleness detector, not a security primitive: a collision keeps
    /// one changed line suppressed, which is the same failure mode as carrying no
    /// hash at all, and more characters buy only line noise.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Lint.ReviewMarker.TReviewMarkers.FormatMarker (DRagLint.Lint.ReviewMarker.pas), DRagLint.Lint.ReviewMarker.TReviewMarkers.HashWindow (DRagLint.Lint.ReviewMarker.pas), DRagLint.Lint.ReviewMarker.TReviewMarkers.InsertInto (DRagLint.Lint.ReviewMarker.pas)</para>
    /// <para>Calls: Copy, DRagLint.Lint.ReviewMarker.TReviewMarkers.NormalizeLine, LowerCase</para>
    /// <para>Returns: LowerCase(Copy(THashSHA2.GetHashString(NormalizeLine(ALineText)), 1, 4))</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.NormalizeLine"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.FormatMarker"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.HashWindow"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.InsertInto"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.LineCommentStart"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function HashLine(const ALineText: string): string; static;
    /// <summary>4 hex chars over a WINDOW of normalized lines starting at
    /// AStartIdx (0-based), rather than over one line.</summary>
    /// <param name="ALines">The whole file, as lines.</param>
    /// <param name="AStartIdx">0-based index of the anchor line.</param>
    /// <param name="AMaxLines">Hard cap on normalized lines consumed.</param>
    /// <returns>The 4-char hash, or HashLine's value when the window degenerates
    /// to a single line.</returns>
    /// <remarks>
    /// WHY THIS EXISTS. HashLine pins a marker to ONE line, which works only
    /// while that line carries content that can change. After bare-except moved
    /// its anchor to the `except` KEYWORD, every marker in every project hashed
    /// the single token `except` and came out identical (`@b112` x12 across two
    /// repos, where the same twelve previously held eight distinct hashes). A
    /// hash that cannot vary cannot go stale, so the marker verified forever no
    /// matter how the handler was rewritten -- the accountability property was
    /// gone while every count looked better.
    /// The window is bounded and stops after a line normalizing to `end`, so it
    /// covers the construct the reviewer actually accepted, not the file.
    /// KNOWN OVER-SENSITIVITY, ACCEPTED DELIBERATELY: NormalizeLine is a
    /// per-line function and cannot see that a `{` opened on an earlier line, so
    /// prose inside a multi-line comment within the window counts as content.
    /// That makes the hash change when a comment changes. It is the SAFE
    /// direction: the error can only make a marker go stale (loud, and the fix
    /// is to re-approve), never make one verify wrongly (silent). Threading
    /// block state here would mean a second implementation of what
    /// MarkerBearingLines already does; do that only if the noise is observed.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.ApplyLineMarkers (DRagLint.CLI.pas), DRagLint.CLI.DoAllow (DRagLint.CLI.pas)</para>
    /// <para>Calls: Copy, DRagLint.Lint.ReviewMarker.NormalizedIsLoneKeyword, DRagLint.Lint.ReviewMarker.TReviewMarkers.HashLine, DRagLint.Lint.ReviewMarker.TReviewMarkers.NormalizeLine, LowerCase</para>
    /// <para>Returns: HashLine(ALines[AStartIdx]); LowerCase(Copy(THashSHA2.GetHashString(SB.ToString), 1, 4))</para>
    /// <para>Complexity: 10 (cyclomatic, outer body), 60 lines (full implementation)</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.NormalizedIsLoneKeyword"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.HashLine"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.NormalizeLine"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.FormatMarker"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.InsertInto"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function HashWindow(const ALines: TArray<string>; AStartIdx: Integer;
      AMaxLines: Integer = 6): string; static;
    /// <summary>Every `dl:ok` entry on the line, in written order.</summary>
    /// <param name="ALineText">One source line, without its line terminator.</param>
    /// <returns>[] when the line carries no marker. A `dl:ok` occurring inside a
    /// string literal is NOT a marker.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.ApplyLineMarkers (DRagLint.CLI.pas), DRagLint.CLI.DoAllow (DRagLint.CLI.pas), DRagLint.Lint.ReviewMarker.TReviewMarkers.InsertInto (DRagLint.Lint.ReviewMarker.pas)</para>
    /// <para>Calls: Copy, Default, DRagLint.Lint.ReviewMarker.TReviewMarkers.LineCommentStart, DRagLint.Lint.ReviewMarker.TReviewMarkers.SplitReason, LowerCase, Pos, Trim</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.LineCommentStart"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.SplitReason"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.FormatMarker"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.HashLine"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.HashWindow"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Parse(const ALineText: string): TArray<TReviewMarker>; static;
    /// <summary>The marker body (without the leading `//`) recording ARuleId as
    /// reviewed on ALineText.</summary>
    /// <param name="ARuleId">Rule id being accepted.</param>
    /// <param name="ALineText">The line the marker will live on; hashed.</param>
    /// <param name="AReason">Optional free text; omitted from the result when ''.</param>
    /// <returns>e.g. `dl:ok bare-except@7f3a -- rethrown by the caller`.</returns>
    /// <remarks>
    /// THE single place a marker is ever formatted. The LSP code action
    /// and the Delphi IDE plugin panel must both come through here rather than
    /// building the text a second time.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Calls: DRagLint.Lint.ReviewMarker.TReviewMarkers.HashLine, DRagLint.Lint.ReviewMarker.TReviewMarkers.RuleToken, Trim</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.HashLine"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.RuleToken"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.HashWindow"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.InsertInto"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.LineCommentStart"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function FormatMarker(const ARuleId, ALineText, AReason: string): string; static;
    /// <summary>ALineText with ARuleId recorded as reviewed: merged into the
    /// existing `dl:ok` comment when the line already has one, otherwise appended
    /// as a new end-of-line comment.</summary>
    /// <param name="ALineText">One source line, without its line terminator.</param>
    /// <param name="ARuleId">Rule id being accepted.</param>
    /// <param name="AReason">Optional free text. An existing reason is preserved.</param>
    /// <param name="AHashOverride"><!-- drag-lint:auto type -->const string = ''</param>
    /// <returns>The whole new line: 7-bit ASCII, no trailing whitespace, original
    /// indentation and code untouched.</returns>
    /// <remarks>
    /// Idempotent only when the review is still valid: a rule already
    /// recorded with a hash matching the current line returns ALineText
    /// byte-identical. A rule recorded with a STALE hash -- or with none at all --
    /// has that one entry re-hashed to the line as it now stands, which is how a
    /// human re-accepts a review after the code moved on. Neighbouring markers
    /// keep their own hashes, stale ones included: re-validating a review of code
    /// nobody re-examined is the failure this design exists to prevent. The marker
    /// is a comment, so the hash it stores is unaffected by its own
    /// insertion.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoAllow (DRagLint.CLI.pas)</para>
    /// <para>Calls: Copy, DRagLint.Lint.ReviewMarker.TReviewMarkers.HashLine, DRagLint.Lint.ReviewMarker.TReviewMarkers.LineCommentStart, DRagLint.Lint.ReviewMarker.TReviewMarkers.Parse, DRagLint.Lint.ReviewMarker.TReviewMarkers.RuleToken, LowerCase, Pos, SameText, Trim, TrimRight</para>
    /// <para>Returns: TrimRight(Result); TrimRight(Prefix + Body)</para>
    /// <para>Complexity: 13 (cyclomatic, outer body), 77 lines (full implementation)</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.HashLine"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.LineCommentStart"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.Parse"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.RuleToken"/>
    /// <seealso cref="DRagLint.Lint.ReviewMarker.TReviewMarkers.FormatMarker"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    /// <summary>ALineText with the `dl:ok` entry for ARuleId removed. The
    /// inverse of InsertInto, for superseding a review rather than adding a
    /// second one beside it.</summary>
    /// <param name="ALineText">One source line, without its line terminator.</param>
    /// <param name="ARuleId">Rule id whose entry is removed; matched case-insensitively.</param>
    /// <returns>The rewritten line. ALineText UNCHANGED when the line carries no
    /// marker for ARuleId -- an unchanged result is how the caller learns this
    /// was a no-op.</returns>
    /// <remarks>Every surviving entry is re-emitted verbatim, hash included, so
    /// removing one review can neither validate nor invalidate another. When the
    /// last entry goes the `dl:ok` comment goes too, and the `//` with it if that
    /// comment held nothing else. Pure.</remarks>
    class function RemoveFrom(const ALineText, ARuleId: string): string; static;
    class function InsertInto(const ALineText, ARuleId, AReason: string;
      const AHashOverride: string = ''): string; static;
  end;

const
  /// <summary>The marker tag. Short, greppable, 7-bit ASCII.</summary>
  REVIEW_MARK = 'dl:ok';
  /// <summary>Separator between the rule list and the free-text reason.</summary>
  REVIEW_REASON_SEP = '--';
  /// <summary>The shared-unit marker tag. Same family as dl:ok.</summary>
  SHARED_MARK = 'dl:shared';

implementation

{ ---------------------------------------------------------------------------
  Normalisation
  --------------------------------------------------------------------------- }

class function TReviewMarkers.NormalizeLine(const ALineText: string): string;
var
  SB  : TStringBuilder;
  I   : Integer       ;
  Len : Integer       ;
  C   : Char          ;
begin
  SB:= TStringBuilder.Create(Length(ALineText));
  try
    I  := 1;
    Len:= Length(ALineText);
    while I <= Len do
    begin
      C:= ALineText[I];

      { String literal: content is preserved VERBATIM, including case. Delphi
        identifiers are case-insensitive but literal content is not, so
        lowercasing here would let 'Abc' and 'abc' share a hash. }
      if C = '''' then
      begin
        SB.Append(C);
        Inc(I);
        while I <= Len do
        begin
          SB.Append(ALineText[I]);
          if ALineText[I] = '''' then
          begin
            { A doubled quote is an escaped quote, not the end of the literal. }
            if (I < Len) and (ALineText[I + 1] = '''') then
            begin
              SB.Append('''');
              Inc(I, 2);
              Continue;
            end;
            Inc(I);
            Break;
          end;
          Inc(I);
        end;
        Continue;
      end;

      { Line comment: everything to end of line is excluded. This is what makes
        the marker able to describe the line it sits on. }
      if (C = '/') and (I < Len) and (ALineText[I + 1] = '/') then Break;

      { Brace form: a directive is code, a comment is not. }
      if C = '{' then
      begin
        if (I < Len) and (ALineText[I + 1] = '$') then
        begin
          while (I <= Len) and (ALineText[I] <> '}') do
          begin
            if not CharInSet(ALineText[I], [' ', #9]) then SB.Append(LowerCase(ALineText[I]));
            Inc(I);
          end;
          if I <= Len then SB.Append('}');
          Inc(I);
        end
        else
        begin
          while (I <= Len) and (ALineText[I] <> '}') do Inc(I);
          Inc(I);
        end;
        Continue;
      end;

      { Parenthesised form, same split. }
      if (C = '(') and (I < Len) and (ALineText[I + 1] = '*') then
      begin
        if (I + 2 <= Len) and (ALineText[I + 2] = '$') then
        begin
          while I <= Len do
          begin
            if (ALineText[I] = '*') and (I < Len) and (ALineText[I + 1] = ')') then
            begin
              SB.Append('*)');
              Inc(I, 2);
              Break;
            end;
            if not CharInSet(ALineText[I], [' ', #9]) then SB.Append(LowerCase(ALineText[I]));
            Inc(I);
          end;
        end
        else
        begin
          Inc(I, 2);
          while I <= Len do
          begin
            if (ALineText[I] = '*') and (I < Len) and (ALineText[I + 1] = ')') then
            begin
              Inc(I, 2);
              Break;
            end;
            Inc(I);
          end;
        end;
        Continue;
      end;

      { Whitespace dropped, so reindentation and interior alignment do not
        invalidate a review -- YADF changes both by design. }
      if CharInSet(C, [' ', #9]) then
      begin
        Inc(I);
        Continue;
      end;

      SB.Append(LowerCase(C));
      Inc(I);
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TReviewMarkers.HashLine(const ALineText: string): string;
begin
  Result:= LowerCase(Copy(THashSHA2.GetHashString(NormalizeLine(ALineText)), 1, 4));
end;

{ True when the normalized line is a single Delphi keyword (optionally with a
  trailing ';'). Such a line is identical in every file that contains it, so a
  hash over it alone can never go stale. NormalizeLine has already stripped
  comments and whitespace and lowercased, so this is a plain set test. }
function NormalizedIsLoneKeyword(const ANorm: string): Boolean;
const
  LONE: array[0..10] of string = (
    'except', 'finally', 'try', 'begin', 'end', 'else', 'do', 'then',
    'repeat', 'of', 'asm');
var
  S: string;
  K: string;
begin
  S:= ANorm;
  if (S <> '') and (S[Length(S)] = ';') then S:= Copy(S, 1, Length(S) - 1);
  for K in LONE do
    if S = K then Exit(True);
  Result:= False;
end;

class function TReviewMarkers.HashWindow(const ALines: TArray<string>;
  AStartIdx: Integer; AMaxLines: Integer): string;
var
  SB   : TStringBuilder;
  I    : Integer       ;
  Taken: Integer       ;
  N    : string        ;
begin
  if (AStartIdx < 0) or (AStartIdx > High(ALines)) then Exit(HashLine(''));

  { WIDEN ONLY WHERE THE LINE CANNOT CARRY A HASH -- i.e. when the anchor
    normalizes to a LONE KEYWORD.

    The first cut of this widened unconditionally, and that is a corpus-wide
    churn event, not a fix: every marker for every rule in every project changes
    hash at once. Measured on the four consumer projects -- review-marker-stale
    went 0/0/0/0 -> 102/128/114/49 and the totals 6/6/9/44 -> 232/299/263/152,
    because ~390 markers anchored on ordinary STATEMENTS were invalidated to
    repair twelve anchored on a keyword.

    A statement line already varies with the code, so HashLine is exactly right
    for it and must keep returning the same value it always has. Only an anchor
    like `except` -- one invariant token, the same in every file forever -- needs
    the construct behind it to make the hash mean anything.

    So the widening is CONDITIONAL and the condition is a property of the line,
    not a list of rule ids: any rule that anchors on a bare keyword gets this
    automatically, including the sibling keyword-anchored rules (empty-except,
    empty-finally, empty-on-handler, empty-conditional, empty-loop-body,
    empty-case-branch), and no rule that anchors on real code is disturbed. }
  if not NormalizedIsLoneKeyword(NormalizeLine(ALines[AStartIdx])) then
    Exit(HashLine(ALines[AStartIdx]));

  SB:= TStringBuilder.Create;
  try
    Taken:= 0;
    I    := AStartIdx;
    while (I <= High(ALines)) and (Taken < AMaxLines) do
    begin
      N:= NormalizeLine(ALines[I]);
      { Blank and comment-only lines contribute nothing. Skipping them rather
        than counting them keeps the window anchored to CODE, so reformatting or
        commenting inside the handler does not shrink what is covered. }
      if N <> '' then
      begin
        SB.Append(N);
        SB.Append(#10);
        Inc(Taken);
        { Stop AFTER the construct's terminator, never before it: `end` is part
          of what was reviewed. Guarded on Taken > 1 so an anchor line that is
          itself an `end` cannot terminate the window at once and collapse this
          back to a single-line hash -- which is the exact failure being fixed. }
        if (Taken > 1) and ((N = 'end') or (N = 'end;')) then Break;
      end;
      Inc(I);
    end;
    Result:= LowerCase(Copy(THashSHA2.GetHashString(SB.ToString), 1, 4));
  finally
    SB.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Parsing
  --------------------------------------------------------------------------- }

class function TReviewMarkers.MarkerBearingLines(const ALines: TArray<string>): TArray<Boolean>;
var
  LI, I, Len : Integer;
  { Named in prose, not shown: a closing brace inside a braced comment ends it
    early. That is the same trap DRagLint.Lint.SharedUnit's header records
    paying for, and writing these two comments the obvious way cost a build
    here too. }
  InBrace    : Boolean; { brace comment     -- spans lines }
  InParen    : Boolean; { star-paren comment -- spans lines }
  Line       : string ;
  CanBear    : Boolean;
begin
  SetLength(Result, Length(ALines));
  { Block-comment state is the whole point: it is carried ACROSS lines. String
    and `//` state are not -- neither can span a line in Object Pascal -- so both
    are re-initialised per line below. }
  InBrace:= False;
  InParen:= False;
  for LI:= 0 to High(ALines) do
  begin
    Line   := ALines[LI];
    Len    := Length(Line);
    CanBear:= False;
    I      := 1;
    while I <= Len do
    begin
      if InBrace then
      begin
        if Line[I] = '}' then InBrace:= False;
        Inc(I);
        Continue;
      end;
      if InParen then
      begin
        if (Line[I] = '*') and (I < Len) and (Line[I + 1] = ')') then
        begin
          InParen:= False;
          Inc(I, 2);
          Continue;
        end;
        Inc(I);
        Continue;
      end;
      { A string literal, so a `//` or `{` inside one opens nothing. A doubled
        quote just re-opens the literal on the next pass -- same net state. }
      if Line[I] = '''' then
      begin
        Inc(I);
        while I <= Len do
        begin
          if Line[I] = '''' then begin Inc(I); Break; end;
          Inc(I);
        end;
        Continue;
      end;
      if Line[I] = '{' then begin InBrace:= True; Inc(I); Continue; end;
      if (Line[I] = '(') and (I < Len) and (Line[I + 1] = '*') then
      begin
        InParen:= True;
        Inc(I, 2);
        Continue;
      end;
      if (Line[I] = '/') and (I < Len) and (Line[I + 1] = '/') then
      begin
        { `///` is a DocInsight doc comment -- prose, and the home of the quoted
          grammar example that produced one of the two false positives. A `//`
          reached here is in code state and can carry a real marker. Either way
          the rest of the line is comment, so block state cannot change again and
          the line is done. }
        CanBear:= not ((I + 2 <= Len) and (Line[I + 2] = '/'));
        Break;
      end;
      Inc(I);
    end; // while
    Result[LI]:= CanBear;
  end; // for
end;

class function TReviewMarkers.LineCommentStart(const ALineText: string): Integer;
var
  I  : Integer;
  Len: Integer;
begin
  Result:= 0;
  I  := 1;
  Len:= Length(ALineText);
  while I <= Len do
  begin
    { Skip string literals -- a '//' inside one opens no comment, which is
      exactly the case a bare Pos() gets wrong. }
    if ALineText[I] = '''' then
    begin
      Inc(I);
      while I <= Len do
      begin
        if ALineText[I] = '''' then
        begin
          if (I < Len) and (ALineText[I + 1] = '''') then begin Inc(I, 2); Continue; end;
          Inc(I);
          Break;
        end;
        Inc(I);
      end;
      Continue;
    end;
    if (ALineText[I] = '/') and (I < Len) and (ALineText[I + 1] = '/') then Exit(I + 2);
    { A '//' inside a block comment opens nothing either. }
    if ALineText[I] = '{' then
    begin
      while (I <= Len) and (ALineText[I] <> '}') do Inc(I);
      Inc(I);
      Continue;
    end;
    if (ALineText[I] = '(') and (I < Len) and (ALineText[I + 1] = '*') then
    begin
      Inc(I, 2);
      while I <= Len do
      begin
        if (ALineText[I] = '*') and (I < Len) and (ALineText[I + 1] = ')') then begin Inc(I, 2); Break; end;
        Inc(I);
      end;
      Continue;
    end;
    Inc(I);
  end;
end;

class procedure TReviewMarkers.SplitReason(const AText: string; out ARules, AReason: string);
var
  I       : Integer;
  DashPos : Integer;
  ColonPos: Integer;
begin
  ARules := AText;
  AReason:= '';

  DashPos:= 0;
  for I:= 1 to Length(AText) - 1 do
    if (AText[I] = '-') and (AText[I + 1] = '-') and
       ((I = 1) or CharInSet(AText[I - 1], [' ', #9])) then
    begin
      { Preceded by whitespace, so a hyphenated rule id such as 'bare-except'
        cannot be mistaken for the separator. }
      DashPos:= I;
      Break;
    end;

  { A colon separates the rules from the prose too. Nothing to the LEFT of a
    separator can legally contain one -- rule ids and the 4-hex @hash are both
    colon-free -- so the first colon is unambiguous.

    This form is accepted because people write it and it used to fail SILENTLY:
    the whole tail became the rule list, the named rule did not exist, and the
    marker suppressed nothing while reading as a review. DataCopy hit it on 11
    sites. See the review-marker-malformed block in DRagLint.CLI. }
  ColonPos:= Pos(':', AText);

  { WHICHEVER SEPARATOR COMES FIRST WINS, so the other one is ordinary prose:
    `-- see note: it is rethrown` keeps its colon, and `: rethrown -- by the
    caller` keeps its dashes. }
  if (ColonPos > 0) and ((DashPos = 0) or (ColonPos < DashPos)) then
  begin
    ARules := Copy(AText, 1, ColonPos - 1);
    AReason:= Trim(Copy(AText, ColonPos + 1, MaxInt));
  end
  else if DashPos > 0 then
  begin
    ARules := Copy(AText, 1, DashPos - 1);
    AReason:= Trim(Copy(AText, DashPos + 2, MaxInt));
  end;
end;

class function TReviewMarkers.Parse(const ALineText: string): TArray<TReviewMarker>;
var
  CStart : Integer         ;
  Comment: string          ;
  TagPos : Integer         ;
  Rest   : string          ;
  Rules  : string          ;
  Reason : string          ;
  Part   : string          ;
  AtPos  : Integer         ;
  M      : TReviewMarker   ;
begin
  Result:= nil;
  CStart:= LineCommentStart(ALineText);
  if CStart = 0 then Exit;

  Comment:= Copy(ALineText, CStart, MaxInt);
  TagPos := Pos(REVIEW_MARK, LowerCase(Comment));
  if TagPos = 0 then Exit;

  Rest:= Copy(Comment, TagPos + Length(REVIEW_MARK), MaxInt);
  SplitReason(Rest, Rules, Reason);

  for Part in Rules.Split([',']) do
  begin
    M:= Default(TReviewMarker);
    M.Reason:= Reason;
    AtPos:= Pos('@', Part);
    if AtPos > 0 then
    begin
      M.RuleId:= Trim(Copy(Part, 1, AtPos - 1));
      M.Hash  := LowerCase(Trim(Copy(Part, AtPos + 1, MaxInt)));
    end
    else
      M.RuleId:= Trim(Part);
    if M.RuleId <> '' then Result:= Result + [M];
  end;
end;

{ ---------------------------------------------------------------------------
  Insertion
  --------------------------------------------------------------------------- }

class function TReviewMarkers.RuleToken(const ARuleId, AHash: string): string;
begin
  if AHash = '' then Result:= ARuleId else Result:= ARuleId + '@' + AHash;
end;

class function TReviewMarkers.FormatMarker(const ARuleId, ALineText, AReason: string): string;
begin
  Result:= REVIEW_MARK + ' ' + RuleToken(ARuleId, HashLine(ALineText));
  if Trim(AReason) <> '' then Result:= Result + ' ' + REVIEW_REASON_SEP + ' ' + Trim(AReason);
end;

class function TReviewMarkers.InsertInto(const ALineText, ARuleId, AReason: string;
  const AHashOverride: string): string;
var
  Existing: TArray<TReviewMarker>;
  M       : TReviewMarker        ;
  Hash    : string               ;
  Reason  : string               ;
  Body    : string               ;
  Comment : string               ;
  CStart  : Integer              ;
  TagPos  : Integer              ;
  Prefix  : string               ;
  Head    : string               ;
  Refreshed: Boolean             ;
begin
  { The WRITER and the CHECKER must agree on the hash input or every marker is
    born stale. The checker hashes a window (see HashWindow); it passes that
    value here rather than letting this function re-derive a single-line hash it
    has no way to reproduce -- InsertInto only ever receives one line. }
  if AHashOverride <> '' then Hash:= AHashOverride
  else Hash:= HashLine(ALineText);
  Existing:= Parse(ALineText);

  { Idempotent: a rule this line already records AND whose hash still matches the
    code is not recorded twice, and the line comes back byte-identical so an
    Allow on an already-clean finding cannot dirty an editor buffer.

    Matching on the rule id ALONE would be wrong. A stale marker re-reports its
    finding by design, and the way a human clears that is to allow it again --
    the same action, not a separate one. Bailing out here would make that click
    a silent no-op. A hashless hand-written marker takes the same path and
    acquires a hash. }
  for M in Existing do
    if SameText(M.RuleId, ARuleId) and SameText(M.Hash, Hash) then Exit(ALineText);

  if Length(Existing) = 0 then
  begin
    Body:= REVIEW_MARK + ' ' + RuleToken(ARuleId, Hash);
    if Trim(AReason) <> '' then Body:= Body + ' ' + REVIEW_REASON_SEP + ' ' + Trim(AReason);
    Head:= TrimRight(ALineText);
    if Head = '' then Result:= '// ' + Body else Result:= Head + '  // ' + Body;
    Exit(TrimRight(Result));
  end;

  { Merge into the existing marker: rebuild its body from the entries already
    there plus the new one, so there is exactly one dl:ok comment on the line. An
    existing reason wins -- it was written by a human about this same code. }
  Reason:= Existing[0].Reason;
  if Trim(Reason) = '' then Reason:= Trim(AReason);

  Refreshed:= False;
  Body     := REVIEW_MARK + ' ';
  for var K: Integer:= 0 to High(Existing) do
  begin
    if K > 0 then Body:= Body + ', ';
    if SameText(Existing[K].RuleId, ARuleId) then
    begin
      { Re-accepting a review whose code moved on: THIS entry is re-hashed to the
        line as it now stands. Every neighbour keeps its own hash verbatim --
        including a stale one. Refreshing the whole line would silently
        re-validate a review of code nobody re-examined, which is the single
        failure this design exists to prevent. Second finding, second click. }
      Body     := Body + RuleToken(ARuleId, Hash);
      Refreshed:= True;
    end
    else
      Body:= Body + RuleToken(Existing[K].RuleId, Existing[K].Hash);
  end;
  if not Refreshed then Body:= Body + ', ' + RuleToken(ARuleId, Hash);
  if Trim(Reason) <> '' then Body:= Body + ' ' + REVIEW_REASON_SEP + ' ' + Trim(Reason);

  CStart := LineCommentStart(ALineText);
  Comment:= Copy(ALineText, CStart, MaxInt);
  TagPos := Pos(REVIEW_MARK, LowerCase(Comment));
  Prefix := Copy(ALineText, 1, CStart + TagPos - 2);

  Result:= TrimRight(Prefix + Body);
end;

class function TReviewMarkers.RemoveFrom(const ALineText, ARuleId: string): string;
{ The inverse of InsertInto, and deliberately its mirror image: same Parse, same
  rebuild loop, same Prefix arithmetic. A separate hand-rolled deletion would be
  a second place that has to know how a marker is spelled, which is the one
  property this unit exists to prevent.

  Only ARuleId's entry goes. Every neighbour is re-emitted VERBATIM, hash
  included -- deleting a superseded review must not silently re-validate, or
  invalidate, a review of code nobody re-examined.

  When the last entry goes, the `dl:ok` comment goes with it, and so does the
  `//` that opened it -- but ONLY when that comment held nothing else. A line
  reading `// see ticket 41 dl:ok foo` keeps `// see ticket 41`; a bare
  `// dl:ok foo` leaves the code alone with no dangling `//`. The reason text
  belongs to the marker, so it leaves with the last entry and is kept while any
  entry remains. }
var
  Existing: TArray<TReviewMarker>;
  Kept    : TArray<TReviewMarker>;
  Tokens  : TArray<string>       ;
  M       : TReviewMarker        ;
  Found   : Boolean              ;
  Body    : string               ;
  Comment : string               ;
  CStart  : Integer              ;
  TagPos  : Integer              ;
  Prefix  : string               ;
begin
  Result  := ALineText;
  Existing:= Parse(ALineText);
  if Length(Existing) = 0 then Exit;

  Found:= False;
  Kept := nil;
  for M in Existing do
    if SameText(M.RuleId, ARuleId) then Found:= True
    else Kept:= Kept + [M];
  { Nothing to remove is not an error, and must not rewrite the line: an
    unchanged line is how the caller learns this was a no-op. }
  if not Found then Exit;

  CStart := LineCommentStart(ALineText);
  Comment:= Copy(ALineText, CStart, MaxInt);
  TagPos := Pos(REVIEW_MARK, LowerCase(Comment));
  if (CStart = 0) or (TagPos = 0) then Exit;
  Prefix := Copy(ALineText, 1, CStart + TagPos - 2);

  if Length(Kept) = 0 then
  begin
    { Was there any other comment text before the tag? Prefix still carries the
      `//`, so measure what sits BETWEEN the opener and the tag. }
    if Trim(Copy(ALineText, CStart, TagPos - 1)) = '' then
      Result:= TrimRight(Copy(ALineText, 1, CStart - 3))  { drop the `//` too }
    else
      Result:= TrimRight(Prefix);
    Exit;
  end;

  { Joined rather than accumulated with `+` in the loop. InsertInto above builds
    its body the accumulating way and carries `concat-in-loop` for it; this is
    new code, so it is held to the whole rule set (the lint-clean standard),
    and string.Join is what that rule's own message recommends. }
  SetLength(Tokens, Length(Kept));
  for var K: Integer:= 0 to High(Kept) do
    Tokens[K]:= RuleToken(Kept[K].RuleId, Kept[K].Hash);
  Body:= REVIEW_MARK + ' ' + string.Join(', ', Tokens);
  if Trim(Kept[0].Reason) <> '' then
    Body:= Body + ' ' + REVIEW_REASON_SEP + ' ' + Trim(Kept[0].Reason);

  Result:= TrimRight(Prefix + Body);
end;

end.
