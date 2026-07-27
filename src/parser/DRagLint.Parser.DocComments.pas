unit DRagLint.Parser.DocComments;

interface

uses
  System.SysUtils
  , System.Classes
  , System  .Generics.Collections
  , DRagLint.Core    .Model
  ;

type
  TDocCommentScanner = class
    public
      /// <summary>Walk the source, return all comment regions sorted by StartLine.</summary>
      class function Scan(const ASource: string): TList<TDocCommentRegion>;
  end;

  TDocCommentParser = class
    public
      class function ParseXmlDoc(const ARaw: string)                         : TParsedDoc; static;
      class function ParsePasDoc(const ARaw: string)                         : TParsedDoc; static;
      class function ParseOneline(const ARaw: string; AKind: TDocCommentKind): TParsedDoc; static;
      class function ParseLoose(const ARaw: string)                          : TParsedDoc; static;

      class function StripXmlDocPrefix(const ALine: string): string; static;
      class function CollapseWhitespace(const S: string)   : string; static;

      class function Dispatch(const ARegion: TDocCommentRegion): TParsedDoc; static;
  end;

implementation

uses
  System.RegularExpressions
  , System.StrUtils
  ;

var
  // v(ADP3 T3b review round 2, NEW IMPORTANT): Dispatch's HasXmlTags sniff for
  // <since>/<see>/<seealso>/<deprecated> used to re-derive its OWN informal
  // Pos()-based approximation of what RxSee/RxSinceTag/RxDeprecatedTag/
  // RxDeprecatedBare (declared fresh, per-call, inside ParseXmlDoc below)
  // actually match -- the two drifted apart on shapes neither hand-written
  // check anticipated (a stray space before a tag's closing '>', a tab
  // instead of a space before an attribute, ALL-CAPS '<DEPRECATED>' since
  // Pos() is case-sensitive but every one of these regexes carries
  // roIgnoreCase). The fix is to sniff with the ACTUAL regexes the parser
  // matches against (IsMatch), not a parallel hand-maintained approximation,
  // so the two literally cannot drift apart again. These four are file-scope
  // (not local to Dispatch, not a class var -- TRegEx needs no interface
  // exposure for that) and built ONCE, lazily, on first use: Dispatch runs
  // once per doc comment scanned, so constructing four TRegEx objects on
  // EVERY call (the naive fix) would add real, measured cost to indexing;
  // see the task report for the whole-unit timing this was checked against.
  // Not thread-guarded: TDocCommentScanner/TDocCommentParser are only ever
  // driven from a single-threaded per-file scan in this codebase
  // (DRagLint.Core.Indexer.pas has no TParallel/TThread around doc parsing
  // at the time of writing) -- if that ever changes, this cache needs a
  // guard too.
  SniffRegexesReady  : Boolean = False;
  SniffSee           : TRegEx;
  SniffSinceTag      : TRegEx;
  SniffDeprecatedTag : TRegEx;
  SniffDeprecatedBare: TRegEx;

procedure EnsureSniffRegexes;
begin
  if SniffRegexesReady then Exit;
  // Pattern strings copied VERBATIM from ParseXmlDoc's own RxSee/RxSinceTag/
  // RxDeprecatedTag/RxDeprecatedBare locals further down this file -- if
  // those ever change, these must change with them, which is exactly the
  // class of drift this fix closes. Duplicated as literal strings (rather
  // than sharing the compiled TRegEx objects themselves across two call
  // sites with very different lifetimes -- a per-call local in ParseXmlDoc
  // vs. this file-scope cache) keeps the change small and mechanical.
  SniffSee           := TRegEx.Create('<(?:see|seealso)\s+cref="([^"]+)"\s*/?>'           , [roIgnoreCase]);
  SniffSinceTag      := TRegEx.Create('<since>([\s\S]*?)</since>'                         , [roIgnoreCase]);
  SniffDeprecatedTag := TRegEx.Create('<deprecated>([\s\S]*?)</deprecated>'               , [roIgnoreCase]);
  SniffDeprecatedBare:= TRegEx.Create('<deprecated\s*/>'                                  , [roIgnoreCase]);
  SniffRegexesReady:= True;
end;

function HasAnyRecognizedTag(const ADoc: TParsedDoc): Boolean;
begin
  // v(ADP3 T3b review round 2, NEW IMPORTANT): the general form of "did
  // ParseXmlDoc actually recognize ANY tag at all" -- deliberately NOT
  // ADoc.HasContent, which is its own, separately-documented and
  // DELIBERATELY narrow OR-chain for a different purpose (see HasContent's
  // own comment in ParseXmlDoc) and does not cover HasExampleTag/SeeAlso/
  // SinceText. Remarks <> '' is included here even though there is no
  // HasRemarksTag presence flag to distinguish "tag absent" from "tag
  // present but empty" the way HasSummaryTag/HasReturnsTag/HasExampleTag do
  // for their own tags -- treating a same-named literal accident as
  // "recognized" is the conservative direction (never causes a deletion; at
  // worst skips a redundant ParseOneline fallback for an already-degenerate
  // input).
  Result:=
    ADoc.HasSummaryTag or ADoc.HasReturnsTag or ADoc.HasExampleTag or ADoc.Deprecated or
    (Length(ADoc.Params) > 0) or (Length(ADoc.Exceptions) > 0) or (Length(ADoc.SeeAlso) > 0) or
    (ADoc.SinceText <> '') or (ADoc.Remarks <> '');
end;

type
  TScanState = (ssCode, ssInString, ssInLineComment, ssInBraceComment, ssInParenComment);

  class function TDocCommentScanner.Scan(const ASource: string): TList<TDocCommentRegion>;
var
  I        : Integer        ;
  Len      : Integer        ;
  Line     : Integer        ;
  Col      : Integer        ;
  State    : TScanState     ;
  StartLine: Integer        ;
  StartCol : Integer        ;
  Buf      : TStringBuilder ;
  Kind     : TDocCommentKind;

  procedure StartLineComment(AKind: TDocCommentKind);
  begin
    State    := ssInLineComment;
    StartLine:= Line;
    StartCol := Col;
    Kind     := AKind;
    Buf.Clear;
  end;

  procedure Emit;
  var
    Region: TDocCommentRegion;
  begin
    Region.StartLine:= StartLine;
    Region.EndLine  := Line;
    Region.StartCol := StartCol;
    Region.Kind     := Kind;
    Region.RawText:= Buf.ToString;
    Result.Add(Region);
    Buf.Clear;
  end;

  function Peek(Ahead: Integer): Char;
  begin
    if I + Ahead - 1 <= Len then Result:= ASource[I + Ahead - 1]
    else Result:= #0;
  end;

  procedure MergeAdjacentSameKind;
  var
    J   : Integer          ;
    Prev: TDocCommentRegion;
  begin
    J:= 1;
    while J < Result.Count do
    begin
      Prev:= Result[J - 1];
      if (Result[J].Kind = Prev.Kind) and (Result[J].StartLine = Prev.EndLine + 1) and (Result[J].Kind in [dckTripleSlash, dckDoubleSlashOne, dckTripleSlashOne, dckLooseLine]) then
      begin
        Prev.EndLine:= Result[J].EndLine;
        Prev.RawText:= Prev.RawText + sLineBreak + Result[J].RawText;
        Result[J - 1]:= Prev;
        Result.Delete(J);
      end
      else Inc(J);
    end;
  end; // procedure

begin
  Result:= TList<TDocCommentRegion>.Create;
  Buf:= TStringBuilder.Create;
  try
    Len:= Length(ASource);
    I    := 1;
    Line := 1;
    Col  := 1;
    State:= ssCode;
    while I <= Len do
    begin
      case State of
        ssCode:
        begin
          if ASource[I] = '''' then State:= ssInString
          else if (ASource[I] = '/') and (Peek(2) = '/') then
          begin
            // /// or ///1 or //1 or //
            if Peek(3) = '/' then
            begin
              if Peek(4) = '1' then StartLineComment(dckTripleSlashOne)
              else StartLineComment(dckTripleSlash);
              Inc(I, 3); Inc(Col, 3);
              if Kind = dckTripleSlashOne then begin Inc(I); Inc(Col); end;
              Continue;
            end
            else if Peek(3) = '1' then
            begin
              StartLineComment(dckDoubleSlashOne);
              Inc(I, 3); Inc(Col, 3);
              Continue;
            end
            else
            begin
              StartLineComment(dckLooseLine);
              Inc(I, 2); Inc(Col, 2);
              Continue;
            end;
          end // if
          else if (ASource[I] = '{') and (Peek(2) = '*') and (Peek(3) = '*') then
          begin
            State:= ssInBraceComment;
            StartLine:= Line; StartCol:= Col;
            Kind:= dckPasDocCurly;
            Buf.Clear;
            Inc(I, 3); Inc(Col, 3);
            Continue;
          end
          else if (ASource[I] = '{') then
          begin
            State:= ssInBraceComment;
            StartLine:= Line; StartCol:= Col;
            Kind:= dckLooseBlock;
            Buf.Clear;
            Inc(I); Inc(Col);
            Continue;
          end
          else if (ASource[I] = '(') and (Peek(2) = '*') and (Peek(3) = '*') then
          begin
            State:= ssInParenComment;
            StartLine:= Line; StartCol:= Col;
            Kind:= dckPasDocParen;
            Buf.Clear;
            Inc(I, 3); Inc(Col, 3);
            Continue;
          end
          else if (ASource[I] = '(') and (Peek(2) = '*') then
          begin
            State:= ssInParenComment;
            StartLine:= Line; StartCol:= Col;
            Kind:= dckLooseBlock;
            Buf.Clear;
            Inc(I, 2); Inc(Col, 2);
            Continue;
          end;
        end; // case
        ssInString     : if ASource[I] = '''' then State:= ssCode;
        ssInLineComment: if (ASource[I] = #13) or (ASource[I] = #10) then
        begin
          Emit;
          State:= ssCode;
        end
        else Buf.Append(ASource[I]);
        ssInBraceComment: if ASource[I] = '}' then
        begin
          Emit;
          State:= ssCode;
        end
        else Buf.Append(ASource[I]);
        ssInParenComment: if (ASource[I] = '*') and (Peek(2) = ')') then
        begin
          Emit;
          State:= ssCode;
          Inc(I, 2); Inc(Col, 2);
          Continue;
        end
        else Buf.Append(ASource[I]);
      end; // case

      if ASource[I] = #10 then
      begin
        Inc(Line);
        Col:= 1;
      end
      else Inc(Col);
      Inc(I);
    end; // while

    // Flush a trailing line comment that hit EOF without newline.
    if State = ssInLineComment then Emit;

    MergeAdjacentSameKind;
  finally
    Buf.Free;
  end; // try
end; // begin

{ TDocCommentParser }

class function TDocCommentParser.StripXmlDocPrefix(const ALine: string): string;
var
  S: string;
begin
  S:= TrimLeft(ALine);
  if S.StartsWith('///1') then Result:= Copy(S, 5, MaxInt)
  else if S.StartsWith('//1') then Result:= Copy(S, 4, MaxInt)
  else if S.StartsWith('///') then Result:= Copy(S, 4, MaxInt)
  else if S.StartsWith('//' ) then Result:= Copy(S, 3, MaxInt)
  else Result:= S;
  if (Length(Result) > 0) and (Result[1] = ' ') then Result:= Copy(Result, 2, MaxInt);
end;

class function TDocCommentParser.CollapseWhitespace(const S: string): string;
var
  Re: TRegEx;
begin
  Re:= TRegEx.Create('[ \t]+');
  Result:= Re.Replace(Trim(S), ' ');
end;

class function TDocCommentParser.ParseXmlDoc(const ARaw: string): TParsedDoc;
var
  Lines          : TArray<string>      ;
  Cleaned        : string              ;
  M              : string              ;
  I              : Integer             ;
  RxSummary      : TRegEx              ;
  RxParam        : TRegEx              ;
  RxReturns      : TRegEx              ;
  RxRemarks      : TRegEx              ;
  RxException    : TRegEx              ;
  RxExample      : TRegEx              ;
  RxSee          : TRegEx              ;
  RxSinceTag     : TRegEx              ;
  RxDeprecatedTag: TRegEx              ;
  RxDeprecatedBare: TRegEx             ;
  Match          : TMatch              ;
  Matches        : TMatchCollection    ;
  Params         : TList<TDocParam>    ;
  Excs           : TList<TDocException>;
  SeeList        : TList<string>       ;
  Param          : TDocParam           ;
  Exc            : TDocException       ;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Format  := dfXmlDoc;
  Result.RawBlock:= ARaw;

  Lines:= ARaw.Split([sLineBreak, #10, #13]);
  Cleaned:= '';
  for I:= 0 to High(Lines) do
  begin
    if I > 0 then Cleaned:= Cleaned + #10;
    Cleaned:= Cleaned + StripXmlDocPrefix(Lines[I]);
  end;

  RxSummary      := TRegEx.Create('<summary>([\s\S]*?)</summary>'                     , [roIgnoreCase]);
  RxRemarks      := TRegEx.Create('<remarks>([\s\S]*?)</remarks>'                     , [roIgnoreCase]);
  RxReturns      := TRegEx.Create('<returns>([\s\S]*?)</returns>'                     , [roIgnoreCase]);
  RxExample      := TRegEx.Create('<example>([\s\S]*?)</example>'                     , [roIgnoreCase]);
  RxParam        := TRegEx.Create('<param\s+name="([^"]+)">([\s\S]*?)</param>'        , [roIgnoreCase]);
  RxException    := TRegEx.Create('<exception\s+cref="([^"]+)">([\s\S]*?)</exception>', [roIgnoreCase]);
  RxSee          := TRegEx.Create('<(?:see|seealso)\s+cref="([^"]+)"\s*/?>'           , [roIgnoreCase]);
  RxSinceTag     := TRegEx.Create('<since>([\s\S]*?)</since>'                         , [roIgnoreCase]);
  // v(ADP3 T3b review, Important 2): captures the message from a hand-written
  // '<deprecated>message</deprecated>' so it round-trips instead of
  // collapsing to a bare Boolean. Two SEPARATE regexes rather than one
  // alternation ('<deprecated\s*(?:/>|>(...)</deprecated>)') -- the
  // alternation was tried first and reproducibly crashed ("Index out of
  // bounds") the moment the bare '/>' branch matched: group 1 sits inside
  // the OTHER alternative, so it never participates in that match, and
  // Delphi's TRegEx/TGroupCollection does not tolerate indexing an
  // unparticipated group the way accessing Match.Groups[1].Success first
  // would (confirmed by bisection: a fixture with ONLY a bare
  // '<deprecated/>' reproduced the crash in isolation; reading a captured
  // group only ever from a regex that is GUARANTEED to have that group
  // participate, as done here, sidesteps the problem entirely rather than
  // guarding around it).
  RxDeprecatedTag    := TRegEx.Create('<deprecated>([\s\S]*?)</deprecated>'           , [roIgnoreCase]);
  RxDeprecatedBare   := TRegEx.Create('<deprecated\s*/>'                              , [roIgnoreCase]);

  // v(ADP3 T3): HasSummaryTag/HasReturnsTag record the tag's LITERAL presence
  // (Match.Success), independent of whether its captured group is empty -- see
  // TParsedDoc's own field comment for why MergeComment needs this.
  Match:= RxSummary.Match(Cleaned);
  Result.HasSummaryTag:= Match.Success;
  if Match.Success then Result.Summary:= CollapseWhitespace(Match.Groups[1].Value);

  Match:= RxRemarks.Match(Cleaned);
  if Match.Success then Result.Remarks:= CollapseWhitespace(Match.Groups[1].Value);

  Match:= RxReturns.Match(Cleaned);
  Result.HasReturnsTag:= Match.Success;
  if Match.Success then Result.ReturnsText:= CollapseWhitespace(Match.Groups[1].Value);

  // v(ADP3 T3b review, Important/Minor 1): HasExampleTag mirrors HasSummaryTag/
  // HasReturnsTag's own presence-vs-content distinction -- see TParsedDoc's
  // field comment.
  Match:= RxExample.Match(Cleaned);
  Result.HasExampleTag:= Match.Success;
  if Match.Success then Result.ExampleText:= Trim(Match.Groups[1].Value);

  Match:= RxSinceTag.Match(Cleaned);
  if Match.Success then Result.SinceText:= CollapseWhitespace(Match.Groups[1].Value);

  // v(ADP3 T3b review, Important 2): try the message-bearing form first
  // (group 1 always participates when THIS regex matches at all, so
  // reading it is always safe); only fall back to the bare-tag regex
  // (no group to read) when the message form did not match -- see
  // RxDeprecatedTag's own comment for why this is two regexes, not one
  // alternation.
  Match:= RxDeprecatedTag.Match(Cleaned);
  if Match.Success then
  begin
    Result.Deprecated:= True;
    Result.DeprecatedText:= CollapseWhitespace(Match.Groups[1].Value);
  end
  else
    Result.Deprecated:= RxDeprecatedBare.IsMatch(Cleaned);

  Params:= TList<TDocParam    >.Create;
  Excs  := TList<TDocException>.Create;
  SeeList:= TList<string>.Create;
  try
    Matches:= RxParam.Matches(Cleaned);
    for I:= 0 to Matches.Count - 1 do
    begin
      Param.Name:= Matches[I].Groups[1].Value;
      Param.Desc:= CollapseWhitespace(Matches[I].Groups[2].Value);
      Params.Add(Param);
    end;
    Result.Params:= Params.ToArray;

    Matches:= RxException.Matches(Cleaned);
    for I:= 0 to Matches.Count - 1 do
    begin
      Exc.TypeName:= Matches[I].Groups[1].Value;
      Exc.Desc:= CollapseWhitespace(Matches[I].Groups[2].Value);
      Excs.Add(Exc);
    end;
    Result.Exceptions:= Excs.ToArray;

    Matches:= RxSee.Matches(Cleaned);
    for I:= 0 to Matches.Count - 1 do SeeList.Add(Matches[I].Groups[1].Value);
    Result.SeeAlso:= SeeList.ToArray;
    // v(ADP3 T3b review, Critical 1 fix): SeeAlsoIsInline, parallel to SeeAlso
    // (built in the SAME loop so the index correspondence holds by
    // construction) -- RxSee's own (?:see|seealso) alternation is NOT a
    // capturing group (deliberately, so this loop's existing Groups[1]
    // (the cref) is unaffected), so which alternative fired is read back
    // from the matched text itself: Matches[I].Value is the FULL match
    // (e.g. '<see cref="X"/>' or '<seealso cref="X"/>'), and only the
    // latter starts with the 8-char literal '<seealso'.
    SetLength(Result.SeeAlsoIsInline, Matches.Count);
    for I:= 0 to Matches.Count - 1 do
      Result.SeeAlsoIsInline[I]:= not StartsText('<seealso', Matches[I].Value);
  finally
    Params.Free;
    Excs.Free;
    SeeList.Free;
  end; // try

  // Fallback: untagged text before first tag becomes summary. This is
  // hand-written prose with no <summary> tag at all -- if it yields real
  // text, HasSummaryTag must also flip True (v(ADP3 T3)): otherwise
  // MergeComment's repair path would mistake real prose here for "no summary
  // written" and silently drop it instead of preserving it verbatim.
  if Result.Summary = '' then
  begin
    M:= Cleaned;
    I:= Pos('<', M);
    if I > 0 then M:= Copy(M, 1, I - 1);
    Result.Summary:= CollapseWhitespace(M);
    if Result.Summary <> '' then Result.HasSummaryTag:= True;
  end;

  // v(ADP3 T3 review round 2, Finding 4): HasContent is DELIBERATELY narrow
  // -- a comment consisting ONLY of a human's blank slot (<summary></summary>
  // and/or <returns></returns>, no other content) correctly reads
  // HasContent = False here, and that must stay true: OTHER consumers read
  // this field directly (the indexer's symbol_docs write, context bundling,
  // Resolver.TypeAt's HasDoc, MCP/LSP hover) and correctly treat a blank-
  // slot-only comment as "not documented". A wider "HasSummaryTag or
  // HasReturnsTag" test was tried here (v(ADP3 T3) review fix, Finding 3)
  // and reverted -- it fixed BuildForSymbol's repair-vs-fresh decision but
  // silently widened what EVERY other consumer of HasContent considers
  // "documented" too. BuildForSymbol now computes its OWN separate signal
  // (ExistingHasAnyTag, from HasSummaryTag/HasReturnsTag/Params/an
  // unmodeled-tag check) and passes it to MergeComment explicitly, instead
  // of this field being widened for everyone.
  Result.HasContent:= (Result.Summary <> '') or (Result.Remarks <> '') or (Result.ReturnsText <> '') or (Length(Result.Params) > 0) or
  (Length(Result.Exceptions) > 0) or Result.Deprecated;
end; // function

class function TDocCommentParser.ParsePasDoc(const ARaw: string): TParsedDoc;
var
  Cleaned    : string              ;
  Body       : string              ;
  SummaryPart: string              ;
  Lines      : TArray<string>      ;
  BodyLines  : TArray<string>      ;
  I          : Integer             ;
  BlankIdx   : Integer             ;
  Params     : TList<TDocParam>    ;
  Excs       : TList<TDocException>;
  SeeList    : TList<string>       ;
  RxTag      : TRegEx              ;
  Match      : TMatch              ;
  AccTag     : string              ;
  AccVal     : string              ;

  procedure FlushTag;
  var
    P2      : TDocParam    ;
    E2      : TDocException;
    Tag     : string       ;
    Arg     : string       ;
    ValRest : string       ;
    SpaceIdx: Integer      ;
    Val     : string       ;
  begin
    if AccTag = '' then Exit;
    Val:= Trim     (AccVal);
    Tag:= LowerCase(AccTag);
    if (Tag = 'param') then
    begin
      SpaceIdx:= Pos(' ', Val);
      if SpaceIdx > 0 then
      begin
        P2.Name:= Copy(Val, 1, SpaceIdx - 1);
        P2.Desc:= Trim(Copy(Val, SpaceIdx + 1, MaxInt));
      end
      else
      begin
        P2.Name:= Val;
        P2.Desc:= '';
      end;
      Params.Add(P2);
    end
    else if (Tag = 'returns') or (Tag = 'return') then Result.ReturnsText:= Val
    else if (Tag = 'throws') or (Tag = 'raises') then
    begin
      SpaceIdx:= Pos(' ', Val);
      if SpaceIdx > 0 then
      begin
        E2.TypeName:= Copy(Val, 1, SpaceIdx - 1);
        E2.Desc:= Trim(Copy(Val, SpaceIdx + 1, MaxInt));
      end
      else
      begin
        E2.TypeName:= Val;
        E2.Desc    := '';
      end;
      Excs.Add(E2);
    end
    else if Tag = 'remarks' then Result.Remarks    := Val
    else if Tag = 'example' then Result.ExampleText:= Val
    else if Tag = 'see' then
    begin
      for ValRest in Val.Split([',']) do
      begin
        Arg:= Trim(ValRest);
        if Arg <> '' then SeeList.Add(Arg);
      end;
    end
    else if Tag = 'since'      then Result.SinceText := Val
    else if Tag = 'deprecated' then Result.Deprecated:= True
    else if (Tag = 'author') or (Tag = 'version') then
    begin
      if Result.Remarks <> '' then Result.Remarks:= Result.Remarks + #10;
      Result.Remarks:= Result.Remarks + AccTag + ': ' + Val;
    end;
    AccTag:= '';
    AccVal:= '';
  end; // procedure

begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Format  := dfPasDoc;
  Result.RawBlock:= ARaw;
  Params:= TList<TDocParam    >.Create;
  Excs  := TList<TDocException>.Create;
  SeeList:= TList<string>.Create;
  try
    // Strip leading `*` or `* ` from each line (common in PasDoc blocks)
    Lines:= ARaw.Split([sLineBreak, #10, #13]);
    Cleaned:= '';
    for I:= 0 to High(Lines) do
    begin
      Body:= TrimLeft(Lines[I]);
      if Body.StartsWith('* ') then Body:= Copy(Body, 3, MaxInt)
      else if Body.StartsWith('*') then Body:= Copy(Body, 2, MaxInt);
      if I > 0 then Cleaned:= Cleaned + #10;
      Cleaned:= Cleaned + Body;
    end;
    Cleaned:= Trim(Cleaned);

    // Summary = text before first @tag (or before first blank line, whichever earlier)
    RxTag:= TRegEx.Create('(?m)^\s*@(\w+)\b\s*(.*)$');
    Match:= RxTag .Match (Cleaned                   );
    if Match.Success then SummaryPart:= Trim(Copy(Cleaned, 1, Match.Index - 1))
    else SummaryPart:= Cleaned;

    // Trim summary at first blank line
    BlankIdx:= Pos(#10#10, SummaryPart);
    if BlankIdx > 0 then SummaryPart:= Trim(Copy(SummaryPart, 1, BlankIdx - 1));
    Result.Summary:= CollapseWhitespace(SummaryPart);

    // Walk @tag blocks
    BodyLines:= Cleaned.Split([#10]);
    AccTag:= '';
    AccVal:= '';
    for I:= 0 to High(BodyLines) do
    begin
      Match:= RxTag.Match(BodyLines[I]);
      if Match.Success then
      begin
        FlushTag;
        AccTag:= Match.Groups[1].Value;
        AccVal:= Match.Groups[2].Value;
      end
      else if AccTag <> '' then
      begin
        if Trim(BodyLines[I]) = '' then FlushTag
        else AccVal:= AccVal + ' ' + Trim(BodyLines[I]);
      end;
    end;
    FlushTag;

    Result.Params    := Params .ToArray;
    Result.Exceptions:= Excs   .ToArray;
    Result.SeeAlso   := SeeList.ToArray;
    // v(ADP3 T3b review, Critical 1 fix): PasDoc's single @see tag has no
    // bare-<see>-vs-<seealso> distinction to make (that is an XML-DocInsight-
    // only spelling choice), so every entry reports False (rendered as
    // <seealso> on re-emit, matching this field's behaviour before this
    // change). Sized to match SeeAlso so MergeComment's parallel-array
    // indexing never runs out of bounds regardless of source format.
    SetLength(Result.SeeAlsoIsInline, Length(Result.SeeAlso));

    // v(ADP3 T3): PasDoc has no "explicitly empty tag" concept of its own (an
    // empty @returns/no summary prose reads identically either way), so
    // presence collapses to plain non-empty-content here -- unlike dfXmlDoc's
    // Match.Success, which can distinguish an empty <tag></tag> from no tag.
    Result.HasSummaryTag:= Result.Summary     <> '';
    Result.HasReturnsTag:= Result.ReturnsText <> '';
    // v(ADP3 T3b review, Important/Minor 1): same non-empty-content collapse
    // as HasSummaryTag/HasReturnsTag just above.
    Result.HasExampleTag:= Result.ExampleText <> '';

    Result.HasContent:= (Result.Summary <> '') or (Length(Result.Params) > 0) or (Result.ReturnsText <> '') or Result.Deprecated;
  finally
    Params.Free;
    Excs.Free;
    SeeList.Free;
  end; // try
end; // begin

class function TDocCommentParser.ParseOneline(const ARaw: string; AKind: TDocCommentKind): TParsedDoc;
var
  Lines: TArray<string>;
  Acc  : TStringBuilder;
  I    : Integer       ;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Format  := dfOneline;
  Result.RawBlock:= ARaw;
  Lines:= ARaw.Split([sLineBreak, #10, #13]);
  Acc:= TStringBuilder.Create;
  try
    for I:= 0 to High(Lines) do
    begin
      if Acc.Length > 0 then Acc.Append(' ');
      Acc.Append(StripXmlDocPrefix(Lines[I]));
    end;
    Result.Summary:= CollapseWhitespace(Acc.ToString);
  finally
    Acc.Free;
  end;
  Result.HasContent:= Result.Summary <> '';
  // v(ADP3 T3): a oneline/loose comment has no tags at all -- the whole
  // comment IS the summary, so presence collapses to non-empty content, same
  // as ParsePasDoc's own HasSummaryTag (see its comment).
  Result.HasSummaryTag:= Result.Summary <> '';
end; // function

class function TDocCommentParser.ParseLoose(const ARaw: string): TParsedDoc;
const
  NOISE_PREFIXES: array[0..9] of string = ( 'TODO', 'FIXME', 'HACK', 'XXX', 'REVIEW', '=====', '-----', '#####', 'Copyright', '(c)' );
var
  Lines     : TArray<string>;
  I         : Integer       ;
  NoiseCount: Integer       ;
  TotalCount: Integer       ;
  Stripped  : string        ;
  Noise     : string        ;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Format  := dfLoose;
  Result.RawBlock:= ARaw;

  Lines:= ARaw.Split([sLineBreak, #10, #13]);
  NoiseCount:= 0;
  TotalCount:= 0;
  for I:= 0 to High(Lines) do
  begin
    Stripped:= TrimLeft(StripXmlDocPrefix(Lines[I]));
    if Stripped = '' then Continue;
    Inc(TotalCount);
    for Noise in NOISE_PREFIXES do
      if StartsText(Noise, Stripped) then
      begin
        Inc(NoiseCount);
        Break;
      end;
  end;

  if (TotalCount > 0) and (NoiseCount * 2 > TotalCount) then
  begin
    Result.HasContent:= False;
    Exit;
  end;

  // Treat like oneline
  Result:= ParseOneline(ARaw, dckLooseLine);
  Result.Format:= dfLoose;
end; // function

class function TDocCommentParser.Dispatch(const ARegion: TDocCommentRegion): TParsedDoc;
var
  HasXmlTags: Boolean;
begin
  case ARegion.Kind of
    dckTripleSlash:
    begin
      EnsureSniffRegexes;
      HasXmlTags:= (Pos('<summary>', ARegion.RawText) > 0) or (Pos('<param', ARegion.RawText) > 0) or (Pos('<returns>', ARegion.RawText) > 0) or
      (Pos('<remarks>', ARegion.RawText) > 0) or (Pos('<exception', ARegion.RawText) > 0) or (Pos('<example>', ARegion.RawText) > 0) or
      // v(ADP3 T3b): <since>/<seealso>/<see>/<deprecated/> were missing from
      // this sniff, so a comment whose ONLY tags were these mis-dispatched to
      // ParseOneline -- the whole raw tag text read back as literal prose,
      // never parsed as XML at all (Task 3's implementer hit this while
      // building an unrelated regression test and worked around it in a
      // fixture; fixing the sniff itself was out of that task's scope but is
      // explicitly in scope here).
      // v(ADP3 T3b review, Important 3): tightened from bare '<see'/
      // '<deprecated' prefixes (which over-matched prose merely MENTIONING a
      // tag-like word, e.g. '<seed>', '<deprecatedSoon>', or a bare
      // '<seealso>' with no cref -- ParseXmlDoc's untagged-prefix fallback
      // then truncated the author's whole summary at that first '<', a
      // NEW loss reachable on prose alone, not present before this task) to
      // the tightest literal-substring checks that still catch every REAL
      // tag.
      // v(ADP3 T3b review round 2, NEW IMPORTANT): those "tightest literal-
      // substring" checks were STILL a hand-maintained approximation of
      // RxSee/RxSinceTag/RxDeprecatedTag/RxDeprecatedBare, and drifted from
      // them on shapes none of us anticipated: '<deprecated >msg</deprecated>'
      // (a space before the closing '>' -- neither '<deprecated>' nor
      // '<deprecated ' as a PREFIX check requires the '>' to come right
      // after, so this one slipped through undetected as a false NEGATIVE
      // relative to what a literal Pos() table can express); '<DEPRECATED>'
      // (Pos is case-sensitive, the regexes all carry roIgnoreCase); and a
      // tab before an attribute ('<seealso\tcref="X"/>', which '<seealso '
      // -- literal space -- does not match but \s+ does). Sniffing with the
      // ACTUAL regex objects (IsMatch) retires all three at once, and the
      // sniff can never again be broader or narrower than the parse for
      // these four tags, because there is only one definition of "matches"
      // now, not two.
      SniffSinceTag.IsMatch(ARegion.RawText) or SniffSee.IsMatch(ARegion.RawText) or
      SniffDeprecatedTag.IsMatch(ARegion.RawText) or SniffDeprecatedBare.IsMatch(ARegion.RawText);
      if HasXmlTags then
      begin
        Result:= ParseXmlDoc(ARegion.RawText);
        // v(ADP3 T3b review round 2, NEW IMPORTANT): the sniff above is a
        // superset test (any of these SUBSTRINGS/shapes present) -- it can
        // still fire for a malformed tag that the sniff correctly IDENTIFIES
        // as tag-shaped but that ParseXmlDoc's underlying regex still does
        // not fully match (e.g. '<exception>' with no required cref="..." at
        // all: the bare '<exception' prefix check above has ALWAYS matched
        // that, pre-dating this task, but RxException itself never captures
        // it). When NOTHING recognizable came back at all, ParseXmlDoc's own
        // untagged-prefix fallback reads '' for Summary too (nothing
        // precedes a malformed tag that opens the comment), so HasContent is
        // False and MergeComment/BuildForSymbol would emit NOTHING for this
        // comment -- silently deleting the entire hand-written /// line the
        // moment a facts block is later merged adjacent to it (confirmed
        // empirically: this needs a SECOND apply cycle to surface, since
        // MergeAdjacentSameKind is what first folds the freshly-inserted
        // facts block into the same scanned region, which is what flips
        // HasContent to True and routes the comment into the unconditional
        // repair-delete-insert branch). Falling back to ParseOneline keeps
        // the raw text as prose instead -- not a correct parse, but never a
        // silent delete, and no worse than every OTHER unrecognized-tag
        // shape (e.g. a stray '<value>') already gets today.
        if not HasAnyRecognizedTag(Result) then
          Result:= ParseOneline(ARegion.RawText, ARegion.Kind);
      end
      else Result:= ParseOneline(ARegion.RawText, ARegion.Kind);
    end;
    dckDoubleSlashOne, dckTripleSlashOne: Result:= ParseOneline(ARegion.RawText, ARegion.Kind);
    dckPasDocCurly, dckPasDocParen : Result:= ParsePasDoc(ARegion.RawText);
    dckLooseLine  , dckLooseBlock  : Result:= ParseLoose (ARegion.RawText);
    else FillChar(Result, SizeOf(Result), 0);
  end; // case
  Result.StartLine:= ARegion.StartLine;
  Result.EndLine  := ARegion.EndLine;
end; // function

end.
