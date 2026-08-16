unit DRagLint.Lint.SharedUnit;

{ The `dl:shared` unit marker: a unit compiled by more than one project says so
  in its own source.

    unit YADF.Options;   // dl:shared YADF, YADFOT, YADFSetup

  WHY A MARKER AND NOT DERIVATION. `resolve-dbs --in <file>` answers with the
  OWNING database, one path -- measured 2026-08-13, it returns only YADF.sqlite
  for a unit that YADFOT.dproj and YADFSetup.dproj also compile. Deriving the SET
  would mean opening every index in the manifest on every run, to learn a fact
  that changes about once a year.

  WHY THE PROJECT LIST IS IN THE MARKER. It is not needed by the staleness rule,
  which only asks "is this unit shared". It is there so the blast radius is
  readable in the source without running the tool -- the case that motivated the
  whole feature -- and so `check-shared` can verify the claim instead of trusting
  it. A marker nobody checks decays into a lie, and this one decides staleness.

  WHY THE READER IS A COMMENT-STATE SCANNER AND NOT A LINE SPLIT. Line 1 of a
  unit here is frequently the brace that opens a header block comment -- the same
  anchoring trap already recorded for `unit-too-large` and for `allow` writing a
  `dl:ok` into a block comment where the reader could not see it
  (`CLI.pas:15322`). Splitting on lines and matching text answers "does the
  string appear", which is a different question from "is there a marker here":
  it accepts `dl:shared` inside a string literal and it rejects a marker on the
  second line of a braced block. The scanner below tracks brace, star-paren and
  slash-slash comments plus string state, so both cases come out right.

  (This comment names those delimiters in prose rather than showing them: a
  closing brace inside a braced comment ends it early, which is the same trap one
  level up, and it cost a build today.)

  SCOPE. Only the HEADER REGION is scanned: everything up to and including the
  line that carries the `interface` keyword. A `dl:shared` further down the file
  is not a unit-level declaration and is ignored. }

interface

type
  /// <summary>Reads and writes the `dl:shared` unit marker.</summary>
  /// <remarks>
  /// Stateless; every entry point re-reads the file. All text handling
  /// is 7-bit ASCII and the file's original line endings are preserved -- only
  /// the single marker line is ever rewritten.
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoSharedUnit (DRagLint.CLI.pas), DRagLint.Doc.Facts.UnitIsShared (DRagLint.Doc.Facts.pas), DRagLint.Doc.SharedFacts.TSharedFacts.BlockDrifted (DRagLint.Doc.SharedFacts.pas), DRagLint.Doc.SharedFacts.TSharedFacts.HoldsForeignInboundEntries (DRagLint.Doc.SharedFacts.pas), DRagLint.Doc.SharedFacts.TSharedFacts.MergeInboundFacts (DRagLint.Doc.SharedFacts.pas)
  /// Used in units: DRagLint.CLI, DRagLint.Doc.Facts, DRagLint.Doc.SharedFacts
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSharedUnit = class
  public
    /// <summary>True when the unit carries a `dl:shared` marker.</summary>
    /// <param name="AUnitPath">Path to a `.pas` file. A missing file is False,
    /// not an error.</param>
    /// <returns><!-- drag-lint:auto -->Observed: IsSharedText(ReadUnitText(AUnitPath)).</returns>
    /// <remarks>
    /// Scans the unit's HEADER REGION, not line 1 alone: line 1 of a
    /// unit here is frequently the `{` of a block comment, which is the same
    /// anchoring trap already recorded for unit-too-large and
    /// compiler-magic-comments.
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Doc.Facts.UnitIsShared (DRagLint.Doc.Facts.pas), DRagLint.Doc.SharedFacts.TSharedFacts.BlockDrifted (DRagLint.Doc.SharedFacts.pas), DRagLint.Doc.SharedFacts.TSharedFacts.HoldsForeignInboundEntries (DRagLint.Doc.SharedFacts.pas), DRagLint.Doc.SharedFacts.TSharedFacts.MergeInboundFacts (DRagLint.Doc.SharedFacts.pas)
    /// Calls: DRagLint.Lint.SharedUnit.ReadUnitText, DRagLint.Lint.SharedUnit.TSharedUnit.IsSharedText
    /// Pure
    /// <seealso cref="DRagLint.Lint.SharedUnit.ReadUnitText"/>
    /// <seealso cref="DRagLint.Lint.SharedUnit.TSharedUnit.IsSharedText"/>
    /// <seealso cref="DRagLint.Lint.SharedUnit.TSharedUnit.AddProject"/>
    /// <seealso cref="DRagLint.Lint.SharedUnit.TSharedUnit.AddProjectToText"/>
    /// <seealso cref="DRagLint.Lint.SharedUnit.TSharedUnit.ProjectsOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function IsShared(const AUnitPath: string): Boolean;

    /// <summary>The project names listed on the marker, in written order.</summary>
    /// <param name="AUnitPath">Path to a `.pas` file.</param>
    /// <returns>Empty when the unit is unmarked, when the file is missing, or
    /// when the marker carries no names.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Lint.ProjectRules.TProjectLintRules.Run (DRagLint.Lint.ProjectRules.pas)
    /// Calls: DRagLint.Lint.SharedUnit.ReadUnitText, DRagLint.Lint.SharedUnit.TSharedUnit.ProjectsOfText
    /// Returns: ProjectsOfText(ReadUnitText(AUnitPath))
    /// Pure
    /// <seealso cref="DRagLint.Lint.SharedUnit.ReadUnitText"/>
    /// <seealso cref="DRagLint.Lint.SharedUnit.TSharedUnit.ProjectsOfText"/>
    /// <seealso cref="DRagLint.Lint.SharedUnit.TSharedUnit.AddProject"/>
    /// <seealso cref="DRagLint.Lint.SharedUnit.TSharedUnit.AddProjectToText"/>
    /// <seealso cref="DRagLint.Lint.SharedUnit.TSharedUnit.IsShared"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function ProjectsOf(const AUnitPath: string): TArray<string>;

    /// <summary>Adds AProject to the marker, creating the marker when absent.</summary>
    /// <param name="AUnitPath">Path to a `.pas` file. Never written by this
    /// call -- the caller decides whether to persist ANewText.</param>
    /// <param name="AProject">Project name, e.g. `YADFOT`. Compared
    /// case-insensitively against the names already listed.</param>
    /// <param name="ANewText">The whole file text as it would stand after the
    /// edit. Set to the CURRENT text (unchanged) whenever the result is False,
    /// so a caller that writes unconditionally still cannot corrupt the file.</param>
    /// <returns>False when AProject is already listed -- an idempotent no-op, so
    /// the IDE menu item is safe to press twice. Also False when AProject is
    /// blank, when the file is missing, or when the unit has no `unit` line to
    /// anchor a new marker to.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Calls: DRagLint.Lint.SharedUnit.ReadUnitText, DRagLint.Lint.SharedUnit.TSharedUnit.AddProjectToText
    /// Returns: False; AddProjectToText(ANewText, AProject, ANewText)
    /// Mutates: ANewText (out)
    /// <seealso cref="DRagLint.Lint.SharedUnit.ReadUnitText"/>
    /// <seealso cref="DRagLint.Lint.SharedUnit.TSharedUnit.AddProjectToText"/>
    /// <seealso cref="DRagLint.Lint.SharedUnit.TSharedUnit.IsShared"/>
    /// <seealso cref="DRagLint.Lint.SharedUnit.TSharedUnit.IsSharedText"/>
    /// <seealso cref="DRagLint.Lint.SharedUnit.TSharedUnit.ProjectsOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function AddProject(const AUnitPath, AProject: string; out ANewText: string): Boolean;

    /// <summary>IsShared, against text already in memory.</summary>
    /// <param name="AText"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Observed: ScanHeader(AText, swMarkInComment) &gt;
    /// 0.</returns>
    /// <remarks>
    /// The IDE plugin holds an unsaved editor buffer; making it write a
    /// temp file just to ask this question is the kind of round-trip that goes
    /// stale.
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoSharedUnit (DRagLint.CLI.pas), DRagLint.Lint.SharedUnit.TSharedUnit.IsShared (DRagLint.Lint.SharedUnit.pas)
    /// Calls: DRagLint.Lint.SharedUnit.ScanHeader
    /// Pure
    /// <seealso cref="DRagLint.Lint.SharedUnit.ScanHeader"/>
    /// <seealso cref="DRagLint.Lint.SharedUnit.TSharedUnit.AddProject"/>
    /// <seealso cref="DRagLint.Lint.SharedUnit.TSharedUnit.AddProjectToText"/>
    /// <seealso cref="DRagLint.Lint.SharedUnit.TSharedUnit.IsShared"/>
    /// <seealso cref="DRagLint.Lint.SharedUnit.TSharedUnit.ProjectsOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function IsSharedText(const AText: string): Boolean;

    /// <summary>ProjectsOf, against text already in memory.</summary>
    /// <param name="AText"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Observed: nil; Names.ToArray.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoSharedUnit (DRagLint.CLI.pas), DRagLint.Lint.SharedUnit.TSharedUnit.AddProjectToText (DRagLint.Lint.SharedUnit.pas), DRagLint.Lint.SharedUnit.TSharedUnit.ProjectsOf (DRagLint.Lint.SharedUnit.pas)
    /// Calls: Copy, DRagLint.Lint.SharedUnit.LineRangeAt, DRagLint.Lint.SharedUnit.ScanHeader, DRagLint.Lint.SharedUnit.SplitCommentTail, Trim
    /// Pure
    /// <seealso cref="DRagLint.Lint.SharedUnit.LineRangeAt"/>
    /// <seealso cref="DRagLint.Lint.SharedUnit.ScanHeader"/>
    /// <seealso cref="DRagLint.Lint.SharedUnit.SplitCommentTail"/>
    /// <seealso cref="DRagLint.Lint.SharedUnit.TSharedUnit.AddProject"/>
    /// <seealso cref="DRagLint.Lint.SharedUnit.TSharedUnit.AddProjectToText"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function ProjectsOfText(const AText: string): TArray<string>;

    /// <summary>AddProject, against text already in memory.</summary>
    /// <param name="AText"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AProject"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ANewText"><!-- drag-lint:auto type -->out string</param>
    /// <returns><!-- drag-lint:auto -->Observed: False; True.</returns>
    /// <remarks>
    /// This is the seam the round-trip check uses: the caller re-reads
    /// ANewText with ProjectsOfText and refuses to write anything that does not
    /// parse back. A marker that does not parse back reads as "declared shared"
    /// while behaving as unshared, which is worse than no marker at all.
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoSharedUnit (DRagLint.CLI.pas), DRagLint.Lint.SharedUnit.TSharedUnit.AddProject (DRagLint.Lint.SharedUnit.pas)
    /// Calls: Copy, DRagLint.Lint.SharedUnit.LineRangeAt, DRagLint.Lint.SharedUnit.ScanHeader, DRagLint.Lint.SharedUnit.SplitCommentTail, DRagLint.Lint.SharedUnit.TSharedUnit.ProjectsOfText, SameText, Trim, TrimLeft, TrimRight
    /// Mutates: ANewText (out)
    /// <seealso cref="DRagLint.Lint.SharedUnit.LineRangeAt"/>
    /// <seealso cref="DRagLint.Lint.SharedUnit.ScanHeader"/>
    /// <seealso cref="DRagLint.Lint.SharedUnit.SplitCommentTail"/>
    /// <seealso cref="DRagLint.Lint.SharedUnit.TSharedUnit.ProjectsOfText"/>
    /// <seealso cref="DRagLint.Lint.SharedUnit.TSharedUnit.AddProject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function AddProjectToText(const AText, AProject: string; out ANewText: string): Boolean;
  end;

implementation

uses
  System.SysUtils
  , System.IOUtils
  , System.Generics.Collections
  , DRagLint.Lint.ReviewMarker  // SHARED_MARK
  ;

const
  IDENT_CHARS = ['A'..'Z', 'a'..'z', '0'..'9', '_'];
  EOL_CHARS   = [#13, #10];

type
  { What one pass of the header scanner is looking for. Both questions need the
    identical comment/string state machine, and two copies of it would drift. }
  TScanWant = (swMarkInComment, swUnitKeyword);

{ ---------------------------------------------------------------------------
  The header scanner
  --------------------------------------------------------------------------- }

/// <summary>Scans the header region and returns the 1-based position of what
/// AWant asks for, or 0.</summary>
/// <remarks>swMarkInComment matches SHARED_MARK only while inside a comment;
/// swUnitKeyword matches the `unit` keyword only while in code. The region ends
/// with the line carrying the `interface` keyword -- scanning continues to that
/// line's end, so a marker parked after the keyword is still seen.</remarks>
function ScanHeader(const AText: string; AWant: TScanWant): Integer;
var
  N, I, StopAt: Integer;
  InBrace, InParen, InLineCmt, InStr: Boolean;
  Ch: Char;

  function AtText(const AWhat: string): Boolean;
  begin
    Result:= (I + Length(AWhat) - 1 <= N) and SameText(Copy(AText, I, Length(AWhat)), AWhat);
  end;

  function AtWord(const AWord: string): Boolean;
  var
    E: Integer;
  begin
    Result:= False;
    if not AtText(AWord) then Exit;
    if (I > 1) and CharInSet(AText[I - 1], IDENT_CHARS) then Exit;
    E:= I + Length(AWord);
    if (E <= N) and CharInSet(AText[E], IDENT_CHARS) then Exit;
    Result:= True;
  end;

begin
  Result   := 0;
  N        := Length(AText);
  StopAt   := N;
  InBrace  := False;
  InParen  := False;
  InLineCmt:= False;
  InStr    := False;
  I        := 1;

  while (I <= N) and (I <= StopAt) do
  begin
    Ch:= AText[I];

    if InLineCmt then
    begin
      if (AWant = swMarkInComment) and AtText(SHARED_MARK) then Exit(I);
      if CharInSet(Ch, EOL_CHARS) then InLineCmt:= False;
      Inc(I);
      Continue;
    end;

    if InBrace then
    begin
      if (AWant = swMarkInComment) and AtText(SHARED_MARK) then Exit(I);
      if Ch = '}' then InBrace:= False;
      Inc(I);
      Continue;
    end;

    if InParen then
    begin
      if (AWant = swMarkInComment) and AtText(SHARED_MARK) then Exit(I);
      if (Ch = '*') and (I < N) and (AText[I + 1] = ')') then
      begin
        InParen:= False;
        Inc(I);
      end;
      Inc(I);
      Continue;
    end;

    if InStr then
    begin
      { A doubled quote inside a literal re-opens it on the next pass, which is
        the same net state -- no special case needed. }
      if Ch = '''' then InStr:= False;
      Inc(I);
      Continue;
    end;

    { code }
    if Ch = '''' then begin InStr    := True; Inc(I);    Continue; end;
    if Ch = '{'  then begin InBrace  := True; Inc(I);    Continue; end;
    if (Ch = '(') and (I < N) and (AText[I + 1] = '*') then begin InParen  := True; Inc(I, 2); Continue; end;
    if (Ch = '/') and (I < N) and (AText[I + 1] = '/') then begin InLineCmt:= True; Inc(I, 2); Continue; end;

    if (AWant = swUnitKeyword) and AtWord('unit') then Exit(I);

    if (StopAt = N) and AtWord('interface') then
    begin
      StopAt:= I;
      while (StopAt <= N) and not CharInSet(AText[StopAt], EOL_CHARS) do Inc(StopAt);
    end;

    Inc(I);
  end;
end;

/// <summary>The 1-based bounds of the line containing APos, EOL excluded.</summary>
procedure LineRangeAt(const AText: string; APos: Integer; out ALineStart, ALineStop: Integer);
begin
  ALineStart:= APos;
  while (ALineStart > 1) and not CharInSet(AText[ALineStart - 1], EOL_CHARS) do Dec(ALineStart);
  ALineStop:= APos;
  while (ALineStop < Length(AText)) and not CharInSet(AText[ALineStop + 1], EOL_CHARS) do Inc(ALineStop);
end;

/// <summary>Splits the text after the marker tag into the project list and the
/// comment terminator that follows it, if any.</summary>
/// <remarks>`{ dl:shared YADF, YADFOT }` must not parse its last project as
/// "YADFOT }".</remarks>
function SplitCommentTail(const ARest: string; out ATail: string): string;
var
  I: Integer;
begin
  ATail:= '';
  I    := 1;
  while I <= Length(ARest) do
  begin
    if ARest[I] = '}' then Break;
    if (ARest[I] = '*') and (I < Length(ARest)) and (ARest[I + 1] = ')') then Break;
    Inc(I);
  end;
  if I <= Length(ARest) then
  begin
    ATail := Copy(ARest, I, MaxInt);
    Result:= Copy(ARest, 1, I - 1);
  end
  else
    Result:= ARest;
end;

/// <summary>Reads a source file as ANSI, or '' when it is not there.</summary>
/// <remarks>ANSI, not the BOM-sniffing default: these files are strict 7-bit
/// ASCII and this unit rewrites one line of them, so read and write must be the
/// same encoding or the untouched bytes do not round-trip.</remarks>
function ReadUnitText(const AUnitPath: string): string;
begin
  Result:= '';
  if (AUnitPath = '') or (not FileExists(AUnitPath)) then Exit;
  Result:= TFile.ReadAllText(AUnitPath, TEncoding.ANSI);
end;

{ ---------------------------------------------------------------------------
  TSharedUnit
  --------------------------------------------------------------------------- }

class function TSharedUnit.IsSharedText(const AText: string): Boolean;
begin
  Result:= ScanHeader(AText, swMarkInComment) > 0;
end;

class function TSharedUnit.IsShared(const AUnitPath: string): Boolean;
begin
  Result:= IsSharedText(ReadUnitText(AUnitPath));
end;

class function TSharedUnit.ProjectsOfText(const AText: string): TArray<string>;
var
  MarkPos, LineStart, LineStop: Integer;
  Rest, Body, Tail, Tok: string;
  Names: TList<string>;
begin
  Result := nil;
  MarkPos:= ScanHeader(AText, swMarkInComment);
  if MarkPos = 0 then Exit;

  LineRangeAt(AText, MarkPos, LineStart, LineStop);
  Rest:= Copy(AText, MarkPos + Length(SHARED_MARK),
              LineStop - (MarkPos + Length(SHARED_MARK)) + 1);
  Body:= SplitCommentTail(Rest, Tail);

  Names:= TList<string>.Create;
  try
    for Tok in Body.Split([',']) do
    begin
      if Trim(Tok) <> '' then Names.Add(Trim(Tok));
    end;
    Result:= Names.ToArray;
  finally
    Names.Free;
  end;
end;

class function TSharedUnit.ProjectsOf(const AUnitPath: string): TArray<string>;
begin
  Result:= ProjectsOfText(ReadUnitText(AUnitPath));
end;

class function TSharedUnit.AddProjectToText(const AText, AProject: string;
  out ANewText: string): Boolean;
var
  Proj, Rest, Body, Tail, NewLine: string;
  MarkPos, UnitPos, LineStart, LineStop, I: Integer;
  Existing: TArray<string>;
begin
  ANewText:= AText;
  Result  := False;

  Proj:= Trim(AProject);
  if Proj = '' then Exit;

  MarkPos:= ScanHeader(AText, swMarkInComment);
  if MarkPos > 0 then
  begin
    Existing:= ProjectsOfText(AText);
    for I:= 0 to High(Existing) do
      if SameText(Existing[I], Proj) then Exit;  { already listed -- idempotent no-op }

    LineRangeAt(AText, MarkPos, LineStart, LineStop);
    Rest:= Copy(AText, MarkPos + Length(SHARED_MARK),
                LineStop - (MarkPos + Length(SHARED_MARK)) + 1);
    Body:= SplitCommentTail(Rest, Tail);

    if Trim(Body) = '' then
      Body:= ' ' + Proj
    else
      Body:= TrimRight(Body) + ', ' + Proj;
    if Tail <> '' then
      Body:= Body + ' ' + TrimLeft(Tail);

    { The tag's own spelling is copied out of the source rather than re-emitted
      from SHARED_MARK, so a marker written `DL:Shared` keeps its casing and the
      edit stays a one-token append. }
    NewLine := Copy(AText, LineStart, MarkPos - LineStart + Length(SHARED_MARK)) + Body;
    ANewText:= Copy(AText, 1, LineStart - 1) + NewLine + Copy(AText, LineStop + 1, MaxInt);
    Exit(True);
  end;

  { No marker yet: anchor a new one on the `unit` declaration line. The scanner
    finds that keyword in CODE state only, so a `unit` mentioned inside the
    header block comment cannot be mistaken for the declaration. }
  UnitPos:= ScanHeader(AText, swUnitKeyword);
  if UnitPos = 0 then Exit;

  LineRangeAt(AText, UnitPos, LineStart, LineStop);
  NewLine := TrimRight(Copy(AText, LineStart, LineStop - LineStart + 1)) +
             '   // ' + SHARED_MARK + ' ' + Proj;
  ANewText:= Copy(AText, 1, LineStart - 1) + NewLine + Copy(AText, LineStop + 1, MaxInt);
  Result  := True;
end;

class function TSharedUnit.AddProject(const AUnitPath, AProject: string;
  out ANewText: string): Boolean;
begin
  ANewText:= ReadUnitText(AUnitPath);
  Result  := False;
  if ANewText = '' then Exit;
  Result:= AddProjectToText(ANewText, AProject, ANewText);
end;

end.
