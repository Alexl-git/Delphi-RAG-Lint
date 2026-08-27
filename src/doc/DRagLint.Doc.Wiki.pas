unit DRagLint.Doc.Wiki;

{ dl:wiki -- human-vocabulary concept blocks, parsed OUT of doc comments the
  index already stores.

  THE WHOLE POINT, AND WHY THIS UNIT IS WHERE IT IS
  ------------------------------------------------
  A `dl:wiki` topic is written inside an ordinary DocInsight (///) comment, so
  it is captured by the EXISTING extractor: every Parse* in
  DRagLint.Parser.DocComments assigns the comment verbatim to RawBlock, and the
  indexer writes that to symbol_docs.raw_block. Nothing here runs at index time.
  This unit is a pure READ-SIDE parse of text that is already in the database,
  which is exactly why the feature needs no DRAGLINT_EXTRACTOR_VERSION bump and
  no re-parse of any index (see docs\PLAN-wiki-comments.md section 4, owner
  ruling R2).

  That property is LOAD-BEARING, not incidental. src\doc is outside the set of
  directories run_extractor_version_guard.ps1 hashes (src\parser, src\preprocess,
  src\index, src\core\DRagLint.Core.Indexer.pas). Moving this unit into any of
  those would make every future edit to it demand a multi-hour reindex of the
  whole box. If a genuine extraction change is ever needed here, STOP and
  re-raise it rather than bumping quietly.

  WHAT THE TEXT LOOKS LIKE BY THE TIME IT REACHES US
  --------------------------------------------------
  Measured 2026-08-27 against the shipping engine, not assumed:

    * raw_block has the `///` already removed and ONE leading space kept, so a
      line reads " dl:wiki Delta Streaming". BuildCleaned removes that space --
      which is why this unit goes through BuildCleaned rather than splitting
      raw_block itself.
    * raw_block's lines are joined with CRLF EVEN WHEN THE SOURCE FILE IS LF.
      BuildCleaned re-joins with a bare #10, so the line INDEX is stable and is
      what HeaderLine is computed from.
    * A comment above `unit X;` attaches to the skUnit symbol and gets its own
      symbol_docs row. That is the recommended home for a multi-type concept:
      skUnit is not in DOCUMENTABLE_KINDS, so the autodoc rewriter never opens
      that comment at all.

  THE GRAMMAR IS LINE-ORIENTED ON PURPOSE
  ---------------------------------------
  It is not XML, and it deliberately does not become XML. The block lives inside
  <remarks>, whose content is prose; making the wiki body a nested tag set would
  mean the doc engine, the hover renderer and DocInsight itself all have to
  agree about tags none of them model. A prefix on a line is something every one
  of those surfaces already passes through untouched. }

interface

uses
  System.SysUtils, System.Classes, System.StrUtils, System.Generics.Collections,
  DRagLint.Core.Model;

const
  /// <summary>The marker that opens a topic. Follows the existing dl: family
  /// (dl:ok, dl:shared in DRagLint.Lint.ReviewMarker) rather than inventing a
  /// second convention -- owner ruling R1, 2026-08-27.</summary>
  WIKI_MARK = 'dl:wiki';

type
  /// <summary>Parses `dl:wiki` topics out of stored doc-comment text, and ranks
  /// them against a human phrase.</summary>
  /// <remarks>Stateless; every method is a class function. Reads nothing but
  /// its arguments -- no file system, no database.</remarks>
  TWikiParser = class
    public
      /// <summary>Cheap pre-filter: does this raw block contain the marker at
      /// all?</summary>
      /// <param name="ARaw">A symbol_docs.raw_block value.</param>
      /// <returns>True when a full parse is worth running.</returns>
      /// <remarks>Case-insensitive, matching both the header test below and
      /// SQLite's ASCII-case-insensitive LIKE, so the SQL pre-filter and this
      /// can never disagree about which rows are candidates.</remarks>
      class function HasMarker(const ARaw: string): Boolean; static;

      /// <summary>Parses every topic in one doc block.</summary>
      /// <param name="ARaw">The raw_block text, exactly as stored.</param>
      /// <param name="AOwnerQName">Qualified name of the owning symbol.</param>
      /// <param name="AOwnerKind">Its kind ('unit', 'class', ...).</param>
      /// <param name="AFilePath">Absolute path of the owning file.</param>
      /// <param name="ADocStartLine">symbol_docs.start_line -- the 1-based file
      /// line of the comment's FIRST line. HeaderLine is derived from it.</param>
      /// <returns>Zero or more topics, in the order they appear.</returns>
      /// <remarks>Never raises on malformed input: an unnamed header yields a
      /// topic with an empty Name, and an alias/seecode line with nothing after
      /// the colon contributes nothing. Reporting bad input is
      /// <c>wiki --check</c>'s job, not the parser's.</remarks>
      class function ParseRawBlock(const ARaw, AOwnerQName, AOwnerKind,
        AFilePath: string; ADocStartLine: Integer): TArray<TWikiTopic>; static;

      /// <summary>Removes every <c>dl:wiki</c> topic from a doc text, leaving
      /// the prose that was not part of one.</summary>
      /// <param name="AText">Any doc text -- typically a symbol's
      /// &lt;remarks&gt; after TDocRegions.StripForDisplay.</param>
      /// <param name="ANames">Receives the names of the topics removed, so the
      /// caller can put an indicator where the body used to be.</param>
      /// <returns>AText minus the topic sections.</returns>
      /// <remarks>FOR HOVER AND OTHER GLANCE-SIZED SURFACES. Owner ruling R3,
      /// 2026-08-27: <i>"might be too long. Hover should say has Wiki - a
      /// clickable link to jump to the text."</i> A concept body is paragraphs
      /// and a hover popup is a glance; putting one inside the other makes the
      /// popup useless for its actual job.
      /// <para>Engine-generated fact blocks (AUTO_BEGIN..AUTO_END) are KEPT --
      /// the hover renderer deliberately shows those, and they are not part of
      /// any topic. Shares ParseRawBlock's single walk, so what is removed here
      /// is exactly what <c>wiki</c> reports, and the two cannot drift into
      /// disagreeing about where a topic ends.</para></remarks>
      class function StripTopics(const AText: string; out ANames: TArray<string>): string; static;

      /// <summary>How well ATerm matches a topic's name or any of its
      /// aliases.</summary>
      /// <param name="ATopic">The candidate.</param>
      /// <param name="ATerm">The human phrase the user typed.</param>
      /// <returns>0 for no match; higher is better. The bands are exact (100),
      /// prefix either direction (80), whole-word containment either direction
      /// (60), plain substring either direction (40).</returns>
      /// <remarks>BOTH DIRECTIONS is the requirement, not a nicety: the user
      /// types "the scheduler" and the alias is "scheduler". A one-way
      /// containment test answers nothing for exactly the phrasing this
      /// feature exists to accept.</remarks>
      class function MatchScore(const ATopic: TWikiTopic; const ATerm: string): Integer; static;

      /// <summary>Comparison for ranking: better score first, then shorter
      /// name.</summary>
      /// <param name="AScoreA">Left topic's MatchScore.</param>
      /// <param name="ANameA">Left topic's Name.</param>
      /// <param name="AScoreB">Right topic's MatchScore.</param>
      /// <param name="ANameB">Right topic's Name.</param>
      /// <returns>Negative when A should print before B, positive when B
      /// should, zero when the two are indistinguishable.</returns>
      /// <remarks>Shortest-name tiebreak follows <c>query --name-like</c>,
      /// whose guard pins the same rule -- one ordering convention, not
      /// two.</remarks>
      class function CompareRanked(AScoreA: Integer; const ANameA: string;
        AScoreB: Integer; const ANameB: string): Integer; static;
    private
      /// <summary>True when ALine is nothing but XML markup (tags and/or an
      /// HTML comment) once the tags are removed.</summary>
      /// <param name="ALine">One cleaned comment line.</param>
      /// <returns>True to drop the line from the body.</returns>
      /// <remarks>Used to keep <c>&lt;/remarks&gt;</c> out of the body without
      /// mangling a prose line that merely mentions a tag.</remarks>
      class function IsMarkupOnly(const ALine: string): Boolean; static;
      /// <summary>Splits a comma list, trims each item, drops empties.</summary>
      /// <param name="AText">The text after an `Aliases:` or `SeeCode:` label.</param>
      /// <returns>The non-empty trimmed items, in order.</returns>
      class function SplitList(const AText: string): TArray<string>; static;
      /// <summary>True when ANeedle occurs in AHay bounded by non-alphanumerics
      /// on both sides.</summary>
      /// <param name="AHay">Haystack; must already be lower case.</param>
      /// <param name="ANeedle">Needle; must already be lower case.</param>
      /// <returns>True on a whole-word occurrence.</returns>
      class function ContainsWholeWord(const AHay, ANeedle: string): Boolean; static;
      /// <summary>THE ONE WALK. Parses topics and, when ANonWiki is supplied,
      /// simultaneously collects every line that is NOT part of a topic.</summary>
      /// <param name="ARaw">The text to walk.</param>
      /// <param name="AOwnerQName">Owning symbol, stamped on each topic.</param>
      /// <param name="AOwnerKind">Its kind.</param>
      /// <param name="AFilePath">Owning file, stamped on each topic.</param>
      /// <param name="ADocStartLine">File line of the comment's first line.</param>
      /// <param name="ANonWiki">Receives the non-topic lines, or nil when the
      /// caller only wants the topics.</param>
      /// <returns>The topics, in the order they appear.</returns>
      /// <remarks>Both public entry points route through here so that "what a
      /// topic covers" has exactly one definition. Two walks would drift, and
      /// the failure would be silent: the hover would strip a line the wiki
      /// verb still showed, or leave one it did not.</remarks>
      class function Walk(const ARaw, AOwnerQName, AOwnerKind, AFilePath: string;
        ADocStartLine: Integer; ANonWiki: TStrings): TArray<TWikiTopic>; static;
  end;

implementation

uses
  DRagLint.Parser.DocComments,
  DRagLint.Doc.Regions;

{ TWikiParser }

class function TWikiParser.HasMarker(const ARaw: string): Boolean;
begin
  Result:= (ARaw <> '') and (Pos(WIKI_MARK, LowerCase(ARaw)) > 0);
end;

class function TWikiParser.IsMarkupOnly(const ALine: string): Boolean;
var
  S    : string ;
  I    : Integer;
  Depth: Integer;
  Ch   : Char   ;
begin
  S:= Trim(ALine);
  if S = '' then Exit(False);
  if S[1] <> '<' then Exit(False);
  { Walk once, dropping every <...> span; whatever is left outside the angle
    brackets is prose. An HTML comment is just a span like any other here. }
  Depth:= 0;
  for I:= 1 to Length(S) do
  begin
    Ch:= S[I];
    if Ch = '<' then Inc(Depth)
    else if Ch = '>' then
    begin
      if Depth > 0 then Dec(Depth);
    end
    else if (Depth = 0) and (Ch <> ' ') and (Ch <> #9) then Exit(False);
  end;
  Result:= True;
end;

class function TWikiParser.SplitList(const AText: string): TArray<string>;
var
  Part: string;
begin
  SetLength(Result, 0);
  for Part in string(AText).Split([',']) do
    if Trim(Part) <> '' then Result:= Result + [Trim(Part)];
end;

class function TWikiParser.ContainsWholeWord(const AHay, ANeedle: string): Boolean;
var
  P     : Integer;
  Before: Char   ;
  After : Char   ;
  Start : Integer;
begin
  Result:= False;
  if (AHay = '') or (ANeedle = '') then Exit;
  Start:= 1;
  repeat
    P:= PosEx(ANeedle, AHay, Start);
    if P <= 0 then Exit;
    Before:= ' ';
    if P > 1 then Before:= AHay[P - 1];
    After:= ' ';
    if P + Length(ANeedle) <= Length(AHay) then After:= AHay[P + Length(ANeedle)];
    if (not CharInSet(Before, ['a'..'z', '0'..'9'])) and
       (not CharInSet(After , ['a'..'z', '0'..'9'])) then Exit(True);
    Start:= P + 1;
  until Start > Length(AHay);
end;

class function TWikiParser.ParseRawBlock(const ARaw, AOwnerQName, AOwnerKind,
  AFilePath: string; ADocStartLine: Integer): TArray<TWikiTopic>;
begin
  Result:= Walk(ARaw, AOwnerQName, AOwnerKind, AFilePath, ADocStartLine, nil);
end;

class function TWikiParser.StripTopics(const AText: string; out ANames: TArray<string>): string;
var
  Rest  : TStringList      ;
  Topics: TArray<TWikiTopic>;
  T     : TWikiTopic       ;
begin
  SetLength(ANames, 0);
  Rest:= TStringList.Create;
  try
    { Line numbers are meaningless here -- AText is a <remarks> fragment, not
      the whole comment -- so 0 is passed deliberately. The caller that needs a
      LOCATION parses the raw block instead; this one only needs the names. }
    Topics:= Walk(AText, '', '', '', 0, Rest);
    for T in Topics do
      if Trim(T.Name) <> '' then ANames:= ANames + [T.Name];
    { TStringList.Text appends a trailing break; Trim keeps the caller's
      "is there anything left" test honest. }
    Result:= Trim(Rest.Text);
  finally
    Rest.Free;
  end;
end;

class function TWikiParser.Walk(const ARaw, AOwnerQName, AOwnerKind, AFilePath: string;
  ADocStartLine: Integer; ANonWiki: TStrings): TArray<TWikiTopic>;
var
  Lines    : TArray<string>   ;
  Topics   : TList<TWikiTopic>;
  Cur      : TWikiTopic       ;
  BodyLines: TStringList      ;
  Have     : Boolean          ;
  InAuto   : Boolean          ;
  I        : Integer          ;
  Raw      : string           ;
  L        : string           ;
  Low      : string           ;
  Rest     : string           ;

  { A line that belongs to NO topic. Collected only when the caller asked;
    every Continue in the walk below is therefore an explicit decision about
    which side of the line it falls on, rather than a silent drop. }
  procedure Keep(const ALine: string);
  begin
    if ANonWiki <> nil then ANonWiki.Add(ALine);
  end;

  procedure Flush;
  begin
    if not Have then Exit;
    Cur.Body:= Trim(BodyLines.Text);
    Topics.Add(Cur);
    Have:= False;
  end;

  procedure StartTopic(const AName: string; ALineIdx: Integer);
  begin
    Flush;
    Cur:= Default(TWikiTopic);
    Cur.Name      := AName;
    Cur.OwnerQName:= AOwnerQName;
    Cur.OwnerKind := AOwnerKind;
    Cur.FilePath  := AFilePath;
    { ADocStartLine is the file line of the comment's first line, and
      BuildCleaned emits exactly one output line per input line, so the index
      into Lines IS the offset from that first line. }
    Cur.HeaderLine:= ADocStartLine + ALineIdx;
    BodyLines.Clear;
    Have:= True;
  end;

begin
  SetLength(Result, 0);
  if not HasMarker(ARaw) then
  begin
    { No marker: every line is non-wiki. Returning early WITHOUT saying so
      would hand the stripper an empty string and silently delete a doc
      comment that had nothing to do with this feature. }
    if ANonWiki <> nil then ANonWiki.Text:= ARaw;
    Exit;
  end;

  { BuildCleaned, not a hand split: it is the ONE definition of "raw_block with
    the comment prefix removed", and going through it is what makes the line
    indexes here agree with every offset the doc engine reports. }
  Lines:= TDocCommentParser.BuildCleaned(ARaw).Split([#10]);

  Topics   := TList<TWikiTopic>.Create;
  BodyLines:= TStringList.Create;
  try
    Have  := False;
    InAuto:= False;
    Cur   := Default(TWikiTopic);

    for I:= 0 to High(Lines) do
    begin
      Raw:= Lines[I];
      L  := Trim(Raw);

      { Engine-owned facts never belong in a hand-written concept body. The
        fence is checked before anything else so a topic that happens to sit
        beside a facts block cannot swallow it. }
      if Pos(AUTO_BEGIN, L) > 0 then begin InAuto:= True ; Keep(Raw); Continue; end;
      if Pos(AUTO_END  , L) > 0 then begin InAuto:= False; Keep(Raw); Continue; end;
      if InAuto then begin Keep(Raw); Continue; end;

      Low:= LowerCase(L);

      if StartsStr(WIKI_MARK, Low) then
      begin
        { `dl:wikifoo` is not a header. Only whitespace -- or nothing at all --
          may follow the marker. }
        if (Length(L) = Length(WIKI_MARK)) or
           CharInSet(L[Length(WIKI_MARK) + 1], [' ', #9]) then
        begin
          Rest:= Trim(Copy(L, Length(WIKI_MARK) + 1, MaxInt));
          StartTopic(Rest, I);
          Continue;
        end;
      end;

      if not Have then begin Keep(Raw); Continue; end;  { not ours }

      if StartsText('Aliases:', L) then
      begin
        Cur.Aliases:= Cur.Aliases + SplitList(Copy(L, Length('Aliases:') + 1, MaxInt));
        Continue;
      end;
      if StartsText('SeeCode:', L) then
      begin
        Cur.SeeCode:= Cur.SeeCode + SplitList(Copy(L, Length('SeeCode:') + 1, MaxInt));
        Continue;
      end;
      if StartsText('Body:', L) then
      begin
        Rest:= Trim(Copy(L, Length('Body:') + 1, MaxInt));
        if Rest <> '' then BodyLines.Add(Rest);
        Continue;
      end;

      { `</remarks>` and friends close the comment, not the topic; dropping them
        keeps the body readable without needing the author to end the block
        explicitly. A prose line that merely MENTIONS a tag is kept -- see
        IsMarkupOnly. }
      if IsMarkupOnly(L) then begin Keep(Raw); Continue; end;

      { Lenient fallback (plan section 3): untagged lines after the header join
        the body even when the author never wrote `Body:`. }
      BodyLines.Add(Raw);
    end;

    Flush;
    Result:= Topics.ToArray;
  finally
    BodyLines.Free;
    Topics   .Free;
  end; // try
end; // function

class function TWikiParser.MatchScore(const ATopic: TWikiTopic; const ATerm: string): Integer;
var
  T   : string        ;
  Cand: TArray<string>;
  C   : string        ;
  S   : Integer       ;
  A   : string        ;
begin
  Result:= 0;
  T:= LowerCase(Trim(ATerm));
  if T = '' then Exit;

  Cand:= [LowerCase(Trim(ATopic.Name))];
  for A in ATopic.Aliases do Cand:= Cand + [LowerCase(Trim(A))];

  for C in Cand do
  begin
    if C = '' then Continue;
    if      C = T                                              then S:= 100
    else if StartsStr(T, C) or StartsStr(C, T)                 then S:= 80
    else if ContainsWholeWord(T, C) or ContainsWholeWord(C, T) then S:= 60
    else if (Pos(C, T) > 0) or (Pos(T, C) > 0)                 then S:= 40
    else                                                            S:= 0;
    if S > Result then Result:= S;
  end;
end;

class function TWikiParser.CompareRanked(AScoreA: Integer; const ANameA: string;
  AScoreB: Integer; const ANameB: string): Integer;
begin
  if AScoreA <> AScoreB then Exit(AScoreB - AScoreA);          { higher first }
  Result:= Length(ANameA) - Length(ANameB);                    { shorter first }
  if Result = 0 then Result:= CompareText(ANameA, ANameB);
end;

end.
