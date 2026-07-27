unit DRagLint.Doc.Strip;

{ AutoDocument Phase 3 Task 2: `document --strip` -- the inverse of the
  `document` write path. Removes exactly what the engine itself wrote into a
  DocInsight (///) comment -- every AUTO_MARK-carrying tag and every
  AUTO_BEGIN..AUTO_END facts region -- and nothing else. Hand-written tags,
  prose, code and ordinary comments are untouched, byte-for-byte.

  Deliberately independent of the parsed doc model (DRagLint.Parser.
  DocComments) and of the symbol index: this unit is a plain line-oriented
  scan over the RAW source text, so it strips a file the parser cannot
  resolve a symbol in just as reliably as a fully indexed one -- the same
  property that lets Task 9's harvest round-trip and Task 17's rollout use
  --strip to reset a real project before re-applying. }

interface

uses
  System.SysUtils, System.Classes,
  DRagLint.Refactor.TextEdit;

type
  /// <summary>Result of stripping one file's engine-owned doc-comment
  /// content.</summary>
  TStripResult = record
    FilePath     : string;             // echoes the input path
    TagsRemoved  : Integer;             // marked <summary>/<param>/<returns> lines dropped (rules 1 + 3)
    BlocksRemoved: Integer;             // AUTO_BEGIN..AUTO_END facts regions dropped (rule 2)
    Edits        : TArray<TTextEdit>;   // tekDeleteLines ranges; empty when nothing to strip
  end;

  /// <summary>Computes (and, via the caller's TTextEditApplier.Apply, performs)
  /// the exact removal of drag-lint's own managed doc-comment output from a
  /// .pas file. Ownership is marker-keyed only -- the same rule the write path
  /// (TDocRegions.MergeComment) uses -- so a hand-written tag or a genuinely
  /// hand-written multi-line &lt;remarks&gt; block is never touched.</summary>
  TDocStripper = class
  public
    /// <summary>Reads AFilePath (ANSI, same reader TDocumenter.BuildForSymbol
    /// uses), scans every source line whose trimmed form starts with '///' for
    /// engine-owned content, and returns the TTextEdit deletions needed to
    /// remove it. Dry-run data; the caller applies it via
    /// TTextEditApplier.Apply (inherits that applier's ANSI/CRLF/.bak
    /// discipline unchanged -- this unit performs no I/O of its own beyond the
    /// read). Removal rules, applied only within a contiguous run of ///
    /// lines (a "doc region"):
    /// 1. A line carrying AUTO_MARK inside a &lt;summary&gt;/&lt;param
    ///    ...&gt;/&lt;returns&gt; tag: drop it, and any following ///
    ///    continuation lines up to and including the one carrying the
    ///    matching close tag (a marked tag can span lines via EmitTagged).
    ///    EXCEPTION (v(ADP3 T3) review round 2, Finding 1 -- param-only): a
    ///    marked &lt;param&gt; whose post-marker body is NON-EMPTY is left
    ///    completely untouched instead -- `document --apply` now preserves
    ///    that exact shape (a human edited inside the tag without removing
    ///    the marker), so strip must agree and never destroy it. A marked
    ///    &lt;summary&gt;/&lt;returns&gt; is always dropped regardless of
    ///    content -- marked means engine-owned for those two, full stop.
    /// 2. A line carrying AUTO_BEGIN: drop it through the line carrying
    ///    AUTO_END, inclusive.
    /// 3. Legacy: a line whose trimmed form ends with AUTO_PARAM -- drop it
    ///    (pre-v(ADP3) managed param; declaration-only elsewhere, this rule is
    ///    its only remaining consumer, kept so an old file self-heals).
    /// 4. If rules 1-3 ACTUALLY DELETED SOMETHING inside a
    ///    &lt;remarks&gt;/&lt;/remarks&gt; pair, and nothing non-blank
    ///    survives between them afterward, drop that pair too. Both halves
    ///    of the test matter: a pair rules 1-3 never touched at all -- e.g. a
    ///    hand-written empty pair, or one whose only interior line is a bare
    ///    '///' -- is left completely alone, tags and any interior content
    ///    together, rather than deleting the tags around content that was
    ///    never engine-owned in the first place.
    /// 5. If the above leaves a doc region with no /// lines at all, the
    ///    region is already fully covered by the ranges above -- no
    ///    additional edit is needed, and no stray blank line is introduced
    ///    (the deletions cover exactly the /// lines, never the blank line
    ///    that separated the region from surrounding code).
    /// A malformed marker (e.g. AUTO_BEGIN with no matching AUTO_END in the
    /// same region, or AUTO_MARK not immediately inside a recognized opening
    /// tag) is left untouched -- absence over a wrong removal.</summary>
    /// <param name="AFilePath">Path to the .pas file to scan; must exist.</param>
    /// <returns>FilePath echoed back, TagsRemoved/BlocksRemoved counts, and
    /// the computed Edits (tekDeleteLines ranges, ascending by line). Edits
    /// is empty when AFilePath carries no engine-owned content, or does not
    /// exist.</returns>
    class function StripFile(const AFilePath: string): TStripResult;

    /// <summary>Same removal rules as StripFile, scoped to the ONE doc region
    /// immediately above source line ADeclLine -- every OTHER doc region in
    /// the file is left untouched. Used by `document --qname X --strip`, so
    /// stripping one symbol's comment never disturbs another declaration's doc
    /// region in the same file. The region qualifies when it ends on the line
    /// directly above ADeclLine, or when exactly one intervening line separates
    /// them AND that line is BLANK. v(ADP3 T3j, register S1): the blank test
    /// is load-bearing -- without it a doc block above a DOCUMENTED declaration
    /// X was claimed by an UNDOCUMENTED declaration Y on the very next line,
    /// and `--qname Y --strip` deleted X's block. A non-blank intervening line
    /// means the region belongs to whatever is on that line.</summary>
    /// <param name="AFilePath">Path to the .pas file to scan; must exist.</param>
    /// <param name="ADeclLine">1-based source line of the target symbol's
    /// declaration (e.g. TSymbol.StartLine).</param>
    /// <param name="ARegionStartLine">v(ADP3 T3d2 D8 review, Critical 1):
    /// 1-based first line of the matched /// region, or 0 if none was found.
    /// Exposed so a caller resolving MULTIPLE declarations that share one
    /// qualified name can detect when two different ADeclLine values resolved
    /// to the SAME physical region and de-duplicate before applying, instead
    /// of queuing the identical delete twice -- the applier has no overlap
    /// detection, so the same delete applied twice removes whatever shifted up
    /// into the freed range. v(ADP3 T3j): the consecutive-declaration shape
    /// that originally motivated this is now REFUSED outright by the blank
    /// test above, so that particular collision can no longer arise -- but the
    /// out param and the caller's de-duplication remain the only protection
    /// against a duplicate delete from any other source (e.g. two index rows
    /// sharing one StartLine), so neither is redundant.</param>
    /// <param name="ARegionEndLine">1-based last line of the matched region,
    /// or 0 if none was found.</param>
    /// <returns>Same shape as StripFile, but Edits (and the Tags/Blocks
    /// counts) cover only the single doc region above ADeclLine; empty when
    /// no such region is found.</returns>
    class function StripSymbolRegion(const AFilePath: string; ADeclLine: Integer;
      out ARegionStartLine, ARegionEndLine: Integer): TStripResult;
  end;

implementation

uses
  System.IOUtils, System.StrUtils,
  DRagLint.Doc.Regions; // AUTO_MARK / AUTO_BEGIN / AUTO_END / AUTO_PARAM (Task 1)

// True when S is a doc-comment line: its trimmed form starts with '///'.
// Matches every other line-oriented /// scan in this codebase (e.g. the
// run_doc_multiline.ps1 runner's own OrphanDocLines check) -- lenient on
// whitespace after the slashes.
function IsDocLine(const S: string): Boolean;
begin
  Result:= StartsStr('///', TrimLeft(S));
end;

// v(ADP3 T3j, register S1): True when 1-based source line ALine1Based exists in
// ALines and holds nothing but whitespace. Bounds-checked deliberately:
// StripSymbolRegion's only caller derives ALine1Based from a caller-supplied
// ADeclLine (a TSymbol.StartLine), so an out-of-range value must read as
// NOT blank -- absence over a wrong removal, the same rule this unit's
// malformed-marker handling already follows.
function IsBlankSourceLine(ALines: TStrings; ALine1Based: Integer): Boolean;
begin
  Result:= (ALine1Based >= 1) and (ALine1Based <= ALines.Count)
           and (Trim(ALines[ALine1Based - 1]) = '');
end;

// Content of a /// line with the leading '///' marker (and any following
// whitespace) removed, then trimmed. Used only to test a line's PAYLOAD
// against an exact tag string (e.g. '<remarks>') without the comment prefix
// getting in the way.
function DocLineContent(const S: string): string;
var
  T: string;
begin
  T:= TrimLeft(S);
  if StartsStr('///', T) then T:= Copy(T, 4, MaxInt);
  Result:= Trim(T);
end;

// Given ALine (the FULL line text, comment prefix included) and the 1-based
// position of an AUTO_MARK occurrence within it, returns the closing tag text
// ('</summary>' / '</param>' / '</returns>') implied by the OPENING tag that
// immediately precedes the marker -- AUTO_MARK always sits right after the
// opening tag's '>' (see TDocRegions.MergeComment's EmitTagged calls), so the
// text up to (not including) the marker's position always ENDS with the
// opening tag. Returns '' when the preceding text does not end with one of
// the three recognized openers -- a marker in an unrecognized position is
// left untouched by the caller (absence over a wrong removal).
function ManagedTagCloser(const ALine: string; AMarkPos: Integer): string;
var
  Prefix: string;
begin
  Prefix:= Copy(ALine, 1, AMarkPos - 1);
  if EndsText('<summary>', Prefix) then Result:= '</summary>'
  else if EndsText('<returns>', Prefix) then Result:= '</returns>'
  else if EndsText('>', Prefix) and (Pos('<param', Prefix) > 0) then Result:= '</param>'
  else Result:= '';
end;

// v(ADP3 T3 review round 2, point 2): true when the tag body between the
// marker (ending at column AFrom on line ALines[ALo]) and the FIRST
// occurrence of ACloser (searched across ALo..AHi, each line after ALo
// normalized via DocLineContent -- /// prefix stripped, trimmed) is empty or
// whitespace-only. A single-line tag reduces to this same check (ALo = AHi
// collapses the loop to a no-op, so the "self-contained" and "multi-line"
// shapes share one implementation). Used only by Rule 1's <param> exception
// below -- <summary>/<returns> are stripped unconditionally regardless of
// what this returns, matching `document --apply`'s own marked-always-means-
// engine-owned rule for those two tags.
function TagBodyIsEmpty(ALines: TStrings; ALo, AHi, AFrom: Integer; const ACloser: string): Boolean;
var
  Combined : string;
  K, ClosePos: Integer;
begin
  Combined:= Copy(ALines[ALo], AFrom, MaxInt);
  for K:= ALo + 1 to AHi do
    Combined:= Combined + ' ' + DocLineContent(ALines[K]);
  ClosePos:= Pos(ACloser, Combined);
  if ClosePos > 0 then Combined:= Copy(Combined, 1, ClosePos - 1);
  Result:= Trim(Combined) = '';
end;

// Applies removal rules 1-4 to the doc region ALines[ALo..AHi] (0-based,
// inclusive), setting ADeleted[i] := True for every line the region loses.
// ADeleted must already be sized to ALines.Count. Mutates ATagsRemoved /
// ABlocksRemoved (rules 1+3 and rule 2 respectively). Rule 5 needs no
// separate step here: when rules 1-4 delete every line in the region, the
// per-line ranges they produce already cover the WHOLE region -- there is no
// additional blank-line artifact to clean up, because the region by
// definition contains only /// lines (a blank line breaks the contiguous
// run that defines a region in the first place).
procedure StripRegion(ALines: TStrings; ALo, AHi: Integer;
  var ADeleted: TArray<Boolean>; var ATagsRemoved, ABlocksRemoved: Integer);
var
  I, J, K    : Integer;
  Line       : string;
  MarkPos    : Integer;
  Closer     : string;
  RemarksOpen: Integer;
  Empty      : Boolean;
  AnyDeleted : Boolean;
begin
  I:= ALo;
  while I <= AHi do
  begin
    Line:= ALines[I];

    // Rule 2: AUTO_BEGIN .. AUTO_END, inclusive.
    if Pos(AUTO_BEGIN, Line) > 0 then
    begin
      J:= I;
      while (J <= AHi) and (Pos(AUTO_END, ALines[J]) = 0) do Inc(J);
      if J <= AHi then
      begin
        for K:= I to J do ADeleted[K]:= True;
        Inc(ABlocksRemoved);
        I:= J + 1;
      end
      else Inc(I); // malformed: BEGIN with no END in this region -- leave alone
      Continue;
    end;

    // Rule 3: legacy trailing AUTO_PARAM sentinel -- whole line dropped.
    if EndsStr(AUTO_PARAM, TrimRight(Line)) then
    begin
      ADeleted[I]:= True;
      Inc(ATagsRemoved);
      Inc(I);
      Continue;
    end;

    // Rule 1: a marked <summary>/<param>/<returns> tag, single- or multi-line.
    MarkPos:= Pos(AUTO_MARK, Line);
    if MarkPos > 0 then
    begin
      Closer:= ManagedTagCloser(Line, MarkPos);
      if Closer <> '' then
      begin
        // Unified single-line/multi-line search: J = I already satisfies
        // "self-contained on this line" (Pos(Closer, ALines[I]) > 0), so one
        // forward search from I handles both shapes identically.
        J:= I;
        while (J <= AHi) and (Pos(Closer, ALines[J]) = 0) do Inc(J);
        if J <= AHi then
        begin
          // v(ADP3 T3 review round 2, point 2): --strip must agree with
          // `document --apply`'s param-only exception (Finding 1) -- a
          // marked <param> whose post-marker body is non-empty is now
          // PRESERVED (marker stripped) by the write path, not owned by the
          // engine; strip must leave it COMPLETELY alone (marker included)
          // too, or the two verbs diverge (apply keeps the text, strip
          // deletes the whole tag). <summary>/<returns> are UNCHANGED:
          // marked always means engine-owned there, stripped
          // unconditionally regardless of content.
          if SameText(Closer, '</param>')
             and (not TagBodyIsEmpty(ALines, I, J, MarkPos + Length(AUTO_MARK), Closer)) then
          begin
            I:= J + 1;
            Continue;
          end;
          for K:= I to J do ADeleted[K]:= True;
          Inc(ATagsRemoved);
          I:= J + 1;
        end
        else Inc(I); // malformed: no matching close tag in this region -- leave alone
        Continue;
      end;
    end;

    Inc(I); // ordinary /// content (hand-written, or a marker outside a recognized tag) -- kept
  end;

  // Rule 4: an emptied <remarks>/</remarks> pair (open+close tags each alone
  // on their own line, matching TDocRegions.MergeComment's own rendering) --
  // drop the pair too, but ONLY when rules 1-3 ABOVE actually deleted
  // something inside it (AnyDeleted) AND nothing non-blank survives (Empty).
  // Review fix: the ORIGINAL code dropped the pair whenever nothing NON-BLANK
  // remained, with no check that anything was ever deleted there at all --
  // so a file the engine had NEVER touched, carrying a hand-written
  // '<remarks>'/'</remarks>' pair with nothing (or only a bare '///' line)
  // between them, lost BOTH tag lines on --strip: the engine deleting
  // hand-written source, exactly what this unit's own contract forbids. The
  // AnyDeleted gate restores the brief's own conditional wording -- "IF
  // DROPPING leaves a pair with nothing between them" presupposes something
  // was dropped -- and its absence is also what let a bare interior '///'
  // line end up ORPHANED (tags removed around it, the harmless-looking bare
  // line never marked deleted itself): with nothing genuinely AUTO-owned
  // inside, AnyDeleted stays False, the whole pair (tags AND any interior
  // content, bare or not) is left completely alone.
  RemarksOpen:= -1;
  for I:= ALo to AHi do
  begin
    if ADeleted[I] then Continue;
    if (RemarksOpen = -1) and SameText(DocLineContent(ALines[I]), '<remarks>') then
      RemarksOpen:= I
    else if (RemarksOpen <> -1) and ContainsText(DocLineContent(ALines[I]), '</remarks>') then
    begin
      Empty:= True;
      AnyDeleted:= False;
      for J:= RemarksOpen + 1 to I - 1 do
      begin
        AnyDeleted:= AnyDeleted or ADeleted[J];
        if (not ADeleted[J]) and (DocLineContent(ALines[J]) <> '') then
        begin
          Empty:= False;
          Break;
        end;
      end;
      if Empty and AnyDeleted then
      begin
        ADeleted[RemarksOpen]:= True;
        ADeleted[I]:= True;
      end;
      RemarksOpen:= -1;
    end;
  end;
end;

// Converts a per-line Deleted flag array into maximal contiguous
// tekDeleteLines ranges (1-based, ascending by line).
function BuildDeleteEdits(const AFilePath: string; const ADeleted: TArray<Boolean>): TArray<TTextEdit>;
var
  I, Lo: Integer;
  E    : TTextEdit;
begin
  Result:= nil;
  I:= 0;
  while I < Length(ADeleted) do
  begin
    if ADeleted[I] then
    begin
      Lo:= I;
      while (I + 1 < Length(ADeleted)) and ADeleted[I + 1] do Inc(I);
      E:= Default(TTextEdit);
      E.FilePath:= AFilePath;
      E.Kind    := tekDeleteLines;
      E.Line    := Lo + 1;
      E.EndLine := I + 1;
      Result:= Result + [E];
    end;
    Inc(I);
  end;
end;

// Loads AFilePath the same way TDocumenter.BuildForSymbol does (ANSI byte
// read, no BOM/codepage sniffing) into a TStringList, so line numbering here
// matches exactly what TTextEditApplier.Apply will re-derive when it loads
// the same file for the actual write (also via TStringList.Text) -- the two
// must agree, or a computed Line/EndLine would delete the wrong physical
// lines. Returns False (ALines untouched) when the file does not exist.
function TryLoadLines(const AFilePath: string; ALines: TStringList): Boolean;
var
  Content: string;
begin
  Result:= TFile.Exists(AFilePath);
  if not Result then Exit;
  Content:= TEncoding.ANSI.GetString(TFile.ReadAllBytes(AFilePath));
  ALines.Text:= Content;
end;

class function TDocStripper.StripFile(const AFilePath: string): TStripResult;
var
  Lines  : TStringList;
  Deleted: TArray<Boolean>;
  I, Lo, Hi: Integer;
begin
  Result:= Default(TStripResult);
  Result.FilePath:= AFilePath;

  Lines:= TStringList.Create;
  try
    if not TryLoadLines(AFilePath, Lines) then Exit;

    SetLength(Deleted, Lines.Count);
    I:= 0;
    while I < Lines.Count do
    begin
      if IsDocLine(Lines[I]) then
      begin
        Lo:= I; Hi:= I;
        while (Hi + 1 < Lines.Count) and IsDocLine(Lines[Hi + 1]) do Inc(Hi);
        StripRegion(Lines, Lo, Hi, Deleted, Result.TagsRemoved, Result.BlocksRemoved);
        I:= Hi + 1;
      end
      else Inc(I);
    end;

    Result.Edits:= BuildDeleteEdits(AFilePath, Deleted);
  finally
    Lines.Free;
  end;
end;

class function TDocStripper.StripSymbolRegion(const AFilePath: string; ADeclLine: Integer;
  out ARegionStartLine, ARegionEndLine: Integer): TStripResult;
var
  Lines  : TStringList;
  Deleted: TArray<Boolean>;
  I, Lo, Hi, RegionLo, RegionHi: Integer;
  Found  : Boolean;
begin
  Result:= Default(TStripResult);
  Result.FilePath:= AFilePath;
  // v(ADP3 T3d2 D8 review, Critical 1): explicit zero, not relying on `out`
  // parameter default-initialization -- Integer is an unmanaged type, so an
  // `out Integer` parameter is NOT implicitly zeroed the way a managed local
  // (string/interface) would be. 0 means "no region matched", agreeing with
  // every early-exit path below.
  ARegionStartLine:= 0;
  ARegionEndLine  := 0;

  Lines:= TStringList.Create;
  try
    if not TryLoadLines(AFilePath, Lines) then Exit;

    // Find the contiguous /// region immediately above ADeclLine, allowing a
    // single BLANK-line gap. Hi + 1 is the region's 1-based end line, so the
    // two accepted cases are exhaustive over the integer window
    // [ADeclLine-2, ADeclLine-1]:
    //   * Hi + 1 = ADeclLine - 1 -- the region ends directly above the
    //     declaration. Always correct, and unchanged here.
    //   * Hi + 1 = ADeclLine - 2 -- exactly ONE line intervenes, at 1-based
    //     line ADeclLine - 1, and it MUST be blank.
    //
    // v(ADP3 T3j, register S1): the blank test is the fix. The window alone
    // used to accept the gap case without ever looking at the intervening
    // line, so for a DOCUMENTED declaration X immediately followed by an
    // UNDOCUMENTED declaration Y, evaluating Y gave the window
    // [XLine-1, XLine] and X's region ends at XLine-1: it matched, and
    // `document --qname Y --strip` deleted X's block. The "gap" it tolerated
    // was declaration X itself. Adjacent declarations are the ordinary Delphi
    // idiom (311 same-qualified-name pairs within one line measured in the real
    // ORM3 index), and "documented X, undocumented Y below it" is just the
    // normal state of a partially-documented class, so this needed no
    // contrivance to reach. Pinned by tests\autodoc\run_doc_p3_strip_wrongsymbol.ps1.
    //
    // This is the same defect class TDocumenter's own FindDocRegionAbove was
    // fixed for (adp2-docregion-fix), and it is the reason THIS comment no
    // longer claims to share that function's tolerance: FindDocRegionAbove
    // guards the window with an INTERVENING-DECLARATION check driven by every
    // symbol's StartLine from the index (see its header in
    // DRagLint.Core.Indexer / DRagLint.Doc.Document). That guard is strictly
    // stronger, but it is unavailable here by design -- this unit is a raw-line
    // scan with no index (see the unit header), and StripSymbolRegion receives
    // one ADeclLine, not the file's symbol table. The blank test is the
    // index-free equivalent: a non-blank intervening line means the region
    // belongs to whatever is ON that line, not to ADeclLine. It is narrower
    // than the declaration check only for a non-blank intervening line that is
    // NOT a declaration (e.g. an ordinary '//' comment), where this refuses a
    // region FindDocRegionAbove would allow -- refusing to delete is the safe
    // direction for a function that removes lines from a user's source.
    Found:= False;
    RegionLo:= 0; RegionHi:= 0;
    I:= 0;
    while I < Lines.Count do
    begin
      if IsDocLine(Lines[I]) then
      begin
        Lo:= I; Hi:= I;
        while (Hi + 1 < Lines.Count) and IsDocLine(Lines[Hi + 1]) do Inc(Hi);
        if (Hi + 1 = ADeclLine - 1)
           or ((Hi + 1 = ADeclLine - 2) and IsBlankSourceLine(Lines, ADeclLine - 1)) then
        begin
          RegionLo:= Lo; RegionHi:= Hi; Found:= True;
        end;
        I:= Hi + 1;
      end
      else Inc(I);
    end;
    if not Found then Exit;

    // v(ADP3 T3d2 D8 review, Critical 1): 0-based array indices -> 1-based
    // line numbers, matching every other line number this unit exposes.
    ARegionStartLine:= RegionLo + 1;
    ARegionEndLine  := RegionHi + 1;

    SetLength(Deleted, Lines.Count);
    StripRegion(Lines, RegionLo, RegionHi, Deleted, Result.TagsRemoved, Result.BlocksRemoved);
    Result.Edits:= BuildDeleteEdits(AFilePath, Deleted);
  finally
    Lines.Free;
  end;
end;

end.
