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
  /// <remarks>Thread-safe: no shared state.</remarks>
  TReviewMarkers = class
  strict private
    /// <summary>1-based index just past the `//` that opens the line comment,
    /// skipping any `//` that occurs inside a string literal or a block
    /// comment; 0 when the line carries no line comment.</summary>
    class function LineCommentStart(const ALineText: string): Integer; static;
    /// <summary>Splits the text following the `dl:ok` tag into the comma-separated
    /// rule list and the free-text reason, on the first `--` that follows
    /// whitespace.</summary>
    class procedure SplitReason(const AText: string; out ARules, AReason: string); static;
    /// <summary>Renders `&lt;rule&gt;@&lt;hash&gt;`, or just `&lt;rule&gt;` when
    /// AHash is ''.</summary>
    class function RuleToken(const ARuleId, AHash: string): string; static;
  public
    /// <summary>The line reduced to its code tokens: comments removed,
    /// whitespace dropped, identifiers lowercased, string-literal content kept
    /// verbatim and case-sensitive. Compiler directives (`{$...}`, `(*$...*)`)
    /// count as CODE, not comment -- `{$IFDEF A}` and `{$IFDEF B}` are different
    /// programs and must not share a hash.</summary>
    /// <param name="ALineText">One source line, without its line terminator.</param>
    /// <returns>The normalized token string; '' for a blank or comment-only line.</returns>
    class function NormalizeLine(const ALineText: string): string; static;
    /// <summary>4 lowercase hex characters over <see cref="NormalizeLine"/>.</summary>
    /// <param name="ALineText">One source line, without its line terminator.</param>
    /// <returns>Exactly 4 chars from [0-9a-f].</returns>
    /// <remarks>A staleness detector, not a security primitive: a collision keeps
    /// one changed line suppressed, which is the same failure mode as carrying no
    /// hash at all, and more characters buy only line noise.</remarks>
    class function HashLine(const ALineText: string): string; static;
    /// <summary>Every `dl:ok` entry on the line, in written order.</summary>
    /// <param name="ALineText">One source line, without its line terminator.</param>
    /// <returns>[] when the line carries no marker. A `dl:ok` occurring inside a
    /// string literal is NOT a marker.</returns>
    class function Parse(const ALineText: string): TArray<TReviewMarker>; static;
    /// <summary>The marker body (without the leading `//`) recording ARuleId as
    /// reviewed on ALineText.</summary>
    /// <param name="ARuleId">Rule id being accepted.</param>
    /// <param name="ALineText">The line the marker will live on; hashed.</param>
    /// <param name="AReason">Optional free text; omitted from the result when ''.</param>
    /// <returns>e.g. `dl:ok bare-except@7f3a -- rethrown by the caller`.</returns>
    /// <remarks>THE single place a marker is ever formatted. The LSP code action
    /// and the Delphi IDE plugin panel must both come through here rather than
    /// building the text a second time.</remarks>
    class function FormatMarker(const ARuleId, ALineText, AReason: string): string; static;
    /// <summary>ALineText with ARuleId recorded as reviewed: merged into the
    /// existing `dl:ok` comment when the line already has one, otherwise appended
    /// as a new end-of-line comment.</summary>
    /// <param name="ALineText">One source line, without its line terminator.</param>
    /// <param name="ARuleId">Rule id being accepted.</param>
    /// <param name="AReason">Optional free text. An existing reason is preserved.</param>
    /// <returns>The whole new line: 7-bit ASCII, no trailing whitespace, original
    /// indentation and code untouched.</returns>
    /// <remarks>Idempotent only when the review is still valid: a rule already
    /// recorded with a hash matching the current line returns ALineText
    /// byte-identical. A rule recorded with a STALE hash -- or with none at all --
    /// has that one entry re-hashed to the line as it now stands, which is how a
    /// human re-accepts a review after the code moved on. Neighbouring markers
    /// keep their own hashes, stale ones included: re-validating a review of code
    /// nobody re-examined is the failure this design exists to prevent. The marker
    /// is a comment, so the hash it stores is unaffected by its own
    /// insertion.</remarks>
    class function InsertInto(const ALineText, ARuleId, AReason: string): string; static;
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

{ ---------------------------------------------------------------------------
  Parsing
  --------------------------------------------------------------------------- }

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
  I: Integer;
begin
  ARules := AText;
  AReason:= '';
  for I:= 1 to Length(AText) - 1 do
    if (AText[I] = '-') and (AText[I + 1] = '-') and
       ((I = 1) or CharInSet(AText[I - 1], [' ', #9])) then
    begin
      { Preceded by whitespace, so a hyphenated rule id such as 'bare-except'
        cannot be mistaken for the separator. }
      ARules := Copy(AText, 1, I - 1);
      AReason:= Trim(Copy(AText, I + 2, MaxInt));
      Exit;
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

class function TReviewMarkers.InsertInto(const ALineText, ARuleId, AReason: string): string;
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
  Hash    := HashLine(ALineText);
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

end.
