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
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoDocumentStripQName (DRagLint.CLI.pas), DRagLint.Doc.Batch.TDocBatch.DocumentUnit (DRagLint.Doc.Batch.pas), declaration (DRagLint.Doc.Strip.pas), DRagLint.Doc.Strip.TDocStripper.StripFile (DRagLint.Doc.Strip.pas), DRagLint.Doc.Strip.TDocStripper.StripSymbolRegion (DRagLint.Doc.Strip.pas)
  /// Used in units: DRagLint.CLI, DRagLint.Doc.Batch, DRagLint.Doc.Strip
  /// <!-- drag-lint:auto END -->
  /// </remarks>
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
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoDocumentStripQName (DRagLint.CLI.pas), DRagLint.Doc.Batch.TDocBatch.DocumentUnit (DRagLint.Doc.Batch.pas)
  /// Used in units: DRagLint.CLI, DRagLint.Doc.Batch
  /// <!-- drag-lint:auto END -->
  /// </remarks>
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
    /// ...&gt;/&lt;returns&gt; tag: drop it, and any following ///
    /// continuation lines up to and including the one carrying the
    /// matching close tag (a marked tag can span lines via EmitTagged).
    /// EXCEPTION (v(ADP3 T3) review round 2, Finding 1 -- param-only): a
    /// marked &lt;param&gt; whose post-marker body is NON-EMPTY is left
    /// completely untouched instead -- `document --apply` now preserves
    /// that exact shape (a human edited inside the tag without removing
    /// the marker), so strip must agree and never destroy it. A marked
    /// &lt;summary&gt;/&lt;returns&gt; is always dropped regardless of
    /// content -- marked means engine-owned for those two, full stop.
    /// 2. A line carrying AUTO_BEGIN: drop it through the line carrying
    /// AUTO_END, inclusive.
    /// 3. Legacy: a line whose trimmed form ends with AUTO_PARAM -- drop it
    /// (pre-v(ADP3) managed param; declaration-only elsewhere, this rule is
    /// its only remaining consumer, kept so an old file self-heals).
    /// 4. If rules 1-3 ACTUALLY DELETED SOMETHING inside a
    /// &lt;remarks&gt;/&lt;/remarks&gt; pair, and nothing non-blank
    /// survives between them afterward, drop that pair too. Both halves
    /// of the test matter: a pair rules 1-3 never touched at all -- e.g. a
    /// hand-written empty pair, or one whose only interior line is a bare
    /// '///' -- is left completely alone, tags and any interior content
    /// together, rather than deleting the tags around content that was
    /// never engine-owned in the first place.
    /// 5. If the above leaves a doc region with no /// lines at all, the
    /// region is already fully covered by the ranges above -- no
    /// additional edit is needed, and no stray blank line is introduced
    /// (the deletions cover exactly the /// lines, never the blank line
    /// that separated the region from surrounding code).
    /// A malformed marker (e.g. AUTO_BEGIN with no matching AUTO_END in the
    /// same region, or AUTO_MARK not immediately inside a recognized opening
    /// tag) is left untouched -- absence over a wrong removal.</summary>
    /// <param name="AFilePath">Path to the .pas file to scan; must exist.</param>
    /// <returns>FilePath echoed back, TagsRemoved/BlocksRemoved counts, and
    /// the computed Edits (tekDeleteLines ranges, ascending by line). Edits
    /// is empty when AFilePath carries no engine-owned content, or does not
    /// exist.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Doc.Batch.TDocBatch.DocumentUnit (DRagLint.Doc.Batch.pas)
    /// Calls: Default, DRagLint.Doc.Strip.BuildDeleteEdits, DRagLint.Doc.Strip.IsDocLine, DRagLint.Doc.Strip.StripRegion, DRagLint.Doc.Strip.TryLoadLines
    /// Returns: Default(TStripResult)
    /// Pure
    /// <seealso cref="DRagLint.Doc.Strip.BuildDeleteEdits"/>
    /// <seealso cref="DRagLint.Doc.Strip.IsDocLine"/>
    /// <seealso cref="DRagLint.Doc.Strip.StripRegion"/>
    /// <seealso cref="DRagLint.Doc.Strip.TryLoadLines"/>
    /// <seealso cref="DRagLint.Doc.Strip.TDocStripper.StripSymbolRegion"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function StripFile(const AFilePath: string): TStripResult;

    /// <summary>Same removal rules as StripFile, scoped to the ONE doc region
    /// immediately above source line ADeclLine -- every OTHER doc region in
    /// the file is left untouched. Used by `document --qname X --strip`, so
    /// stripping one symbol's comment never disturbs another declaration's doc
    /// region in the same file. Attribution uses the SHARED predicate
    /// DRagLint.Core.Model.DocRegionFitsDecl, the same one
    /// `document --apply`'s TDocumenter.FindDocRegionAbove reads, so what the
    /// write path claims is exactly what this removes.</summary>
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
    /// into the freed range. v(ADP3 T3j, corrected in review round 2): the
    /// consecutive-declaration shape that originally motivated this is now
    /// refused by the SHARED INTERVENING-DECLARATION GUARD (the second overload
    /// finds the first's own declaration line inside its gap), and, for a caller
    /// with no symbol table, by the blank-line fallback described under
    /// ASymStartLines below -- so that particular collision can no longer arise
    /// on either branch. But the out param and the caller's de-duplication
    /// remain the only protection against a duplicate delete from any other
    /// source (e.g. two index rows sharing one StartLine), so neither is
    /// redundant.</param>
    /// <param name="ARegionEndLine">1-based last line of the matched region,
    /// or 0 if none was found.</param>
    /// <param name="ASymStartLines">v(ADP3 T3j review round 1): every symbol's
    /// 1-based StartLine in AFilePath, INCLUDING ADeclLine's own, sorted
    /// ASCENDING -- exactly what `document --apply` passes its own
    /// FindDocRegionAbove. Supplying it makes this function's attribution
    /// IDENTICAL to the write path's, which is the invariant that matters: a
    /// region the write path claims must be a region this can remove, or
    /// `--apply` writes a block `--strip` can never take back.
    /// <para>MAY be empty, for a caller with no symbol table -- this unit is
    /// deliberately index-free (see the unit header) and must stay usable
    /// without one. v(ADP3 T3j review round 2, folded 4): passing it is
    /// REQUIRED, with no `= nil` default, deliberately. A default would have
    /// made the NARROWER fallback the silent choice for any future caller that
    /// simply did not think about it, on a code path that deletes lines from a
    /// user's source and with no committed test on that branch. Being forced to
    /// write the argument is the compile-time nudge to consider which
    /// attribution rule you want. When it IS empty the declaration test is
    /// vacuous, so
    /// a FALLBACK applies instead: a one-line gap is accepted only when that
    /// line is BLANK. That is deliberately NARROWER than the write path (it
    /// refuses an ordinary comment in the gap, which the write path tolerates),
    /// because with no symbol table there is no way to tell a comment from a
    /// declaration, and on a code path that DELETES lines from a user's source
    /// the safe direction is to refuse. Prefer passing the lines.</para></param>
    /// <returns>Same shape as StripFile, but Edits (and the Tags/Blocks
    /// counts) cover only the single doc region above ADeclLine; empty when
    /// no such region is found.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoDocumentStripQName (DRagLint.CLI.pas)
    /// Calls: Default, DRagLint.Core.Model.DocRegionFitsDecl, DRagLint.Core.Model.DocRegionInGapWindow, DRagLint.Doc.Strip.BuildDeleteEdits, DRagLint.Doc.Strip.IsBlankSourceLine, DRagLint.Doc.Strip.IsDocLine, DRagLint.Doc.Strip.StripRegion, DRagLint.Doc.Strip.TryLoadLines
    /// Returns: Default(TStripResult)
    /// Complexity: 11 (cyclomatic, outer body), 95 lines (full implementation)
    /// Mutates: ARegionStartLine (out), ARegionEndLine (out)
    /// <seealso cref="DRagLint.Core.Model.DocRegionFitsDecl"/>
    /// <seealso cref="DRagLint.Core.Model.DocRegionInGapWindow"/>
    /// <seealso cref="DRagLint.Doc.Strip.BuildDeleteEdits"/>
    /// <seealso cref="DRagLint.Doc.Strip.IsBlankSourceLine"/>
    /// <seealso cref="DRagLint.Doc.Strip.IsDocLine"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function StripSymbolRegion(const AFilePath: string; ADeclLine: Integer;
      out ARegionStartLine, ARegionEndLine: Integer;
      const ASymStartLines: TArray<Integer>): TStripResult;
  end;

implementation

uses
  System.IOUtils, System.StrUtils,
  DRagLint.Doc.Regions, // AUTO_MARK / AUTO_BEGIN / AUTO_END / AUTO_PARAM (Task 1)
  // v(ADP3 T3j review round 1): DOC_ALLOW_GAP + the SHARED attribution
  // predicate (DocRegionFitsDecl / DocRegionInGapWindow) that the
  // `document --apply` write path reads too. Core.Model is types-and-pure-
  // functions only (its own uses clause is System.SysUtils alone), so this does
  // NOT give the unit an index dependency -- the property the unit header calls
  // out is preserved.
  DRagLint.Core.Model;

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

    // Rule 1b (v(ADP3 T7)): HARVESTED REMARKS PROSE -- a marked line that is
    // NOT a tag. TDocRegions.EmitHarvestedRemarks writes the harvested comment's
    // second-and-later paragraphs inside <remarks> and ABOVE the AUTO_BEGIN
    // fence, with AUTO_MARK on the FIRST line only. That shape matches neither
    // rule 1 (no recognized opening tag precedes the marker, so ManagedTagCloser
    // returns '') nor rule 2 (no fence), so before this rule the write path
    // produced something --strip could not undo: MEASURED on
    // fixtures/docp3/harvest_text.pas -- apply then strip left the marked prose
    // line and an orphaned <remarks>/</remarks> pair behind, with one
    // drag-lint:auto marker surviving a verb whose whole contract is that none
    // do.
    //
    // The run ends at the first following line that opens or closes a TAG, or
    // that carries the fence -- i.e. at </remarks> or AUTO_BEGIN. Nothing
    // hand-written can be caught by that: MergeComment emits preserved hand
    // prose ABOVE this block, never below it, so everything between the marked
    // line and the next tag is engine-written continuation (including the bare
    // /// paragraph separators, whose content is empty).
    //
    // Counted as a BLOCK, not a tag: it is a contiguous engine-owned region
    // like the fence, and no <tag> was removed.
    if (MarkPos > 0) and (Pos(AUTO_MARK, DocLineContent(Line)) = 1) then
    begin
      J:= I + 1;
      while (J <= AHi) do
      begin
        var C: string:= DocLineContent(ALines[J]);
        if C.StartsWith('<') or (Pos(AUTO_BEGIN, ALines[J]) > 0) or (Pos(AUTO_END, ALines[J]) > 0) then Break;
        Inc(J);
      end;
      for K:= I to J - 1 do ADeleted[K]:= True;
      Inc(ABlocksRemoved);
      I:= J;
      Continue;
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
  out ARegionStartLine, ARegionEndLine: Integer;
  const ASymStartLines: TArray<Integer>): TStripResult;
var
  Lines  : TStringList;
  Deleted: TArray<Boolean>;
  I, Lo, Hi, RegionLo, RegionHi: Integer;
  Found  : Boolean;
  Fits   : Boolean;
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

    // Find the contiguous /// region immediately above ADeclLine. Hi is a
    // 0-based array index, so Hi + 1 is the region's 1-based END line.
    //
    // v(ADP3 T3j, register S1 -- and its review round 1, which CHANGED the
    // predicate): attribution is the SHARED DocRegionFitsDecl from
    // DRagLint.Core.Model, which is the very same predicate
    // `document --apply`'s TDocumenter.FindDocRegionAbove reads.
    //
    // The original defect: this code carried its own inline copy of
    // FindDocRegionAbove's WINDOW and omitted its GUARD, while a comment here
    // claimed it tolerated "the same gap". So for a DOCUMENTED declaration X
    // immediately followed by an UNDOCUMENTED declaration Y, evaluating Y gave
    // the window [XLine-1, XLine], X's region ends at XLine-1, it matched, and
    // `document --qname Y --strip` DELETED X's block -- the "gap" it tolerated
    // was declaration X itself. Adjacent declarations are the ordinary Delphi
    // idiom (311 same-qualified-name pairs within one line in the real ORM3
    // index), and "documented X, undocumented Y below it" is just the normal
    // state of a partially-documented class.
    //
    // The FIRST fix required the gap line to be BLANK. That closed the defect
    // but introduced a worse one: the write path's real predicate is "no OTHER
    // DECLARATION in the gap", not "the gap is blank", so it deliberately
    // tolerates an ordinary comment there. Requiring blankness made --strip
    // NARROWER than --apply, which means `--apply` could write a block
    // `--strip` would then refuse to remove -- an apply/strip asymmetry, i.e. a
    // permanently unremovable engine block. Reading the same predicate as the
    // write path is what actually preserves the round-trip, and sharing one
    // declaration is what stops the two from drifting again.
    //
    // FALLBACK, when ASymStartLines is empty (a caller with no symbol table --
    // this unit is deliberately index-free): the declaration test would be
    // vacuous, so require the one-line gap to be BLANK instead. Narrower than
    // the write path on purpose -- with no symbol table a comment and a
    // declaration are indistinguishable, and refusing is the safe direction for
    // code that deletes lines from a user's source. Both branches are pinned by
    // tests\autodoc\run_doc_p3_strip_wrongsymbol.ps1.
    Found:= False;
    RegionLo:= 0; RegionHi:= 0;
    I:= 0;
    while I < Lines.Count do
    begin
      if IsDocLine(Lines[I]) then
      begin
        Lo:= I; Hi:= I;
        while (Hi + 1 < Lines.Count) and IsDocLine(Lines[Hi + 1]) do Inc(Hi);
        if Length(ASymStartLines) > 0 then
          Fits:= DocRegionFitsDecl(Hi + 1, ADeclLine, DOC_ALLOW_GAP, ASymStartLines)
        else
          Fits:= DocRegionInGapWindow(Hi + 1, ADeclLine, DOC_ALLOW_GAP)
                 and ((Hi + 1 = ADeclLine - 1) or IsBlankSourceLine(Lines, ADeclLine - 1));
        if Fits then
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
