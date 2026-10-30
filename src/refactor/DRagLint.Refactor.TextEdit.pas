unit DRagLint.Refactor.TextEdit;

{ Range insert/delete text edits for the non-rename refactors (find-unit,
  safe-delete). TRenameRefactoring.Apply is token-replace only; this applier
  does whole-line insert/delete + single-line character insert, keeping each
  file's encoding / BOM / line-break style (TTextFileFormat) and the .bak
  discipline. Builders (TFindUnitRefactoring, TSafeDelete-
  Refactoring) are added in later tasks. }

interface

uses
  System.SysUtils, System.Classes, System.IOUtils,
  System.Generics.Collections, System.Generics.Defaults,
  DRagLint.Core.Interfaces;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Refactor.TextEdit.pas), DRagLint.CLI.CycleFix.ToTextEdits.Make (DRagLint.CLI.CycleFix.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTextEditKind = (tekInsertInLine, tekInsertLines, tekDeleteLines, tekReplaceInLine, tekReplaceLines);

  /// <summary>One text edit. tekInsertInLine: insert Text into line Line at
  /// 1-based column Col. tekInsertLines: insert Text (CRLF-joined) after line
  /// Line (0 = top). tekDeleteLines: delete lines Line..EndLine inclusive.
  /// tekReplaceInLine: on line Line, replace the characters in 1-based columns
  /// [Col, EndCol) (EndCol exclusive) with Text (Text may be '' to delete).
  /// tekReplaceLines: replace lines Line..EndLine inclusive with Text, which may
  /// span lines (CRLF- or LF-separated; '' leaves one empty line).</summary>
  /// <remarks>
  /// ExpectText is the OPTIONAL stale-position guard for
  /// tekReplaceInLine (ignored by every other kind). When it is non-empty the
  /// applier verifies -- case-insensitively, Delphi identifiers being
  /// case-insensitive -- that the file AS IT IS ON DISK really holds ExpectText
  /// at [Col, EndCol) of line Line, and DROPS the edit when it does not.
  /// Producers whose coordinates come from the SYMBOL STORE (a snapshot that
  /// goes stale the moment the file is edited) must set it; leaving it '' keeps
  /// the historical unguarded behaviour for every existing caller.
  /// v(PHASE A2): ExpectLine extends the SAME guard to the line kinds
  /// (tekInsertLines / tekDeleteLines), which had none at all -- see
  /// AnchorIsValid for what it verifies and why a substring test alone is not
  /// enough. Set BOTH fields to arm it; ExpectLine = 0 is unguarded.
  /// tekReplaceLines (autofix wave A0, 2026-10-27): a non-empty ExpectText must
  /// EQUAL (case-sensitively) the current full text of line Line, else the edit
  /// is dropped and counted skipped; the overlap check treats Line..EndLine as a
  /// delete range, so it can never interleave with a delete or another replace.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.NetLineChange (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.StageShadow (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.ToTextEdits (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.ToTextEdits.Make (DRagLint.CLI.CycleFix.pas) (+81 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.CLI.CycleFix, DRagLint.Convert.Apply, DRagLint.Convert.UnitRules, DRagLint.Diagnostics.AstChecks, DRagLint.Doc.Batch, DRagLint.Doc.Document, DRagLint.Doc.Strip, DRagLint.Lint.DocRules, DRagLint.Refactor.EnumHelper, DRagLint.Refactor.ExtractMethod, DRagLint.Refactor.MultiProjectRename, DRagLint.Refactor.NamingFix, DRagLint.Refactor.TextEdit</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTextEdit = record
    FilePath  : string;
    Kind      : TTextEditKind;
    Line      : Integer;
    Col       : Integer;
    EndCol    : Integer;      { tekReplaceInLine: 1-based exclusive end column }
    EndLine   : Integer;
    Text      : string;
    ExpectText: string;       { tekReplaceInLine: the span guard; with ExpectLine: the anchor guard }
    ExpectLine: Integer;      { 1-based ANCHOR line that must still hold ExpectText; 0 = unguarded }
    Owner     : string;       { the finding that produced it (FixOwnerKey); '' = unattributed }
    AtomGroup : string;       { edits sharing it apply all-or-nothing; '' = the Owner is the group (EditAtomKey) }
  end;

  /// <summary>How a text file was stored on disk -- its encoding, its BOM and
  /// its line-break style -- so a tool that rewrites the file writes it back
  /// the same way (deep review F8, 2026-10-25).</summary>
  /// <remarks>
  /// A UTF-8 or UTF-16 BOM selects that encoding and is kept. A file with no
  /// BOM whose bytes include a high byte AND are valid UTF-8 (IsValidUtf8, the
  /// indexer's own rule) is UTF-8 without a BOM, and is written back without
  /// one (W5-D, 2026-10-25). Any other BOM-less file -- pure ASCII, or high
  /// bytes that are not valid UTF-8 -- is ANSI (the system code page), exactly
  /// as before, so a plain ANSI file round-trips byte-identical. LineBreak is
  /// LF only when the text holds an LF and no CRLF; otherwise (CRLF, mixed, or
  /// no line break at all) it is CRLF, the historical output. Encoding is an
  /// RTL standard singleton -- never owned, never freed.
  /// </remarks>
  TTextFileFormat = record
    Encoding : TEncoding;  { ANSI, UTF8, Unicode or BigEndianUnicode singleton }
    Preamble : TBytes;     { the BOM read from the file; empty when it had none }
    LineBreak: string;     { #13#10 or #10 }
    /// <summary>Decodes a file's bytes and records how they were stored.</summary>
    /// <param name="ABytes">The file's raw bytes (may be empty).</param>
    /// <param name="AText">Out: the text, without the BOM.</param>
    /// <returns>The format to hand to Encode when the text is written back.</returns>
    class function Decode(const ABytes: TBytes; out AText: string): TTextFileFormat; static;
    /// <summary>Reads a file and decodes it as Decode does -- the one reader
    /// every tool that edits a file in place uses, so a column it computes
    /// counts the same characters the writer will write.</summary>
    /// <param name="APath">The file to read.</param>
    /// <param name="AText">Out: the text, without the BOM; '' when the file is missing.</param>
    /// <returns>The file's format; ANSI + CRLF when the file is missing.</returns>
    class function ReadFile(const APath: string; out AText: string): TTextFileFormat; static;
    /// <summary>The line break a rewrite of AText should use: #10 when AText
    /// holds an LF and no CRLF, else #13#10.</summary>
    /// <param name="AText">Text as read from a file.</param>
    /// <returns>#10 or #13#10.</returns>
    class function LineBreakOf(const AText: string): string; static;
    /// <summary>The bytes to write for AText: the original BOM followed by
    /// AText in the original encoding.</summary>
    /// <param name="AText">The text to write; its line breaks are written as given.</param>
    /// <returns>Preamble + Encoding.GetBytes(AText).</returns>
    function Encode(const AText: string): TBytes;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.ApplyDocEditsGuarded (DRagLint.CLI.pas), DRagLint.CLI.CycleFix.StageShadow (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.DoDocumentUnit (DRagLint.CLI.pas), DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas), DRagLint.CLI.ReportStrip (DRagLint.CLI.pas) (+12 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.CLI.CycleFix, DRagLint.Convert.Apply, DRagLint.Refactor.ExtractMethod</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTextEditApplier = class
  private
    class procedure ApplyOneEdit(ALines: TStringList; const AEdit: TTextEdit; var AApplied, ASkippedEdits: Integer);
    class function ApplyGroup(const AFilePath, AContent: string; AGroup: TList<TTextEdit>;
      AQuiet: Boolean; var ASkippedEdits: Integer; out AApplied: Integer): string;
  public
    /// <summary>The text Apply would write for one file, computed in memory
    /// (1.27.0, C9): the same sort, stale-anchor and overlap checks and the
    /// same re-serialisation (in AContent's own line-break style, see
    /// TTextFileFormat.LineBreakOf), without touching the disk.</summary>
    /// <param name="AFilePath">The file the edits target; only edits whose
    /// FilePath equals it (case-insensitively) are applied.</param>
    /// <param name="AContent">The file's current text.</param>
    /// <param name="AEdits">The edit set; edits for other files are ignored.</param>
    /// <returns>The edited text, or AContent unchanged when no edit applies
    /// (Apply would then leave the file alone).</returns>
    /// <remarks>Pure. convert-apply re-indexes this text to reconcile the
    /// converted unit's uses clauses before anything is written.</remarks>
    class function ApplyToText(const AFilePath, AContent: string; const AEdits: TArray<TTextEdit>): string;
    /// <summary>Applies edits per file, back-to-front by line, preserving the
    /// file's encoding, BOM and line-break style (TTextFileFormat) + (optional)
    /// .bak backup. Returns files touched.</summary>
    /// <param name="AEdits"><!-- drag-lint:auto type -->const TArray&lt;TTextEdit&gt;</param>
    /// <param name="AWriteBackups"><!-- drag-lint:auto type -->Boolean</param>
    /// <returns><!-- drag-lint:auto -->Integer -- Observed: Apply(AEdits, AWriteBackups,
    /// Skipped).</returns>
    /// <remarks>
    /// Edits are validated before they are written: a
    /// tekReplaceInLine whose Col lies past end-of-line is REJECTED (it would
    /// otherwise degrade into a silent append), and one carrying a non-empty
    /// ExpectText is rejected unless the current line really holds that text at
    /// [Col, EndCol) (compared case-insensitively). Use the overload with
    /// ASkippedEdits to learn how many were dropped.
    /// A file whose every edit was rejected is NOT rewritten and gets NO .bak --
    /// it is not counted as touched either. This matters beyond tidiness: the
    /// write path re-serializes through a TStringList (one line-break style for the whole file),
    /// so an unconditional rewrite would modify a file that no edit had changed.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoConvertApply.PerformApplyWrites (DRagLint.CLI.pas), DRagLint.CLI.DoCreateEnumHelper (DRagLint.CLI.pas), DRagLint.CLI.DoDocumentStripQName (DRagLint.CLI.pas), DRagLint.CLI.DoDocumentUnit (DRagLint.CLI.pas), DRagLint.CLI.DoExtractMethod (DRagLint.CLI.pas) (+3 more)</para>
    /// <para>Calls: DRagLint.Refactor.TextEdit.TTextEditApplier.Apply/3</para>
    /// <para>Overload 1 of 2</para>
    /// <para>Directives: overload</para>
    /// <seealso cref="DRagLint.Refactor.TextEdit.TTextEditApplier.Apply"/>
    /// <seealso cref="DRagLint.Refactor.TextEdit.TTextEditApplier.ApplyGroup"/>
    /// <seealso cref="DRagLint.Refactor.TextEdit.TTextEditApplier.ApplyOneEdit"/>
    /// <seealso cref="DRagLint.Refactor.TextEdit.TTextEditApplier.ApplyToText"/>
    /// <seealso cref="DRagLint.Refactor.TextEdit.TTextEditApplier.RefusalOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Apply(const AEdits: TArray<TTextEdit>; AWriteBackups: Boolean): Integer; overload;
    /// <summary>Same as Apply(AEdits, AWriteBackups), additionally reporting how
    /// many edits the pre-write validation dropped.</summary>
    /// <param name="AEdits">The edit set.</param>
    /// <param name="AWriteBackups">True writes a .bak beside each touched file.</param>
    /// <param name="ASkippedEdits">Out: count of edits rejected before writing --
    /// a tekReplaceInLine whose Col is past end-of-line, or whose non-empty
    /// ExpectText does not match the current line at [Col, EndCol). Non-zero
    /// means the producer's coordinates are stale for that file and the caller
    /// should surface a "reindex and re-run" hint; those sites were NOT
    /// written.</param>
    /// <returns>Number of files ACTUALLY modified -- a file whose every edit was
    /// rejected is not rewritten, backed up, or counted.</returns>
    /// <exception cref="EInOutError"><!-- drag-lint:auto exc -->via DRagLint.Refactor.TextEdit.FailWriteForTests: %s=%d: simulated write failure on %s</exception>
    /// <remarks>
    /// Edits are grouped by FilePath CASE-INSENSITIVELY (Ruling 13): one file
    /// spelled two ways is one group -- read once, its .bak written once from
    /// the original bytes, written once under the first spelling seen.
    /// Pinned by run_rename_owners_harness.ps1 P3-P5.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.ApplyDocEditsGuarded (DRagLint.CLI.pas), DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas), DRagLint.Refactor.TextEdit.TTextEditApplier.Apply/2 (DRagLint.Refactor.TextEdit.pas)</para>
    /// <para>Calls: DRagLint.Refactor.TextEdit.FailWriteForTests, DRagLint.Refactor.TextEdit.TTextEditApplier.ApplyGroup</para>
    /// <para>Returns: Touched</para>
    /// <para>Overload 2 of 2</para>
    /// <para>Mutates: ASkippedEdits (out)</para>
    /// <para>Touches: file system</para>
    /// <para>Directives: overload</para>
    /// <seealso cref="DRagLint.Refactor.TextEdit.FailWriteForTests"/>
    /// <seealso cref="DRagLint.Refactor.TextEdit.TTextEditApplier.ApplyGroup"/>
    /// <seealso cref="DRagLint.Refactor.TextEdit.TTextEditApplier.Apply"/>
    /// <seealso cref="DRagLint.Refactor.TextEdit.TTextEditApplier.ApplyOneEdit"/>
    /// <seealso cref="DRagLint.Refactor.TextEdit.TTextEditApplier.ApplyToText"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Apply(const AEdits: TArray<TTextEdit>; AWriteBackups: Boolean;
      out ASkippedEdits: Integer): Integer; overload;
    /// <summary>Human-readable preview of the edit set.</summary>
    /// <param name="AEdits"><!-- drag-lint:auto type -->const TArray&lt;TTextEdit&gt;</param>
    /// <returns><!-- drag-lint:auto -->string -- Observed: SB.ToString.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoConvertApply.RunUnit (DRagLint.CLI.pas), DRagLint.CLI.DoCreateEnumHelper (DRagLint.CLI.pas), DRagLint.CLI.DoDocument (DRagLint.CLI.pas), DRagLint.CLI.DoDocumentUnit (DRagLint.CLI.pas), DRagLint.CLI.DoFindUnit (DRagLint.CLI.pas) (+5 more)</para>
    /// <para>Calls: Format</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Refactor.TextEdit.TTextEditApplier.Apply"/>
    /// <seealso cref="DRagLint.Refactor.TextEdit.TTextEditApplier.ApplyGroup"/>
    /// <seealso cref="DRagLint.Refactor.TextEdit.TTextEditApplier.ApplyOneEdit"/>
    /// <seealso cref="DRagLint.Refactor.TextEdit.TTextEditApplier.ApplyToText"/>
    /// <seealso cref="DRagLint.Refactor.TextEdit.TTextEditApplier.RefusalOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function RenderDryRun(const AEdits: TArray<TTextEdit>): string;
    /// <summary>Why Apply would refuse part of an edit set, or '' when it
    /// would apply every file's edits (1.25.1).</summary>
    /// <param name="AEdits">The whole plan, every file's edits.</param>
    /// <returns>'' or, for the first file whose edits Apply would refuse
    /// whole, 'refused N edit(s) to &lt;file&gt; -- overlapping delete ranges
    /// (an engine defect)'.</returns>
    /// <remarks>The same overlap test Apply makes per file, without reading
    /// or writing anything, so a caller can refuse a multi-file plan BEFORE
    /// any file is written -- Apply works file by file and cannot undo a file
    /// it already wrote. Stale-anchor edits are not considered: they are
    /// skipped one by one by design. Files are grouped case-insensitively,
    /// as Apply groups them (Ruling 13; run_rename_owners_harness.ps1 P6). Pure.</remarks>
    class function RefusalOf(const AEdits: TArray<TTextEdit>): string;
    /// <summary>Withdraws, WHOLE, every fix one of whose edits would not apply
    /// to its file as it is on disk now (lane IATOM, 2026-10-27).</summary>
    /// <param name="AEdits">The plan; edits are tied into fixes by EditAtomKey.</param>
    /// <param name="AWithdrawnOwners">Out: the distinct non-empty Owner of every
    /// withdrawn edit, in plan order -- the findings to report as declined.</param>
    /// <returns>AEdits minus the withdrawn fixes' edits, order kept. Edits with
    /// no atom key (unattributed builders) always pass through.</returns>
    /// <remarks>The check is the applier's own (EditWouldApply: the stale-anchor
    /// guard, the in-line span guard, the replace-lines whole-line guard, range
    /// checks), made against each file read once, before any edit -- so a fix
    /// whose interface removal no longer matches never lands its implementation
    /// insert alone (E2004, engine dogfood 2026-10-27). A fix spanning several
    /// files is withdrawn from all of them. Reads files; writes nothing.</remarks>
    class function WithdrawBrokenFixes(const AEdits: TArray<TTextEdit>;
      out AWithdrawnOwners: TArray<string>): TArray<TTextEdit>;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoFindUnit (DRagLint.CLI.pas), DRagLint.Convert.Apply.BuildApplyPlan.BuildToTypeAdd (DRagLint.Convert.Apply.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Convert.Apply</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TFindUnitRefactoring = class
  public
    /// <summary>Computes edits to add the unit declaring AName to AInFile's uses
    /// clause. AResolvedUnit = the chosen unit; AAlreadyUsed=True (empty result)
    /// when it is already imported. Empty result + AResolvedUnit='' when AName is
    /// unresolvable. Inserts into the implementation uses if present, else the
    /// interface uses, else a fresh implementation uses block.</summary>
    /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AInFile"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AResolvedUnit"><!-- drag-lint:auto type -->out string</param>
    /// <param name="AAlreadyUsed"><!-- drag-lint:auto type -->out Boolean</param>
    /// <returns><!-- drag-lint:auto -->TArray&lt;TTextEdit&gt; -- Observed: Build(AStore,
    /// AStore, AName, AInFile, AResolvedUnit, AAlreadyUsed).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Calls: DRagLint.Refactor.TextEdit.TFindUnitRefactoring.Build/7</para>
    /// <para>Overload 1 of 3</para>
    /// <para>Pure</para>
    /// <para>Directives: overload</para>
    /// <seealso cref="DRagLint.Refactor.TextEdit.TFindUnitRefactoring.Build"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Build(const AStore: ISymbolStore; const AName, AInFile: string;
      out AResolvedUnit: string; out AAlreadyUsed: Boolean): TArray<TTextEdit>; overload;
    /// <summary>Same as the single-store overload, but resolves AName's
    /// declaring unit (FindSymbolsByExactName/GetFilePath) against ANameStore
    /// while AInFile's own uses-clause/insertion-point lookups (FindFileIdByPath/
    /// GetUnitUsesForFile) go against AUnitStore -- for callers whose target
    /// TYPE and target FILE are indexed in different --db stores (e.g.
    /// drag-lint convert-apply, where the To type may live in a different
    /// index than the form being converted).</summary>
    /// <param name="ANameStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
    /// <param name="AUnitStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AInFile"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AResolvedUnit"><!-- drag-lint:auto type -->out string</param>
    /// <param name="AAlreadyUsed"><!-- drag-lint:auto type -->out Boolean</param>
    /// <param name="APreferInterface">False (default): the section rule above.
    /// True: target the INTERFACE uses -- appended after its last entry, or a
    /// fresh 'uses X;' after the 'interface' keyword when it has none. convert-
    /// apply passes True when the retyped field is declared in the interface
    /// section, where an implementation-only uses would not compile (E2003). A
    /// unit already used in EITHER section is still AAlreadyUsed.</param>
    /// <returns><!-- drag-lint:auto -->TArray&lt;TTextEdit&gt; -- Observed: nil; [Edit].</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoFindUnit (DRagLint.CLI.pas) ?, DRagLint.Convert.Apply.BuildApplyPlan.BuildToTypeAdd (DRagLint.Convert.Apply.pas) ?, DRagLint.Refactor.TextEdit.TFindUnitRefactoring.Build/5 (DRagLint.Refactor.TextEdit.pas)</para>
    /// <para>Calls: ChangeFileExt, DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Core.Interfaces.ISymbolStore.GetUnitUsesForFile, DRagLint.Core.Model.IncludeUsesRefusal, DRagLint.Core.Model.TUnitUse.FromInclude, DRagLint.Refactor.TextEdit.PickUsesAnchor, ExtractFileName, LowerCase, SameText, Trim</para>
    /// <para>Overload 2 of 3</para>
    /// <para>Complexity: 26 (cyclomatic, outer body), 146 lines (full implementation)</para>
    /// <para>Mutates: AResolvedUnit (out), AAlreadyUsed (out), AReason (out)</para>
    /// <para>Touches: file system</para>
    /// <para>Directives: overload</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetUnitUsesForFile"/>
    /// <seealso cref="DRagLint.Core.Model.IncludeUsesRefusal"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Build(const ANameStore, AUnitStore: ISymbolStore; const AName, AInFile: string;
      out AResolvedUnit: string; out AAlreadyUsed: Boolean; APreferInterface: Boolean = False): TArray<TTextEdit>; overload;
    /// <summary>N-06: the two-store overload that also says WHY no edit was
    /// computed when the reason is the uses clause living in an include.</summary>
    /// <param name="ANameStore">As the two-store overload.</param>
    /// <param name="AUnitStore">As the two-store overload.</param>
    /// <param name="AName">As the two-store overload.</param>
    /// <param name="AInFile">As the two-store overload.</param>
    /// <param name="AResolvedUnit">As the two-store overload.</param>
    /// <param name="AAlreadyUsed">As the two-store overload; a unit used through
    /// an include counts as used.</param>
    /// <param name="AReason">'' when an edit was computed or the usual causes
    /// apply; the uses-in-include refusal text when the target section's only
    /// uses entries come from an include (never edited, and a fresh clause
    /// there would be a second uses clause).</param>
    /// <param name="APreferInterface">As the two-store overload.</param>
    /// <returns>The edits; empty with AReason set on the include refusal.</returns>
    /// <remarks>Include rows are never the insertion anchor: the edit goes after
    /// the last INLINE entry of the section.</remarks>
    class function Build(const ANameStore, AUnitStore: ISymbolStore; const AName, AInFile: string;
      out AResolvedUnit: string; out AAlreadyUsed: Boolean; out AReason: string;
      APreferInterface: Boolean = False): TArray<TTextEdit>; overload;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoSafeDelete (DRagLint.CLI.pas)</para>
  /// <para>Used in units: DRagLint.CLI</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSafeDeleteRefactoring = class
  public
    /// <summary>Edits to delete the declaration (and impl body, for a routine)
    /// of AQName, but ONLY when it has zero references. Reference check uses
    /// FindCallersByName(short name) -- FindReferencesTo is unreliable (refs.
    /// symbol_id is NULL in the index). Returns empty + ARefuseReason when the
    /// symbol is referenced or not found.</summary>
    /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
    /// <param name="AQName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ARefuseReason"><!-- drag-lint:auto type -->out string</param>
    /// <returns><!-- drag-lint:auto -->TArray&lt;TTextEdit&gt; -- Observed: nil;
    /// Edits.ToArray.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoSafeDelete (DRagLint.CLI.pas)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindCallersByName, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByQualifiedName, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Refactor.TextEdit.LastSeg, Format</para>
    /// <para>Complexity: 10 (cyclomatic, outer body), 56 lines (full implementation)</para>
    /// <para>Mutates: ARefuseReason (out)</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindCallersByName"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByQualifiedName"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
    /// <seealso cref="DRagLint.Refactor.TextEdit.LastSeg"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Build(const AStore: ISymbolStore; const AQName: string;
      out ARefuseReason: string): TArray<TTextEdit>;
  end;

type
  /// <summary>One character a write would lose in an ANSI file (convert-apply encoding guard).</summary>
  /// <remarks>Code is the Unicode code point, Text its string form, Line the 1-based line of its
  /// first occurrence in the text as it would be written.</remarks>
  TEncodingMisfit = record
    Code: Integer;
    Text: string;
    Line: Integer;
  end;

/// <summary>The engine's name for how a text file is stored: ansi, utf8, utf8-bom or utf16-bom.</summary>
/// <param name="AFmt">A format from TTextFileFormat.Decode.</param>
/// <returns>One of ansi | utf8 | utf8-bom | utf16-bom.</returns>
function TextFileEncodingName(const AFmt: TTextFileFormat): string;

/// <summary>The distinct code points in AValues that an ANSI file cannot hold.</summary>
/// <param name="AFmt">The target file's format; only ansi can lose characters.</param>
/// <param name="AValues">The strings a write would put into the file.</param>
/// <returns>Code points in first-seen order; empty unless AFmt is ansi. "Fits" is a lossless
/// round trip through TEncoding.ANSI (the active code page).</returns>
function UnfitCodePoints(const AFmt: TTextFileFormat; const AValues: TArray<string>): TArray<Integer>;

/// <summary>The 1-based line of the first occurrence of a code point in a text.</summary>
/// <param name="AText">The text as it would be written.</param>
/// <param name="ACode">The code point to find.</param>
/// <returns>The line, or 0 when the text does not hold it.</returns>
function FirstLineOfCodePoint(const AText: string; ACode: Integer): Integer;

/// <summary>Rewrites the string literals of AText so characters AEnc cannot hold become
/// Delphi numeric codes, as the IDE writes a .dfm ('Gr'#246'sse').</summary>
/// <param name="AText">DFM text (a block or a fragment).</param>
/// <param name="AEnc">The target file's encoding; a character that round-trips is left alone.</param>
/// <returns>AText with unfit characters inside quoted literals replaced by #codes (one per UTF-16
/// unit); AText unchanged when nothing needs it. Characters outside literals are never touched.</returns>
function EscapeUnfitForDfm(const AText: string; AEnc: TEncoding): string;

/// <summary>True when bytes are a compiled (binary, TPF0 or resource-header) .dfm.</summary>
/// <param name="ABytes">The file's raw bytes.</param>
/// <returns>True for a binary form file; such a file has no text encoding.</returns>
function IsBinaryDfmFile(const ABytes: TBytes): Boolean;

/// <summary>The bytes of a text file re-stored as UTF-8 with a BOM.</summary>
/// <param name="ABytes">The file's raw bytes, decoded as TTextFileFormat.Decode does.</param>
/// <returns>BOM + the decoded text as UTF-8; the line breaks are kept as read.</returns>
function RaiseBytesToUtf8Bom(const ABytes: TBytes): TBytes;

/// <summary>TEST SEAM for an atomic multi-file write: raises before the AWriteNo-th write of one
/// write transaction when DRAGLINT_TEST_FAIL_WRITE_AT names that number; inert otherwise.</summary>
/// <param name="AWriteNo">1-based number of the write about to happen in this transaction.</param>
/// <param name="APath">The file about to be written (named in the message).</param>
/// <exception cref="EInOutError">Raised when DRAGLINT_TEST_FAIL_WRITE_AT equals AWriteNo.</exception>
/// <remarks>Called by TTextEditApplier.Apply (convert-apply) and by `cycles --fix --apply`
/// (DRagLint.CLI.CycleFix.WriteAll), so their rollback can be proven by a test.</remarks>
procedure FailWriteForTests(AWriteNo: Integer; const APath: string);

/// <summary>The key that ties edits into one all-or-nothing fix.</summary>
/// <param name="AEdit">An edit.</param>
/// <returns>AEdit.AtomGroup when set, else AEdit.Owner; '' = not tied to any
/// fix (applied, or skipped, edit by edit as before).</returns>
function EditAtomKey(const AEdit: TTextEdit): string;

implementation

uses
  System.Character, System.StrUtils, System.Math,
  DRagLint.Core.Model, DRagLint.Core.Encoding;

{ The code point starting at S[I] and how many UTF-16 units it spans (2 for a valid surrogate pair). }
function CodePointAt(const S: string; I: Integer; out ALen: Integer): Integer;
const
  HighSurrogateLo = $D800;
  HighSurrogateHi = $DBFF;
  LowSurrogateLo  = $DC00;
  LowSurrogateHi  = $DFFF;
  SurrogateBase   = $10000;
  SurrogateBits   = $400;
begin
  ALen:= 1;
  Result:= Ord(S[I]);
  if (Result >= HighSurrogateLo) and (Result <= HighSurrogateHi) and (I < Length(S))
    and (Ord(S[I + 1]) >= LowSurrogateLo) and (Ord(S[I + 1]) <= LowSurrogateHi) then
  begin
    Result:= SurrogateBase + (Result - HighSurrogateLo) * SurrogateBits + (Ord(S[I + 1]) - LowSurrogateLo);
    ALen:= 2;
  end;
end;

function TextFileEncodingName(const AFmt: TTextFileFormat): string;
begin
  if AFmt.Encoding = TEncoding.ANSI then Result:= 'ansi'
  else if AFmt.Encoding = TEncoding.UTF8 then Result:= if Length(AFmt.Preamble) > 0 then 'utf8-bom' else 'utf8'
  else Result:= 'utf16-bom';
end;

{ True when AEnc stores AUnit (one code point as UTF-16 units) and reads it back unchanged. }
function EncodingHolds(AEnc: TEncoding; const AUnit: string): Boolean;
begin
  Result:= AEnc.GetString(AEnc.GetBytes(AUnit)) = AUnit;
end;

function UnfitCodePoints(const AFmt: TTextFileFormat; const AValues: TArray<string>): TArray<Integer>;
const
  AsciiLimit = $80;
var
  Len, Cp: Integer;
  Seen   : TList<Integer>;
begin
  Result:= nil;
  if AFmt.Encoding <> TEncoding.ANSI then Exit;
  Seen:= TList<Integer>.Create;
  try
    for var V: string in AValues do
    begin
      var I: Integer:= 1;
      while I <= Length(V) do
      begin
        Cp:= CodePointAt(V, I, Len);
        if (Cp >= AsciiLimit) and not Seen.Contains(Cp) and not EncodingHolds(AFmt.Encoding, Copy(V, I, Len)) then
          Seen.Add(Cp);
        Inc(I, Len);
      end;
    end;
    Result:= Seen.ToArray;
  finally
    Seen.Free;
  end;
end;

function FirstLineOfCodePoint(const AText: string; ACode: Integer): Integer;
var
  At: Integer;
begin
  Result:= 0;
  At:= Pos(TCharacter.ConvertFromUtf32(ACode), AText);
  if At = 0 then Exit;
  Result:= 1;
  for var I: Integer:= 1 to At - 1 do
    if AText[I] = #10 then Inc(Result);
end;

function EscapeUnfitForDfm(const AText: string; AEnc: TEncoding): string;
const
  FIRST_NON_ASCII = $80; { first code unit that may need a #code }
var
  SB      : TStringBuilder;
  SrcIn   : Boolean; { the source is inside a quoted literal }
  OutIn   : Boolean; { the output has an open quote }
  LitAny  : Boolean; { the current literal produced output }
  I, Len  : Integer;
  C       : Char;

  procedure CloseOut;
  begin
    if OutIn then
    begin
      SB.Append('''');
      OutIn:= False;
    end;
  end;

  procedure OpenOut;
  begin
    if not OutIn then
    begin
      SB.Append('''');
      OutIn:= True;
    end;
    LitAny:= True;
  end;

begin
  SB:= TStringBuilder.Create;
  try
    SrcIn := False;
    OutIn := False;
    LitAny:= False;
    I:= 1;
    while I <= Length(AText) do
    begin
      C:= AText[I];
      if not SrcIn then
      begin
        SB.Append(C);
        if C = '''' then
        begin
          SrcIn := True;
          SB.Length:= SB.Length - 1;
          OutIn := False;
          LitAny:= False;
        end;
        Inc(I);
        Continue;
      end;
      if C = '''' then
      begin
        if (I < Length(AText)) and (AText[I + 1] = '''') then
        begin
          OpenOut;
          SB.Append('''''');
          Inc(I, 2);
          Continue;
        end;
        if not LitAny then SB.Append('''''') else CloseOut;
        SrcIn:= False;
        Inc(I);
        Continue;
      end;
      CodePointAt(AText, I, Len);
      if (Ord(C) >= FIRST_NON_ASCII) and not EncodingHolds(AEnc, Copy(AText, I, Len)) then
      begin
        CloseOut;
        LitAny:= True;
        for var K: Integer:= 0 to Len - 1 do SB.Append('#').Append(Ord(AText[I + K]));
      end
      else
      begin
        OpenOut;
        SB.Append(Copy(AText, I, Len));
      end;
      Inc(I, Len);
    end;
    if SrcIn then CloseOut; { an unterminated literal: leave the output as balanced as the input was }
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function IsBinaryDfmFile(const ABytes: TBytes): Boolean;
const
  ResHeaderFirstByte = $FF;
  Signature          = 'TPF0';
begin
  Result:= ((Length(ABytes) > 0) and (ABytes[0] = ResHeaderFirstByte)) or
           ((Length(ABytes) >= Length(Signature)) and (TEncoding.ANSI.GetString(ABytes, 0, Length(Signature)) = Signature));
end;

function RaiseBytesToUtf8Bom(const ABytes: TBytes): TBytes;
var
  Text: string;
begin
  TTextFileFormat.Decode(ABytes, Text);
  Result:= TEncoding.UTF8.GetPreamble + TEncoding.UTF8.GetBytes(Text);
end;

function HasHighByte(const ABytes: TBytes): Boolean;
const
  FirstNonAscii = $80;
begin
  Result:= False;
  for var B: Byte in ABytes do
    if B >= FirstNonAscii then Exit(True);
end;

class function TTextFileFormat.Decode(const ABytes: TBytes; out AText: string): TTextFileFormat;
var
  Enc : TEncoding;
  Skip: Integer;
begin
  Enc := nil; { nil = detect a UTF-8 / UTF-16 BOM, else fall back to ANSI }
  Skip:= TEncoding.GetBufferEncoding(ABytes, Enc, TEncoding.ANSI);
  { W5-D: no BOM, a high byte, and valid UTF-8 = UTF-8 without a BOM }
  if (Skip = 0) and (Enc = TEncoding.ANSI) and HasHighByte(ABytes) and IsValidUtf8(ABytes) then Enc:= TEncoding.UTF8;
  Result.Encoding:= Enc;
  Result.Preamble:= Copy(ABytes, 0, Skip);
  AText:= if Length(ABytes) > Skip then Enc.GetString(ABytes, Skip, Length(ABytes) - Skip) else '';
  Result.LineBreak:= LineBreakOf(AText);
end;

class function TTextFileFormat.ReadFile(const APath: string; out AText: string): TTextFileFormat;
var
  Bytes: TBytes;
begin
  Bytes:= nil;
  if TFile.Exists(APath) then Bytes:= TFile.ReadAllBytes(APath);
  Result:= Decode(Bytes, AText);
end;

class function TTextFileFormat.LineBreakOf(const AText: string): string;
begin
  Result:= if (Pos(#10, AText) > 0) and (Pos(#13#10, AText) = 0) then #10 else #13#10;
end;

function TTextFileFormat.Encode(const AText: string): TBytes;
begin
  Result:= Preamble + Encoding.GetBytes(AText);
end;

{ Sort key for back-to-front application within a file: larger line first; for
  deletes use EndLine as the key so a delete is processed before any edit above
  it. tekInsertInLine/Lines use Line. }
function EditTopLine(const E: TTextEdit): Integer;
begin
  Result:= if E.Kind in [tekDeleteLines, tekReplaceLines] then E.EndLine else E.Line;
end;

{ THE STALE-POSITION GUARD for tekReplaceInLine. True when the edit may be
  written against ALine, the current on-disk content of its target line.
  Rejects two things the old unguarded path let through silently:
   * Col past end-of-line -- Copy(S, 1, C-1) + Text + Copy(S, EC, MaxInt) then
     degenerates into an APPEND, gluing the replacement onto whatever the line
     ends with (observed: `then` + `GlyActive` -> `thenGlyActive`, exit code 0);
   * a non-empty ExpectText that the line does not actually hold at
     [Col, EndCol) -- i.e. store coordinates that have drifted since indexing.
  An empty ExpectText leaves the second check off, which is exactly the historic
  behaviour every pre-existing caller relies on. }
function ReplaceEditIsValid(const E: TTextEdit; const ALine: string): Boolean;
var
  C, EC: Integer;
begin
  Result:= False;
  C:= E.Col; if C < 1 then C:= 1;
  if C > Length(ALine) + 1 then Exit;      { past end-of-line: reject, never append }
  if E.ExpectText = '' then Exit(True);    { unguarded (legacy) caller }
  EC:= E.EndCol;
  if EC <= C then Exit;
  if (EC - C) <> Length(E.ExpectText) then Exit;   { span width must match }
  if (EC - 1) > Length(ALine) then Exit;           { span runs past end-of-line }
  Result:= SameText(Copy(ALine, C, EC - C), E.ExpectText);
end;

{ THE STALE-ANCHOR GUARD, for edits whose Line came from the symbol store.

  ReplaceEditIsValid above answers "does this line still hold the text I am
  about to replace". It only ever applied to tekReplaceInLine, so the LINE kinds
  -- insert a block above a declaration, delete the block above it -- had no
  guard at all. That is the fourth instance of one root cause this repo has now
  hit: `unused-local`'s fixer destroyed 72 lines; the naming autofix wrote onto
  `then`/`else` and exited 0; `document --qname --apply` run twice on one class
  nested the second block inside the first and left the second symbol
  undocumented, because the store still held the PRE-EDIT start_line, which
  after the first insert pointed into the middle of the block just written.

  WHY "CONTAINS THE NAME" IS NOT ENOUGH, and the comment test is load-bearing:
  the stale coordinate in that defect landed on `/// Calls: Create` -- a line
  that DOES contain the identifier the guard is looking for. So the anchor must
  also still look like a DECLARATION: a line that starts a comment is never one.
  Together the two conditions are what makes this structural rather than a
  spelling check.

  Conservative in the only direction that matters: when the guard cannot
  confirm the anchor, the edit is DROPPED. Dropping a good edit costs a re-run;
  writing at a coordinate that has moved corrupts the user's source. }
function ContainsWholeWord(const AText, AWord: string): Boolean;
var
  L, W : string ;
  P, WL: Integer;

  function IsWordCh(const ACh: Char): Boolean;
  begin
    Result:= CharInSet(ACh, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
  end;

begin
  Result:= False;
  if AWord = '' then Exit;
  L := LowerCase(AText);
  W := LowerCase(AWord);
  WL:= Length(W);
  P := Pos(W, L);
  while P > 0 do
  begin
    if ((P = 1) or (not IsWordCh(L[P - 1]))) and
       ((P + WL > Length(L)) or (not IsWordCh(L[P + WL]))) then Exit(True);
    P:= Pos(W, L, P + 1);
  end;
end;

function AnchorIsValid(const E: TTextEdit; ALines: TStrings): Boolean;
var
  S: string;
begin
  if (E.ExpectLine <= 0) or (E.ExpectText = '') then Exit(True);  { unguarded }
  if (E.ExpectLine > ALines.Count) then Exit(False);              { file shrank past it }
  S:= TrimLeft(ALines[E.ExpectLine - 1]);
  { A comment line is never a declaration -- see the header above. }
  if S.StartsWith('//') or S.StartsWith('{') or S.StartsWith('(*') then Exit(False);
  Result:= ContainsWholeWord(S, E.ExpectText);
end;

{ True when two tekDeleteLines edits in AEdits (one file's edits) cover a
  common line. Overlapping deletes are never a valid plan: applied back-to-front
  the second one lands on lines the first has already shifted into place, and
  deletes whatever sits BELOW its intended span. That is how a duplicated
  doc-repair pair removed nine declarations on 2026-09-29 (both overloads of a
  pair re-resolved by name to the first). Adjacent ranges do not overlap. }
function DeletesOverlap(AEdits: TList<TTextEdit>): Boolean;
var
  Ranges: TList<TTextEdit>;
  E     : TTextEdit       ;
  I     : Integer         ;
begin
  Result:= False;
  Ranges:= TList<TTextEdit>.Create;
  try
    for E in AEdits do
      if E.Kind in [tekDeleteLines, tekReplaceLines] then Ranges.Add(E);   { a replace-lines range overlaps like a delete }
    Ranges.Sort(TComparer<TTextEdit>.Construct(
      function(const A, B: TTextEdit): Integer
      begin
        Result:= A.Line - B.Line;
      end));
    for I:= 1 to Ranges.Count - 1 do
      if Ranges[I].Line <= Ranges[I - 1].EndLine then Exit(True);
  finally
    Ranges.Free;
  end;
end;

{ 1.25.1: TEST SEAM, inert unless the environment variable names it. With
  DRAGLINT_TEST_FAIL_WRITE_AT=N, the N-th file write of one Apply call raises
  EInOutError before a byte of it is written -- the only way a test can make a
  write fail AFTER convert-apply's writability pre-check, which is what its
  rollback exists for (run_convert_apply_atomic.ps1). }
procedure FailWriteForTests(AWriteNo: Integer; const APath: string);
const
  TEST_FAIL_WRITE_AT = 'DRAGLINT_TEST_FAIL_WRITE_AT';
begin
  if GetEnvironmentVariable(TEST_FAIL_WRITE_AT) = IntToStr(AWriteNo) then
    raise EInOutError.CreateFmt('%s=%d: simulated write failure on %s', [TEST_FAIL_WRITE_AT, AWriteNo, APath]);
end;

class function TTextEditApplier.RefusalOf(const AEdits: TArray<TTextEdit>): string;
var
  FileMap: TObjectDictionary<string, TList<TTextEdit>>;
  Group  : TList<TTextEdit>;
  Paths  : TArray<string>;
begin
  Result := '';
  { Ruling 13: one file under two spellings (BASICS.PAS / Basics.pas) is ONE
    group, or an overlap across the spellings goes unseen. }
  FileMap:= TObjectDictionary<string, TList<TTextEdit>>.Create([doOwnsValues], TIStringComparer.Ordinal);
  try
    Paths:= nil;
    for var E: TTextEdit in AEdits do
    begin
      if not FileMap.TryGetValue(E.FilePath, Group) then
      begin
        Group:= TList<TTextEdit>.Create;
        FileMap.Add(E.FilePath, Group);
        Paths:= Paths + [E.FilePath];
      end;
      Group.Add(E);
    end;
    for var P: string in Paths do
      if DeletesOverlap(FileMap[P]) then
        Exit(Format('refused %d edit(s) to %s -- overlapping delete ranges (an engine defect)', [FileMap[P].Count, P]));
  finally
    FileMap.Free;
  end;
end;

class function TTextEditApplier.Apply(const AEdits: TArray<TTextEdit>; AWriteBackups: Boolean): Integer;
var
  Skipped: Integer;
begin
  Result:= Apply(AEdits, AWriteBackups, Skipped);
end;

{ tekReplaceLines (autofix wave A0): the whole range must exist, and the first
  line must still hold the text the producer saw (when it set ExpectText) --
  else the edit is stale and only counted. }
procedure ApplyReplaceLines(ALines: TStringList; const AEdit: TTextEdit; var AApplied, ASkippedEdits: Integer);
begin
  if (AEdit.Line < 1) or (AEdit.EndLine < AEdit.Line) or (AEdit.EndLine > ALines.Count)
     or ((AEdit.ExpectText <> '') and (ALines[AEdit.Line - 1] <> AEdit.ExpectText)) then
  begin
    Inc(ASkippedEdits);
    Exit;
  end;
  for var L: Integer:= AEdit.EndLine downto AEdit.Line do ALines.Delete(L - 1);
  var Parts: TArray<string>:= AEdit.Text.Replace(#13#10, #10).Split([#10]);
  if Length(Parts) = 0 then Parts:= [''];
  for var PIdx: Integer:= High(Parts) downto 0 do ALines.Insert(AEdit.Line - 1, Parts[PIdx]);
  Inc(AApplied);
end;

function EditAtomKey(const AEdit: TTextEdit): string;
begin
  Result:= if AEdit.AtomGroup <> '' then AEdit.AtomGroup else AEdit.Owner;
end;

{ lane IATOM: would ApplyOneEdit WRITE this edit against ALines (the file as
  found)? The same guards ApplyOneEdit and the anchor pre-pass apply, plus a
  delete range that must lie inside the file. Edits are applied back-to-front
  and never overlap, so the answer against the unmutated snapshot is the answer
  at write time. }
function EditWouldApply(const E: TTextEdit; ALines: TStrings): Boolean;
begin
  if not AnchorIsValid(E, ALines) then Exit(False);
  case E.Kind of
    tekDeleteLines  : Result:= (E.Line >= 1) and (E.EndLine >= E.Line) and (E.EndLine <= ALines.Count);
    tekInsertInLine : Result:= InRange(E.Line, 1, ALines.Count);
    tekReplaceInLine: Result:= InRange(E.Line, 1, ALines.Count) and ReplaceEditIsValid(E, ALines[E.Line - 1]);
    tekReplaceLines : Result:= (E.Line >= 1) and (E.EndLine >= E.Line) and (E.EndLine <= ALines.Count)
                               and ((E.ExpectText = '') or (ALines[E.Line - 1] = E.ExpectText));
  else
    Result:= True;  { tekInsertLines clamps its index and always writes }
  end;
end;

{ Adds to ABad the atom key of every keyed edit of AEdits that would not apply to ALines. }
procedure CollectBrokenAtoms(AEdits: TEnumerable<TTextEdit>; ALines: TStrings; ABad: TStringList);
begin
  for var E: TTextEdit in AEdits do
    if (EditAtomKey(E) <> '') and not EditWouldApply(E, ALines) then ABad.Add(EditAtomKey(E));
end;

class function TTextEditApplier.WithdrawBrokenFixes(const AEdits: TArray<TTextEdit>;
  out AWithdrawnOwners: TArray<string>): TArray<TTextEdit>;
var
  FileMap: TObjectDictionary<string, TList<TTextEdit>>;
  Group  : TList<TTextEdit>;
  Bad    : TStringList;
  Lines  : TStringList;
  Text   : string;
begin
  AWithdrawnOwners:= nil;
  FileMap:= TObjectDictionary<string, TList<TTextEdit>>.Create([doOwnsValues], TIStringComparer.Ordinal);
  Bad    := TStringList.Create(dupIgnore, True, False);
  Lines  := TStringList.Create;
  try
    for var E: TTextEdit in AEdits do
      if EditAtomKey(E) <> '' then
      begin
        if not FileMap.TryGetValue(E.FilePath, Group) then
        begin
          Group:= TList<TTextEdit>.Create;
          FileMap.Add(E.FilePath, Group);
        end;
        Group.Add(E);
      end;
    for var Pair: TPair<string, TList<TTextEdit>> in FileMap do
    begin
      TTextFileFormat.ReadFile(Pair.Key, Text);
      Lines.Text:= Text;
      CollectBrokenAtoms(Pair.Value, Lines, Bad);
    end;
    if Bad.Count = 0 then Exit(AEdits);
    Result:= nil;
    for var E: TTextEdit in AEdits do
      if (EditAtomKey(E) <> '') and (Bad.IndexOf(EditAtomKey(E)) >= 0) then
      begin
        if (E.Owner <> '') and (IndexText(E.Owner, AWithdrawnOwners) < 0) then AWithdrawnOwners:= AWithdrawnOwners + [E.Owner];
      end
      else Result:= Result + [E];
  finally
    Lines.Free;
    Bad.Free;
    FileMap.Free;
  end;
end;

{ One kept edit applied to ALines (the per-kind half of ApplyGroup). }
class procedure TTextEditApplier.ApplyOneEdit(ALines: TStringList; const AEdit: TTextEdit; var AApplied, ASkippedEdits: Integer);
begin
  case AEdit.Kind of
    tekDeleteLines:
      begin
        var LHi: Integer:= AEdit.EndLine;
        var LLo: Integer:= AEdit.Line;
        if LLo < 1 then LLo:= 1;
        if LHi > ALines.Count then LHi:= ALines.Count;
        for var L: Integer:= LHi downto LLo do
          if (L >= 1) and (L <= ALines.Count) then
          begin
            ALines.Delete(L - 1);
            Inc(AApplied);
          end;
      end;
    tekInsertLines:
      begin
        var Idx: Integer:= AEdit.Line; { insert AFTER 1-based Line => 0-based index Line }
        if Idx < 0 then Idx:= 0;
        if Idx > ALines.Count then Idx:= ALines.Count;
        { split Text on CRLF/LF so multi-line inserts keep separate lines }
        var Parts: TArray<string>:= AEdit.Text.Replace(#13#10, #10).Split([#10]);
        for var PIdx: Integer:= High(Parts) downto 0 do
          ALines.Insert(Idx, Parts[PIdx]);
        Inc(AApplied);
      end;
    tekInsertInLine:
      begin
        if (AEdit.Line >= 1) and (AEdit.Line <= ALines.Count) then
        begin
          var S: string:= ALines[AEdit.Line - 1];
          var C: Integer:= AEdit.Col;
          if C < 1 then C:= 1;
          if C > Length(S) + 1 then C:= Length(S) + 1;
          ALines[AEdit.Line - 1]:= Copy(S, 1, C - 1) + AEdit.Text + Copy(S, C, MaxInt);
          Inc(AApplied);
        end
        else
          Inc(ASkippedEdits);   { line does not exist: silently dropped before }
      end;
    tekReplaceInLine:
      begin
        if (AEdit.Line >= 1) and (AEdit.Line <= ALines.Count) then
        begin
          var S: string:= ALines[AEdit.Line - 1];
          if not ReplaceEditIsValid(AEdit, S) then
            Inc(ASkippedEdits)
          else
          begin
            var C: Integer:= AEdit.Col;
            if C < 1 then C:= 1;
            var EC: Integer:= AEdit.EndCol;
            if EC < C then EC:= C;
            if EC > Length(S) + 1 then EC:= Length(S) + 1;
            ALines[AEdit.Line - 1]:= Copy(S, 1, C - 1) + AEdit.Text + Copy(S, EC, MaxInt);
            Inc(AApplied);
          end;
        end
        else
          Inc(ASkippedEdits);   { line does not exist: out of range, never written }
      end;
    tekReplaceLines: ApplyReplaceLines(ALines, AEdit, AApplied, ASkippedEdits);
  end;
end;

{ 1.27.0 (C9): ONE file's edits applied to its text -- the shared core of Apply
  and ApplyToText, so the in-memory preview convert-apply re-indexes is, by
  construction, the text Apply writes. AApplied is the number of edits that
  changed the lines (0 = Apply leaves the file alone). AQuiet suppresses the
  overlapping-delete note on stderr (a preview is not a refusal). }
class function TTextEditApplier.ApplyGroup(const AFilePath, AContent: string; AGroup: TList<TTextEdit>;
  AQuiet: Boolean; var ASkippedEdits: Integer; out AApplied: Integer): string;
var
  Group  : TList<TTextEdit>;
  E      : TTextEdit;
  Content: string;
  Lines  : TStringList;
  Cmp    : IComparer<TTextEdit>;
  Kept   : TList<TTextEdit>;
  AppliedInFile: Integer;
begin
  Group  := AGroup;
  Content:= AContent;
  Result := AContent;
  AppliedInFile:= 0;
  AApplied:= 0;
  { back-to-front: largest top-line first so indices stay valid }
  Cmp:= TComparer<TTextEdit>.Construct(
    function(const A, B: TTextEdit): Integer
    begin
      Result:= EditTopLine(B) - EditTopLine(A);
      { 1.25.2: an `insert after L` and a delete ENDING at L share the key L
        -- two ADJACENT re-emitted blocks: the second's insert after the
        first's last line. The insert must go first: run after the delete,
        its index L lands as many lines too low as were deleted, inside a
        later block (DMREADINGS: tables spliced into their neighbours, a
        .dfm Delphi refused). TList.Sort is not stable, so the order is
        stated, never left to the sort. }
      if Result = 0 then Result:= Ord(A.Kind <> tekInsertLines) - Ord(B.Kind <> tekInsertLines);
      { same line: larger column first (back-to-front) }
      if Result = 0 then Result:= B.Col - A.Col;
    end);
  { 1.25.2: STABLE. Edits the comparer ties (two inserts at one line and
    column) are applied in REVERSE planned order, so they land in the file
    in planned order: each later insert at the same index goes above the
    earlier one. TList.Sort alone left it to the sort. }
  var Planned: TArray<TTextEdit>:= Group.ToArray;
  var Order: TList<Integer>:= TList<Integer>.Create;
  try
    for var K: Integer:= 0 to High(Planned) do Order.Add(K);
    Order.Sort(TComparer<Integer>.Construct(
      function(const IA, IB: Integer): Integer
      begin
        Result:= Cmp.Compare(Planned[IA], Planned[IB]);
        if Result = 0 then Result:= IB - IA;
      end));
    Group.Clear;
    for var K: Integer in Order do Group.Add(Planned[K]);
  finally
    Order.Free;
  end;

  Lines:= TStringList.Create;
  try
    Lines.Text:= Content;

    { v(PHASE A2): STALE-ANCHOR PRE-PASS, over the file AS FOUND.

      It runs BEFORE any edit is applied, and that is not a stylistic
      choice. Edits are applied back-to-front, and the doc repair path emits
      a DELETE of the old comment span plus an INSERT of the merged one --
      the delete is processed first, which shifts every line below it. An
      anchor checked mid-loop would therefore be read at the wrong offset
      for the insert, and the pair could half-apply: the existing comment
      deleted, its replacement dropped. Validating everything against the
      unmutated snapshot makes a pair fail or survive TOGETHER, since both
      carry the same anchor.

      Only ExpectLine-bearing edits are affected; every historic caller
      leaves it 0 and reaches the loop below exactly as before. }
    { lane IATOM: a FIX is applied all-or-nothing. When any edit of one atom
      (EditAtomKey -- the finding, or the group a fixer set) would not apply
      to the file as found, every edit of that atom is dropped here, before a
      byte moves: an interface removal that no longer matches must not leave
      its implementation insert behind (E2004). Unkeyed edits keep the
      historical edit-by-edit behaviour. }
    var Broken: TStringList:= TStringList.Create(dupIgnore, True, False);
    Kept:= TList<TTextEdit>.Create;
    try
      CollectBrokenAtoms(Group, Lines, Broken);
      for E in Group do
        if (EditAtomKey(E) <> '') and (Broken.IndexOf(EditAtomKey(E)) >= 0) then Inc(ASkippedEdits)
        else if AnchorIsValid(E, Lines) then Kept.Add(E)
        else Inc(ASkippedEdits);

      { 2026-09-29: an engine that plans overlapping deletes has a defect,
        and applying its plan destroys lines it never meant to touch. Refuse
        the file's edits WHOLE -- a partial application is how a repair
        becomes a loss -- and say so, since the file is left as found. }
      if DeletesOverlap(Kept) then
      begin
        if not AQuiet then Writeln(ErrOutput, Format('drag-lint: refused %d edit(s) to %s -- overlapping delete ranges ' +
          '(an engine defect; the file is left unchanged)', [Kept.Count, AFilePath]));
        Inc(ASkippedEdits, Kept.Count);
        Kept.Clear;
      end;

    for E in Kept do ApplyOneEdit(Lines, E, AppliedInFile, ASkippedEdits);
    finally
      Broken.Free;
      Kept.Free;
    end;
    AApplied:= AppliedInFile;
    if AppliedInFile = 0 then Exit;
    { re-join in the file's own line-break style (F8: CRLF unless it was LF-only),
      preserve a trailing newline if the original had one }
    var LB: string:= TTextFileFormat.LineBreakOf(Content);
    var SB: TStringBuilder:= TStringBuilder.Create;
    try
      for var I: Integer:= 0 to Lines.Count - 1 do
      begin
        SB.Append(Lines[I]);
        if I < Lines.Count - 1 then SB.Append(LB);
      end;
      if (Content <> '') and (Content[Length(Content)] = #10) then SB.Append(LB);
      Result:= SB.ToString;
    finally
      SB.Free;
    end;
  finally
    Lines.Free;
  end;
end;

class function TTextEditApplier.ApplyToText(const AFilePath, AContent: string; const AEdits: TArray<TTextEdit>): string;
var
  Group  : TList<TTextEdit>;
  Skipped: Integer;
  Applied: Integer;
begin
  Group:= TList<TTextEdit>.Create;
  try
    for var E: TTextEdit in AEdits do
      if SameText(E.FilePath, AFilePath) then Group.Add(E);
    Skipped:= 0;
    Result := ApplyGroup(AFilePath, AContent, Group, True, Skipped, Applied);
  finally
    Group.Free;
  end;
end;

class function TTextEditApplier.Apply(const AEdits: TArray<TTextEdit>; AWriteBackups: Boolean;
  out ASkippedEdits: Integer): Integer;
var
  FileMap : TDictionary<string, TList<TTextEdit>>;
  E       : TTextEdit;
  Group   : TList<TTextEdit>;
  Pair    : TPair<string, TList<TTextEdit>>;
  RawBytes: TBytes;
  Fmt     : TTextFileFormat;
  OldText : string;
  NewText : string;
  Touched : Integer;
  AppliedInFile: Integer;
begin
  Touched:= 0;
  ASkippedEdits:= 0;
  { Ruling 13: group by path CASE-INSENSITIVELY. Two owners of a shared unit
    store it as BASICS.PAS and Basics.pas; as two groups the second re-read the
    first's output and overwrote the .bak with it. One group = one read, one
    .bak from the ORIGINAL bytes, one write (under the first spelling seen). }
  FileMap:= TDictionary<string, TList<TTextEdit>>.Create(TIStringComparer.Ordinal);
  try
    for E in AEdits do
    begin
      if not FileMap.TryGetValue(E.FilePath, Group) then
      begin Group:= TList<TTextEdit>.Create; FileMap.Add(E.FilePath, Group); end;
      Group.Add(E);
    end;

    for Pair in FileMap do
    begin
      if not TFile.Exists(Pair.Key) then Continue;
      RawBytes:= TFile.ReadAllBytes(Pair.Key);
      { The .bak used to be written before a single edit had been evaluated --
        so a file whose every edit the guard rejected still got a backup, was
        still rewritten, and still counted as touched. RawBytes holds the
        original, so the backup waits until something changed. }
      { F8: decode by the file's BOM (none = ANSI, as before) and write back in
        the same encoding, BOM included. }
      Fmt:= TTextFileFormat.Decode(RawBytes, OldText);
      NewText:= ApplyGroup(Pair.Key, OldText, Pair.Value, False, ASkippedEdits, AppliedInFile);
      { Nothing survived validation for this file: leave it exactly as found --
        no backup, no rewrite, not counted. The re-serialization is NOT
        byte-preserving (TStringList + one line-break style), so writing here
        would edit a file on behalf of zero applied edits. }
      if AppliedInFile = 0 then Continue;
      if AWriteBackups then TFile.WriteAllBytes(Pair.Key + '.bak', RawBytes);
      FailWriteForTests(Touched + 1, Pair.Key);
      TFile.WriteAllBytes(Pair.Key, Fmt.Encode(NewText));
      Inc(Touched);
    end;
  finally
    for Pair in FileMap do Pair.Value.Free;
    FileMap.Free;
  end;
  Result:= Touched;
end;

class function TTextEditApplier.RenderDryRun(const AEdits: TArray<TTextEdit>): string;
var SB: TStringBuilder; E: TTextEdit; Last: string;
begin
  SB:= TStringBuilder.Create;
  try
    Last:= '';
    for E in AEdits do
    begin
      if E.FilePath <> Last then begin SB.AppendLine('File: ' + E.FilePath); Last:= E.FilePath; end;
      case E.Kind of
        tekDeleteLines : SB.AppendLine(Format('  delete lines %d..%d', [E.Line, E.EndLine]));
        tekInsertLines : SB.AppendLine(Format('  insert after line %d: %s', [E.Line, E.Text]));
        tekInsertInLine: SB.AppendLine(Format('  insert at L%d:C%d: %s', [E.Line, E.Col, E.Text]));
        tekReplaceInLine: SB.AppendLine(Format('  replace L%d:C%d..%d -> "%s"', [E.Line, E.Col, E.EndCol, E.Text]));
        tekReplaceLines : SB.AppendLine(Format('  replace lines %d..%d -> "%s"', [E.Line, E.EndLine, E.Text.Replace(#13#10, '\n').Replace(#10, '\n')]));
      end;
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

{ N-06: the anchor scan of TFindUnitRefactoring.Build. ALast = the textually last
  INLINE entry of ASection (an include row is never the anchor: its coordinates
  are in the .inc); AIncRow = the first include-sourced entry of ASection, or a
  default record (FromInclude = False) when there is none. }
procedure PickUsesAnchor(const AUses: TArray<TUnitUse>; ASection: TUnitUseSection;
  out ALast, AIncRow: TUnitUse; out AHaveLast: Boolean);
var
  U: TUnitUse;
begin
  ALast:= Default(TUnitUse);
  AIncRow:= Default(TUnitUse);
  AHaveLast:= False;
  for U in AUses do
    if (U.Section = ASection) and U.FromInclude and not AIncRow.FromInclude then
      AIncRow:= U;
  for U in AUses do
    if (U.Section = ASection) and not U.FromInclude then
      if (not AHaveLast) or (U.StartLine > ALast.StartLine)
         or ((U.StartLine = ALast.StartLine) and (U.StartCol > ALast.StartCol)) then
      begin
        ALast:= U;
        AHaveLast:= True;
      end;
end;

class function TFindUnitRefactoring.Build(const AStore: ISymbolStore;
  const AName, AInFile: string; out AResolvedUnit: string; out AAlreadyUsed: Boolean): TArray<TTextEdit>;
begin
  Result:= Build(AStore, AStore, AName, AInFile, AResolvedUnit, AAlreadyUsed);
end;

class function TFindUnitRefactoring.Build(const ANameStore, AUnitStore: ISymbolStore;
  const AName, AInFile: string; out AResolvedUnit: string; out AAlreadyUsed: Boolean;
  APreferInterface: Boolean): TArray<TTextEdit>;
var
  Reason: string;
begin
  Result:= Build(ANameStore, AUnitStore, AName, AInFile, AResolvedUnit, AAlreadyUsed, Reason, APreferInterface);
end;

class function TFindUnitRefactoring.Build(const ANameStore, AUnitStore: ISymbolStore;  // dl:ok too-many-parameters@896d, too-many-exit-points@8fee -- REVIEWED 2026-10-23: params = the 7-parameter overload plus the one N-06 out-reason (a record would only rename them); exits = six guard-clause exits (nothing found, self, already used, file not indexed, no keyword line) that predate N-06, whose own exit was folded into the else-if chain
  const AName, AInFile: string; out AResolvedUnit: string; out AAlreadyUsed: Boolean;
  out AReason: string; APreferInterface: Boolean): TArray<TTextEdit>;
var
  Syms : TArray<TSymbol>;
  S    : TSymbol;
  Cands: TDictionary<string, Integer>; { unit -> score }
  Best : string; BestScore: Integer;
  FullPath: string; InFileId: Int64;
  Uses_: TArray<TUnitUse>; U: TUnitUse;
  UsedSet: TDictionary<string, Boolean>;
  UnitName: string;
  TargetSection: TUnitUseSection;
  LastInSection: TUnitUse; HaveLast: Boolean;
  IncRow: TUnitUse;
  Edit: TTextEdit;
  Pair: TPair<string, Integer>;
begin
  Result:= nil; AResolvedUnit:= ''; AAlreadyUsed:= False;
  AReason:= '';

  { 1. resolve the best declaring unit -- against ANameStore, which may be a
    DIFFERENT store than AUnitStore (the type being added to the uses clause
    may be indexed in a different --db than the file it's being added to). }
  Syms:= ANameStore.FindSymbolsByExactName(AName);
  if Length(Syms) = 0 then Exit;
  Cands:= TDictionary<string, Integer>.Create;
  try
    for S in Syms do
    begin
      UnitName:= ChangeFileExt(ExtractFileName(ANameStore.GetFilePath(S.FileId)), '');
      if UnitName = '' then Continue;
      var Sc: Integer:= 1;
      if not SameText(S.Section, 'implementation') then Inc(Sc, 10); { interface-visible }
      var Cur: Integer;
      if not Cands.TryGetValue(UnitName, Cur) then Cur:= 0;
      Cands.AddOrSetValue(UnitName, Cur + Sc);
    end;
    Best:= ''; BestScore:= -1;
    for Pair in Cands do
      if Pair.Value > BestScore then begin BestScore:= Pair.Value; Best:= Pair.Key; end;
  finally
    Cands.Free;
  end;
  if Best = '' then Exit;
  AResolvedUnit:= Best;

  { do not add a unit to itself }
  if SameText(ChangeFileExt(ExtractFileName(AInFile), ''), Best) then Exit;

  { 2. load the target file's existing uses -- against AUnitStore, which
    actually has AInFile indexed. }
  FullPath:= TPath.GetFullPath(AInFile);
  InFileId:= AUnitStore.FindFileIdByPath(FullPath);
  if InFileId <= 0 then InFileId:= AUnitStore.FindFileIdByPath(AInFile);
  Uses_:= nil;
  if InFileId > 0 then Uses_:= AUnitStore.GetUnitUsesForFile(InFileId);

  UsedSet:= TDictionary<string, Boolean>.Create;
  try
    for U in Uses_ do UsedSet.AddOrSetValue(LowerCase(U.UnitName), True);
    if UsedSet.ContainsKey(LowerCase(Best)) then begin AAlreadyUsed:= True; Exit; end;

    { 3. choose target section: implementation uses if present, else interface }
    HaveLast:= False;
    var HasImpl: Boolean:= False;
    var HasIntf: Boolean:= False;
    for U in Uses_ do
    begin
      if U.Section = uusImplementation then HasImpl:= True;
      if U.Section = uusInterface then HasIntf:= True;
    end;
    { C13 a: a caller retyping an INTERFACE declaration needs the unit there }
    if APreferInterface then TargetSection:= uusInterface
    else if HasImpl then TargetSection:= uusImplementation
    else if HasIntf then TargetSection:= uusInterface
    else TargetSection:= uusImplementation; { fresh block goes to implementation }

    { last entry in the chosen section -> append ', Best' after it. N-06: an
      include row is never the anchor (its coordinates are in the .inc). }
    PickUsesAnchor(Uses_, TargetSection, LastInSection, IncRow, HaveLast);

    if HaveLast then
    begin
      { insert ', Best' at the end of the last unit entry (before the ';') }
      Edit.FilePath:= AInFile; Edit.Kind:= tekInsertInLine;
      Edit.Line:= LastInSection.EndLine; Edit.Col:= LastInSection.EndCol;
      Edit.EndLine:= 0; Edit.Text:= ', ' + Best;
      Result:= [Edit];
    end
    else if IncRow.FromInclude then
      { N-06: the section's uses clause lives in an include -- never edited, and
        a fresh clause here would be a second uses clause. }
      AReason:= IncludeUsesRefusal('find-unit', IncRow, AInFile)
    else
    begin
      { no uses clause in the file at all -> a fresh "uses Best;" block.
        Insert after the 'implementation' line if the file has one, else after
        'interface'. We locate the keyword by reading the file (cheap, single file). }

      { ...BUT ONLY IF WE ACTUALLY KNOW THAT. An empty Uses_ has TWO causes and
        they demand opposite actions:
          (a) the file genuinely declares no uses clause  -> a fresh block is right;
          (b) AUnitStore does not INDEX the file at all   -> we know nothing, and
              a fresh block is a guess.
        InFileId separates them, and until now nothing did. Measured: with a
        library-only --db, `find-unit --name TEdit --in uMainZeissCopy.pas`
        proposed `insert after line 2176: uses Vcl.StdCtrls;` -- line 2176 is
        `implementation`, and that unit ALREADY has an implementation uses clause
        at 2180-2200. Under --apply that writes a SECOND uses clause into the
        section, which does not compile. The keyword scan below cannot catch it:
        it looks for `implementation` and never asks whether a uses clause
        follows.
        Refusing here yields no edits, so the caller reports "No edit computed"
        and exits 1 -- the same shape as the KeywordLine=0 refusal just below.
        Pass a --db that indexes the target file (the PROJECT index) and the
        HaveLast branch above does the right thing instead. }
      if InFileId <= 0 then Exit;

      var KeywordLine: Integer:= 0;
      if TFile.Exists(AInFile) then
      begin
        var Raw: string:= TEncoding.ANSI.GetString(TFile.ReadAllBytes(AInFile));
        var SL: TStringList:= TStringList.Create;
        try
          SL.Text:= Raw;
          var WantImpl: Boolean:= (TargetSection = uusImplementation);
          for var I: Integer:= 0 to SL.Count - 1 do
          begin
            var T: string:= LowerCase(Trim(SL[I]));
            if WantImpl and (T = 'implementation') then begin KeywordLine:= I + 1; Break; end;
            if (not WantImpl) and (T = 'interface') then begin KeywordLine:= I + 1; Break; end;
          end;
        finally
          SL.Free;
        end;
      end;
      if KeywordLine = 0 then Exit; { cannot place safely }
      Edit.FilePath:= AInFile; Edit.Kind:= tekInsertLines;
      Edit.Line:= KeywordLine; Edit.Col:= 0; Edit.EndLine:= 0;
      Edit.Text:= ''#13#10'uses ' + Best + ';';
      Result:= [Edit];
    end;
  finally
    UsedSet.Free;
  end;
end;

function LastSeg(const S: string): string;
var P: Integer;
begin
  P:= LastDelimiter('.', S);
  if P > 0 then Result:= Copy(S, P + 1, MaxInt) else Result:= S;
end;

class function TSafeDeleteRefactoring.Build(const AStore: ISymbolStore;
  const AQName: string; out ARefuseReason: string): TArray<TTextEdit>;
var
  Syms        : TArray<TSymbol>  ;
  Sym         : TSymbol          ;
  Refs        : TArray<TReference>;
  Short       : string           ;
  Path        : string           ;
  Edits       : TList<TTextEdit> ;
  E           : TTextEdit        ;
  R           : TReference       ;
  ExternalRefs: Integer          ;
begin
  Result:= nil; ARefuseReason:= '';
  Syms:= AStore.FindSymbolsByQualifiedName(AQName);
  if Length(Syms) = 0 then begin ARefuseReason:= Format('symbol "%s" not found', [AQName]); Exit; end;
  Sym:= Syms[0];
  Short:= LastSeg(AQName);

  { Zero-reference check via name-text match (FindReferencesTo is unreliable:
    refs.symbol_id is NULL in the index, so it always returns empty). Any ref
    row returned by FindCallersByName that is NOT at exactly the declaration's
    (FileId, StartLine) is a real external usage. If ExternalRefs > 0, refuse. }
  Refs:= AStore.FindCallersByName(Short);
  ExternalRefs:= 0;
  for R in Refs do
    if not ((R.FileId = Sym.FileId) and (R.StartLine = Sym.StartLine)) then Inc(ExternalRefs);
  if ExternalRefs > 0 then
  begin
    ARefuseReason:= Format('"%s" has %d reference(s) -- refusing to delete', [AQName, ExternalRefs]);
    Exit;
  end;

  Path:= AStore.GetFilePath(Sym.FileId);
  if Path = '' then begin ARefuseReason:= 'declaration file path unknown'; Exit; end;

  Edits:= TList<TTextEdit>.Create;
  try
    { impl body first (higher line numbers), then declaration.
      The applier sorts back-to-front anyway, but emit in logical order. }
    if (Sym.ImplStartLine > 0) and (Sym.ImplEndLine >= Sym.ImplStartLine) then
    begin
      E.FilePath:= Path; E.Kind:= tekDeleteLines;
      E.Line:= Sym.ImplStartLine; E.EndLine:= Sym.ImplEndLine; E.Col:= 0; E.Text:= '';
      Edits.Add(E);
    end;
    if (Sym.StartLine > 0) and (Sym.EndLine >= Sym.StartLine) then
    begin
      E.FilePath:= Path; E.Kind:= tekDeleteLines;
      E.Line:= Sym.StartLine; E.EndLine:= Sym.EndLine; E.Col:= 0; E.Text:= '';
      Edits.Add(E);
    end;
    Result:= Edits.ToArray;
  finally
    Edits.Free;
  end;
end;

end.
