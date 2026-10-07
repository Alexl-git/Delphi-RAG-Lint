unit DRagLint.Convert.Rules;

{
  Track 3 (component conversion), Batch 1, Task 2 -- the reFind-SUPERSET
  conversion-rules DSL parser + validator that backs the CLI `convert-validate`
  verb (and, later, the convert-scaffold generator + an apply step in Batch 2+).

  The DSL is a strict superset of RAD Studio's reFind rule language (readme.txt
  section 3.2): it ADOPTS reFind's #unuse / #remove / #migrate directives and the
  raw-PCRE ' -> ' escape hatch verbatim, and ADDS four drag-lint directives that
  reFind lacks -- #convert / #link / #default / #note -- so a whole type-pair
  conversion (grouped deep-property assignments + a target uses-add + defaults +
  human notes) lives in one text file.

  Two totally-pure functions, NO I/O:
    * ParseConversionRules  -- TOTAL: never raises. Every input line is either a
      recognised rule, an ignored comment/blank, or a captured PARSE ERROR
      (unknown '#directive'). Parse errors ride on the ruleset's ParseErrors
      field; the validator surfaces them.
    * ValidateConversionRules -- the "we know the REAL properties" check reFind
      cannot do: #link / #default target/source paths are resolved, segment by
      segment, against the supplied From/To classes (TClassRef -- 1.20.6: a
      per-class member cache, no property tree is built). A literal '???'
      path is an explicit-unfilled STUB marker (the Batch-1 scaffolder emits
      these) and is NOT a hard error.

  READ-ONLY: no files, no globals, and no writes. Validation reads the index
  through the caller's TPropMemberCache; parsing touches nothing. Deterministic.
}

interface

uses
  System.SysUtils,
  DRagLint.Convert.PropCache;

const
  /// <summary>The smallest value '#depth N' accepts.</summary>
  MIN_BOOK_DEPTH = 1;
  /// <summary>The largest value '#depth N' accepts.</summary>
  MAX_BOOK_DEPTH = 10;
  /// <summary>The tree-expansion depth proptree and convert-scaffold use when
  /// neither --depth nor a --rules book's '#depth' names one.</summary>
  /// <remarks>Precedence: --depth N &gt; '#depth N' &gt; this. Depth is the
  /// class-recursion budget: a K-segment path needs depth &gt;= K-1.</remarks>
  DEFAULT_TREE_DEPTH = 5;

type
  /// <summary>The kind of a single parsed conversion rule.</summary>
  /// <remarks>
  /// rkUnuse=#unuse (drop a unit from the uses clause); rkRemove=#remove
  /// (drop a property from PAS+DFM, or DFM-only); rkMigrate=#migrate (replace an
  /// identifier, reFind's ' -&gt; ' form); rkConvert=#convert (declare the
  /// From-&gt;To type pair a block converts, adding target units); rkLink=#link
  /// (deep property assignment, ToPath '&lt;-' FromPath -- note the REVERSED
  /// arrow vs migrate); rkDefault=#default (set a target property to a value when
  /// no source maps); rkNote=#note (a human comment carried in the rule set);
  /// rkPcre=a raw non-'#' line containing ' -&gt; ' (the PCRE find/replace escape
  /// hatch); rkIgnore=#ignore (acknowledge an F property/event is intentionally
  /// NOT mapped -- suppresses the unmapped-non-default WARN for that FromPath).
  /// rkUse=#use (ADD a unit to the uses clause -- companion to #unuse).
  /// rkUseSwap=#useswap (replace Old with one-or-more New units; UnitName=Old,
  /// UnitsAdd=the New list; canonically #unuse Old + #use New...).
  /// rkMapping=#mapping (one line of a named, reusable conditional value map --
  /// a declaration, a #when branch, or a #else branch); rkApply=#apply (apply a
  /// named mapping within the enclosing #convert block's scope).
  /// rkDepth=#depth (the book's property-tree expansion depth for proptree and
  /// convert-scaffold; Depth holds the value; conversion ignores it).
  /// rkWarn=#warn (1.26.3: a book-authored warning when the SOURCE .dfm streams
  /// FromPath; Text holds the template; carries nothing). rkCheckRef=#check-ref
  /// (1.26.3: the converted ToPath value must name a value some .dfm of the
  /// project carries on a Class.Prop listed in RefTargets).
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Convert.Rules.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TRuleKind = (rkUnuse, rkRemove, rkMigrate, rkConvert, rkLink, rkDefault, rkNote, rkPcre, rkIgnore, rkUse, rkUseSwap,
               rkMapping, rkApply, rkDepth, rkWarn, rkCheckRef);

  /// <summary>One '&lt;ToPath&gt; = &lt;Value&gt;' assignment from a #mapping
  /// branch's set list.</summary>
  /// <remarks>
  /// ToPath keeps its dots -- 'Style.ModalResult.Default' is ONE path, never
  /// segments. Value is the raw target value text, verbatim. An item with no
  /// '=' yields a bare ToPath and an empty Value, which the editor accepts and
  /// so must this.
  /// Structurally identical to the converter editor's ConvRules.Model.TSetPair,
  /// and deliberately NOT shared with it: the two parsers ship independently
  /// (see the grammar-parity note in ParseConversionRules), and the engine must
  /// not take a dependency on an editor UI unit. The name differs so the two do
  /// not collide at interface level -- both units are members of drag-lint.dproj,
  /// so identical names would make TSetPair ambiguous by uses-clause order.
  /// A change to one must be mirrored in the other.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Convert.Rules.pas), DRagLint.CLI.DoConvertValidate.SetsSummary (DRagLint.CLI.pas), DRagLint.Convert.DfmReemit.ReemitBlock.ApplySets (DRagLint.Convert.DfmReemit.pas), DRagLint.Convert.Rules.ParseConversionRules.ParseSetList (DRagLint.Convert.Rules.pas), DRagLint.Convert.Rules.ValidateBlocks.CheckMapping (DRagLint.Convert.Rules.pas) (+1 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Convert.DfmReemit, DRagLint.Convert.Rules</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TMappingSetPair = record
    ToPath: string;
    Value : string;
  end;

  /// <summary>One parsed conversion rule. A flat record; only the fields relevant
  /// to <see cref="Kind"/> are populated (the rest stay '').</summary>
  /// <remarks>
  /// Field usage by Kind:
  /// rkUnuse -&gt; UnitName.
  /// rkRemove -&gt; PropName + DfmOnly (True for '#remove DFM: X').
  /// rkMigrate -&gt; Scope (optional 'Class:' or 'obj.' receiver prefix -- see
  /// below), Old (the LHS identifier), New (the RHS identifier), UnitsAdd
  /// (0+ trailing uses-units).
  /// rkConvert -&gt; FromType, ToType, UnitsAdd (0+ target units to add).
  /// rkLink -&gt; ToPath (LHS of '&lt;-'), FromPath (RHS of '&lt;-'), Cast and
  /// GlyphExpr (both optional, split off the RHS).
  /// rkDefault -&gt; ToPath, Value (RHS of '=').
  /// rkNote -&gt; Text.
  /// rkPcre -&gt; Search (LHS of ' -&gt; '), Replace (RHS).
  /// rkIgnore -&gt; FromPath (the F property/event path to leave unmapped, no warn).
  /// LineNo is the 1-based source line the rule was parsed from.
  /// SCOPE-FOLD CHOICE for #migrate: reFind allows an optional '&lt;Class&gt; :'
  /// class-scope and/or an optional '&lt;obj&gt; .' object-scope before the old
  /// identifier. We fold BOTH into a single Scope string kept verbatim (e.g.
  /// 'TForm1:' or 'DataSet.' or 'TForm1: DataSet.'); Old holds only the bare
  /// old identifier after the last such prefix. This preserves the receiver
  /// intent without over-modelling it in Batch 1 (validation ignores Scope).
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.BuildBlockClasses (DRagLint.CLI.pas), DRagLint.CLI.ConvertApplyComponentPart (DRagLint.CLI.pas), DRagLint.CLI.DoConvertValidate (DRagLint.CLI.pas), DRagLint.Convert.Apply.CheckFreshness (DRagLint.Convert.Apply.pas), DRagLint.Convert.Apply.FindConvertRuleFor (DRagLint.Convert.Apply.pas) (+28 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Convert.Apply, DRagLint.Convert.DfmReemit, DRagLint.Convert.Rules, DRagLint.Convert.UnitRules</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TConversionRule = record
    Kind: TRuleKind;
    FromType, ToType, ToPath, FromPath, Old, New, Scope, UnitName, PropName, Value, Text, Search, Replace: string;
    UnitsAdd: TArray<string>;
    DfmOnly : Boolean;
    LineNo  : Integer;
    /// <summary>rkLink only: the optional `: CastFn` suffix on the FromPath side
    /// ('' = identity). Captured so it stops corrupting FromPath; NOT yet
    /// performed by convert-apply, which refuses to rewrite a link carrying one
    /// rather than silently dropping the conversion.</summary>
    Cast    : string;
    /// <summary>rkLink only: the optional glyph expression after the FromPath
    /// ('G[*/4], G[1/5]G[2/5]', see DRagLint.Convert.GlyphExpr), kept VERBATIM;
    /// '' = none. Split off at the first ' G[' AFTER the cast suffix, so
    /// FromPath is the bare source property the tree check expects. Validated by
    /// ValidateConversionRules; NOT yet realised by convert-apply, which refuses
    /// a book carrying one (UnrealisedGlyphLinks) rather than carry the source
    /// image whole.</summary>
    GlyphExpr: string;
    /// <summary>rkMapping/rkApply: the mapping's name. This is the ONLY thing
    /// tying a declaration, its #when branches and its #else together -- they
    /// are three flat sibling lines, not a nested block.</summary>
    MapName : string;
    /// <summary>rkMapping declaration only: the source enum type after 'from',
    /// and the target class list after 'to' (top-level-comma split, so a generic
    /// 'Unit.TList&lt;A, B&gt;' stays ONE entry).</summary>
    MapFromType: string;
    MapToTypes : TArray<string>;
    /// <summary>rkMapping #when only: the condition '&lt;WhenFrom&gt; =
    /// &lt;WhenValue&gt;'. A #when with no '=' leaves WhenValue empty and keeps
    /// the whole condition in WhenFrom -- the editor accepts that shape, so the
    /// engine must too (see ParseConversionRules' grammar-parity remark).</summary>
    WhenFrom : string;
    WhenValue: string;
    /// <summary>rkMapping only: True for the '#else' branch.</summary>
    IsElse   : Boolean;
    /// <summary>rkMapping #when/#else: the assignments right of '-&gt;'.</summary>
    Sets     : TArray<TMappingSetPair>;
    /// <summary>rkDepth only: the '#depth N' value, always 1..10 (an
    /// out-of-range or non-integer value is a parse error and makes no
    /// rule).</summary>
    Depth    : Integer;
    /// <summary>rkCheckRef only: the '&lt;Class&gt;.&lt;Prop&gt;' targets after
    /// the ToPath, in book order; the LAST dot splits class from
    /// property.</summary>
    RefTargets: TArray<string>;
  end;

  /// <summary>One parse-or-validation error, anchored to a source line.</summary>
  /// <remarks>
  /// LineNo is the 1-based source line; Message is a human-readable,
  /// ASCII-only description (e.g. 'unknown directive: #frobnicate' or
  /// 'link ToPath not found in --to tree: Bogus.Path').
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.CLI.pas), DRagLint.CLI.DoConvertReemit (DRagLint.CLI.pas), DRagLint.CLI.DoConvertValidate (DRagLint.CLI.pas), DRagLint.CLI.EmitApplyJson (DRagLint.CLI.pas), DRagLint.CLI.ResolveTreeDepth (DRagLint.CLI.pas) (+10 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Convert.Rules</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TRuleError = record
    LineNo : Integer;
    Message: string;
    /// <summary>True when the error is about the book's '#depth' (invalid
    /// value, or a second '#depth'). proptree / convert-scaffold key on it to
    /// refuse a broken book (exit 2) while ignoring its other parse errors --
    /// a structural signal, never a match on Message text.</summary>
    IsDepthError: Boolean;
  end;

  /// <summary>The full parsed rule set: the recognised rules plus any parse
  /// errors captured while reading them.</summary>
  /// <remarks>
  /// Rules holds every RECOGNISED rule in source order. ParseErrors
  /// holds one entry per UNKNOWN '#directive' line (or other total-parser
  /// rejection) -- the parser NEVER raises, so a malformed input still yields a
  /// well-formed ruleset with the problems recorded here. ValidateConversionRules
  /// folds these ParseErrors into its returned error list, so a caller that runs
  /// the validator sees parse + validation problems together. (ADDED FIELD vs the
  /// Task-2 brief's minimal shape -- documented as acceptable there; Task 3 reads
  /// Rules and may inspect ParseErrors but is not broken by its presence.)
  /// Depth is the book's '#depth N' (1..10), 0 when the book has none or its
  /// only '#depth' line was invalid; DepthLine is that line (0 = none). It is
  /// the tree-expansion depth for proptree / convert-scaffold --rules, below an
  /// explicit --depth and above the default 5. Conversion and validation
  /// resolve paths lazily and never read it. At most one '#depth' per book: a
  /// second one is a parse error on its own line and the first one stands.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Convert.Apply.pas), DRagLint.CLI.DoConvertApply (DRagLint.CLI.pas), DRagLint.CLI.DoConvertReemit (DRagLint.CLI.pas), DRagLint.CLI.DoConvertValidate (DRagLint.CLI.pas), DRagLint.CLI.ResolveTreeDepth (DRagLint.CLI.pas) (+7 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Convert.Apply, DRagLint.Convert.DfmReemit, DRagLint.Convert.Rules, DRagLint.Convert.UnitRules</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TConversionRuleSet = record
    Rules      : TArray<TConversionRule>;
    ParseErrors: TArray<TRuleError>;
    Depth      : Integer;
    DepthLine  : Integer;
  end;

  /// <summary>The From and To classes of one #convert block, as
  /// ValidateConversionRulesPerBlock consumes them.</summary>
  /// <remarks>
  /// Each side is a qualified class name plus the member cache of the store it
  /// resolved in (the two may be different --db stores). A side that is unset
  /// or does not resolve (RootType='') skips the checks against it, exactly as
  /// in ValidateConversionRules. It means "not checked here", never "checked
  /// and fine": a caller that WANTS a block checked and cannot resolve its type
  /// must report that itself (convert-apply's BuildBlockClasses raises an error
  /// on the block's #convert line). Callers build one per block, index-aligned
  /// with the book's blocks: [0] is the region before the first #convert (no
  /// block, normally both sides unset), [N] the Nth #convert in source order.
  /// 1.20.6 (T2b): replaced TBlockTrees -- no property tree is built; each path
  /// is resolved segment by segment (TPropMemberCache.ResolvePath, psDfm).
  /// </remarks>
  TBlockClasses = record
    FromClass: TClassRef;
    ToClass  : TClassRef;
  end;

  /// <summary>A rule path that names members which EXIST but are inaccessible
  /// on the .dfm surface -- a WARNING, never an error (owner ruling R12,
  /// 2026-09-30).</summary>
  /// <remarks>
  /// Like `if 1 > 2 then`: such a rule can never execute, because no .dfm
  /// streams the member, unless a descendant class (e.g. `TMyTable =
  /// class(TTable)`) raises its visibility. The rule is KEPT in the book and
  /// skipped when converting (WithoutUnreachableRules).
  /// LineNo is the rule's book line; Path the path as written; Member,
  /// Visibility and DeclaringClass name the first offending segment (see
  /// TPathResolution). Message is the whole text line every surface prints,
  /// exactly: 'line N: warning: &lt;Path&gt;: &lt;Member&gt; is
  /// &lt;Visibility&gt; in &lt;DeclaringClass&gt;; never applied unless a
  /// descendant class changes its visibility'.
  /// Block is the #convert block (ConvertBlocks numbering) whose class made the
  /// path unreachable, and IsWhen marks a #mapping line's #when SOURCE path (as
  /// opposed to a target it sets); both drive WithoutUnreachableRules and are
  /// never emitted. A #mapping line checked in several blocks has one record
  /// per block it is unreachable in, so one message can appear more than once
  /// -- print through DistinctUnreachable.
  /// </remarks>
  TUnreachablePath = record
    LineNo        : Integer;
    Path          : string;
    Member        : string;
    Visibility    : string;
    DeclaringClass: string;
    Message       : string;
    Block         : Integer;
    IsWhen        : Boolean;
  end;

/// <summary>True when S is one or more ASCII decimal digits and nothing
/// else.</summary>
/// <param name="S">The text to test, untrimmed.</param>
/// <returns>False for '', a sign ('+3', '-1'), a '$' hex prefix ('$A'), a
/// blank, a decimal point -- every form StrToInt / TryStrToInt alone would
/// accept or half-accept.</returns>
/// <remarks>The one strict integer check shared by '#depth N', the CLI's
/// --depth (proptree / convert-scaffold) and --progress-interval, so the
/// three can never disagree about what a number is.</remarks>
function IsDecimalDigits(const S: string): Boolean;

/// <summary>Parses the reFind-superset conversion-rules DSL text into a rule set.
/// TOTAL: never raises -- an unknown '#directive' becomes a captured ParseError,
/// never an exception.</summary>
/// <param name="AText">The raw rules text (CRLF or LF line endings both accepted).
/// Blank lines and lines starting with '//' or ';' are ignored.</param>
/// <returns>A TConversionRuleSet whose Rules are the recognised rules (each with
/// its 1-based LineNo) and whose ParseErrors carry any unknown-directive lines.
/// An empty/whitespace-only input yields empty Rules and empty ParseErrors.</returns>
/// <remarks>
/// Directive grammar (all case-INSENSITIVE on the leading '#word'):
/// '#use &lt;unit&gt;' (add a unit); '#useswap &lt;Old&gt; -&gt; &lt;New1&gt; [, &lt;New2&gt; ...]' (replace a unit with one-or-more units);
/// '#unuse &lt;unit&gt;'; '#remove &lt;prop&gt;' / '#remove DFM: &lt;prop&gt;'
/// (DFM-only); '#migrate [&lt;Class&gt; :] [&lt;obj&gt; .] &lt;old&gt; -&gt;
/// &lt;new&gt; [, &lt;unit&gt; ...]'; '#convert &lt;FromType&gt; -&gt;
/// &lt;ToType&gt; [, &lt;unit&gt; ...]'; '#link &lt;ToPath&gt; &lt;- &lt;FromPath&gt;
/// [&lt;G-expr&gt;] [: &lt;Cast&gt;]' (note the '&lt;-' arrow; the cast is split
/// off first, then the glyph expression at the first ' G[' -- see
/// TConversionRule.GlyphExpr); '#default &lt;ToPath&gt; = &lt;value&gt;';
/// '#note &lt;text&gt;'; '#ignore &lt;FromPath&gt;' (acknowledge an F property is
/// intentionally unmapped -- suppresses its unmapped-non-default warning);
/// '#depth &lt;N&gt;' (the book's tree-expansion depth, decimal digits 1..10,
/// one per book -- out of range, non-numeric or a second '#depth' is a
/// ParseError on that line; see TConversionRuleSet.Depth).
/// R27 (1.20.6): a From-only header -- '#convert TFoo -&gt; ' or '#convert
/// TFoo', the form the editor writes while authoring -- still parses as a
/// rule with FromType 'TFoo' and an EMPTY ToType (never 'TFoo -&gt;'), and is a
/// ParseError on its line: '#convert TFoo has no To type'. Likewise
/// '#useswap X -&gt; ' (no New unit): '#useswap X has no replacement unit'.
/// A NON-'#' line containing ' -&gt; ' is a raw PCRE
/// rule (Search -&gt; Replace). Any other '#word' is an unknown directive
/// recorded in ParseErrors. Pure; deterministic; no I/O.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoConvertApply (DRagLint.CLI.pas), DRagLint.CLI.DoConvertReemit (DRagLint.CLI.pas), DRagLint.CLI.DoConvertValidate (DRagLint.CLI.pas), DRagLint.CLI.ResolveTreeDepth (DRagLint.CLI.pas)</para>
/// <para>Calls: CharInSet, Copy, Default, DRagLint.Convert.Rules.IsDecimalDigits, DRagLint.Convert.Rules.ParseConversionRules.AddError, DRagLint.Convert.Rules.ParseConversionRules.AddRule, DRagLint.Convert.Rules.ParseConversionRules.Directive, DRagLint.Convert.Rules.ParseConversionRules.ParseMappingDirective, DRagLint.Convert.Rules.SplitCastSuffix, DRagLint.Convert.Rules.SplitGlyphExpr (+14 more)</para>
/// <para>Complexity: 34 (cyclomatic, outer body), 483 lines (full implementation)</para>
/// <seealso cref="DRagLint.Convert.Rules.IsDecimalDigits"/>
/// <seealso cref="DRagLint.Convert.Rules.ParseConversionRules.AddError"/>
/// <seealso cref="DRagLint.Convert.Rules.ParseConversionRules.AddRule"/>
/// <seealso cref="DRagLint.Convert.Rules.ParseConversionRules.Directive"/>
/// <seealso cref="DRagLint.Convert.Rules.ParseConversionRules.ParseMappingDirective"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ParseConversionRules(const AText: string): TConversionRuleSet;

/// <summary>Validates a parsed rule set against the real members of the From and
/// To classes, catching path typos reFind cannot -- plus folding in any parse
/// errors from ParseConversionRules.</summary>
/// <param name="ARules">The parsed rule set (its ParseErrors are included in the
/// result).</param>
/// <param name="AFrom">The FromType. May be unset or unresolved (RootType='') to
/// skip source-path checks.</param>
/// <param name="ATo">The ToType. May be unset or unresolved to skip target-path
/// checks.</param>
/// <param name="AUnreachable">Receives the paths that EXIST but fail the
/// surface (TUnreachablePath), in source order, at most one per (line, path,
/// offending member, declaring class); never errors.</param>
/// <returns>Zero-length array = valid. Otherwise one TRuleError per problem, in
/// source order (parse errors first, then validation errors).</returns>
/// <remarks>
/// Checks performed: for each rkLink, ToPath must resolve from ATo and FromPath
/// from AFrom; for each rkDefault, ToPath must resolve from ATo. A path resolves
/// segment by segment on the DFM surface (TPropMemberCache.ResolvePathEx, psDfm --
/// ruling R8: a published leaf; each hop published, or public and class-typed;
/// never private), with no depth limit (1.20.6: no property tree is built, so
/// --depth no longer applies). A path whose every segment exists but fails R8
/// is UNREACHABLE (owner ruling R12): it goes to AUnreachable, not to the
/// errors; only a segment naming nothing is a "not found" error. A path equal to the literal
/// '???' is an explicit-unfilled STUB marker (emitted by the Batch-1 scaffolder)
/// and is SKIPPED -- never a hard error -- so scaffolder output validates clean.
/// When a side does not resolve (RootType=''), the checks against it are skipped
/// (parse-only / tree-less mode). rkConvert type pairs are informational and are
/// NEVER hard-failed (a rename mismatch is not a path error). Other kinds
/// (rkUnuse/rkRemove/rkMigrate/rkNote/rkPcre) are not path-checked in Batch 1.
/// rkIgnore is not path-checked either -- a #ignore for a non-existent F path is
/// tolerated (it simply matches nothing), never a hard error.
/// A #link carrying a glyph expression is checked by ParseGlyphExpr and
/// ValidateGlyphExpr (errors name the expression column), and a 'G[count]' link
/// must have exactly one image link from the same FromPath in its #convert
/// block. These checks need no class, so they also run in parse-only mode.
/// Deterministic; reads the index through the classes' caches; writes nothing.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoConvertReemit (DRagLint.CLI.pas), DRagLint.CLI.DoConvertValidate (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.Convert.Rules.ValidateBlocks</para>
/// <para>Returns: ValidateBlocks(ARules, Classes, False, AUnreachable)</para>
/// <seealso cref="DRagLint.Convert.Rules.ValidateBlocks"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ValidateConversionRules(const ARules: TConversionRuleSet;
  const AFrom, ATo: TClassRef; out AUnreachable: TArray<TUnreachablePath>): TArray<TRuleError>;

/// <summary>Validates a parsed rule set BLOCK BY BLOCK: each #convert block's
/// #link and #default paths against that block's own From/To classes, and each
/// #mapping line against the classes of the block(s) that #apply it -- plus the
/// class-less checks and parse errors ValidateConversionRules reports.</summary>
/// <param name="ARules">The parsed rule set (its ParseErrors are included in the
/// result).</param>
/// <param name="ABlockClasses">One TBlockClasses per block, index-aligned with
/// the book: [0] is the region before the first #convert, [N] the Nth #convert
/// block in source order. An index past the end counts as two unset sides
/// (checks skipped).</param>
/// <param name="AUnreachable">Receives the UNREACHABLE paths (owner ruling
/// R12), in source order, at most one per (line, path, offending member,
/// declaring class) however many blocks check that line; the message carries
/// no block suffix.</param>
/// <returns>Zero-length array = valid. Otherwise one TRuleError per problem:
/// parse errors first, then validation errors in source order. Each path error
/// carries ValidateConversionRules' message followed by the block it was
/// checked in, ' (#convert line N: From -&gt; To)'.</returns>
/// <remarks>
/// Why it exists: convert-apply used to check a whole multi-block book against
/// the FIRST block's two types, so every link of blocks 2..N failed
/// (convrules\BDE-to-FireDAC.rules: 540 errors). convert-validate, which takes
/// one --from/--to pair, keeps ValidateConversionRules.
/// Mapping scope: an #apply belongs to the nearest #convert above it. A #mapping
/// line is checked against every block that applies its name (and may report
/// once per such block); a mapping no block applies is checked against the
/// block it sits in, and is NOT tree-checked when it sits before the first
/// #convert -- there is no class it could be checked against. A #link or
/// #default before the first #convert is checked against ABlockClasses[0].
/// Paths resolve as in ValidateConversionRules (psDfm, ruling R8).
/// Deterministic; reads the index through the classes' caches; writes nothing.
/// </remarks>
function ValidateConversionRulesPerBlock(const ARules: TConversionRuleSet;
  const ABlockClasses: TArray<TBlockClasses>; out AUnreachable: TArray<TUnreachablePath>): TArray<TRuleError>;

/// <summary>The rule set one #convert block actually RUNS: its UNREACHABLE
/// paths taken out (owner ruling R12: such a rule is skipped, never applied)
/// without disturbing any #mapping's branch order.</summary>
/// <param name="ARules">The parsed rule set.</param>
/// <param name="AUnreachable">What validation reported
/// (ValidateConversionRules / ValidateConversionRulesPerBlock).</param>
/// <param name="ABlock">The #convert block being run (ConvertBlocks
/// numbering: 1 = the first #convert); 0 or less = no block (only the
/// #link / #default removal applies -- the .pas access-site pass).</param>
/// <returns>A copy of ARules; every kept rule's order and LineNo unchanged,
/// ParseErrors kept.</returns>
/// <remarks>
/// #link / #default: a line with an unreachable path is removed. Each such
/// line is validated in exactly ONE block (its own), so this is already
/// per-block; it is removed whatever ABlock is -- a dead rule stays dead in
/// the book-wide leak ReemitComponent has for #link too.
/// #mapping (per block, only records with Block = ABlock): an unreachable
/// TARGET is stripped from that line's set list and the line is KEPT, so a
/// value matching that branch still sets its reachable targets and never
/// falls through to a later #when or #else. An unreachable #when SOURCE
/// (IsWhen) removes EVERY line of that mapping (declaration, every #when, the
/// #else) for this block: the branch can never match, and letting a later
/// branch or #else fire in its place would write a value nobody chose -- the
/// conservative reading (controller fix round 1). Its #apply stays and finds
/// nothing to evaluate. The #convert headers, #apply and the unit rules are
/// never touched, so block numbering is unchanged. Pure.
/// </remarks>
function WithoutUnreachableRules(const ARules: TConversionRuleSet;
  const AUnreachable: TArray<TUnreachablePath>; ABlock: Integer): TConversionRuleSet;

/// <summary>The property names a #warn text references as brace placeholders
/// (1.26.3).</summary>
/// <param name="AText">The #warn template text.</param>
/// <returns>Each name between an opening and the next closing brace that is a
/// valid (dotted) identifier, in text order, duplicates kept; empty when
/// none. The literal placeholders &lt;value&gt; and &lt;name&gt; are not brace
/// forms and never appear here.</returns>
/// <remarks>Pure. convert-validate checks every name against the block's From
/// type; the re-emit reads each from the source block.</remarks>
function WarnPlaceholders(const AText: string): TArray<string>;

/// <summary>AUnreachable with each message once, in first-seen order -- what
/// every surface prints and emits.</summary>
/// <param name="AUnreachable">Validation's records (several per message
/// when a #mapping line is unreachable in several blocks).</param>
/// <returns>The first record of each distinct Message. Pure.</returns>
function DistinctUnreachable(const AUnreachable: TArray<TUnreachablePath>): TArray<TUnreachablePath>;

/// <summary>Non-fatal findings on a parsed rule set: things that validate but
/// are almost certainly not what the author meant.</summary>
/// <param name="ARules">The parsed rule set.</param>
/// <returns>One TRuleError per warning, in source order; empty when there is
/// nothing to say. A warning never makes a rule set invalid.</returns>
/// <remarks>
/// Today one warning (G-grammar design 3.3): a straight #link of a glyph-count
/// property (IsGlyphCountPropName on the FromPath, e.g. 'NumGlyphs') in the same
/// #convert block as a G image link. That carry is right for identity
/// alternatives only; the author almost certainly means 'G[count]'. Needs no
/// property tree. Pure; deterministic; no I/O.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoConvertValidate (DRagLint.CLI.pas)</para>
/// <para>Calls: Default, DRagLint.Convert.GlyphExpr.IsGlyphCountPropName, DRagLint.Convert.Rules.ConvertBlocks, DRagLint.Convert.Rules.IsGlyphImageLink, Format</para>
/// <seealso cref="DRagLint.Convert.GlyphExpr.IsGlyphCountPropName"/>
/// <seealso cref="DRagLint.Convert.Rules.ConvertBlocks"/>
/// <seealso cref="DRagLint.Convert.Rules.IsGlyphImageLink"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ConversionRuleWarnings(const ARules: TConversionRuleSet): TArray<TRuleError>;

/// <summary>The #link rules convert-apply cannot perform yet because they
/// carry a glyph expression.</summary>
/// <param name="ARules">The parsed rule set.</param>
/// <returns>One TRuleError per #link whose GlyphExpr is set, in source order;
/// empty when the book has none.</returns>
/// <remarks>
/// convert-validate accepts a valid G-expression (CV-4), but extracting and
/// stitching the slots is CV-2's build. Until it lands, convert-apply refuses
/// a book listed here instead of carrying the source image WHOLE, which the
/// owner's ruling forbids ("never fall back to carry-whole"). CV-2 retires this
/// function when it realises the links. Pure; deterministic; no I/O.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoConvertReemit (DRagLint.CLI.pas), DRagLint.CLI.ValidateConvertBook (DRagLint.CLI.pas)</para>
/// <para>Calls: Default, Format</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function UnrealisedGlyphLinks(const ARules: TConversionRuleSet): TArray<TRuleError>;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  DRagLint.Convert.GlyphExpr;

const
  ARROW_MIGRATE = ' -> ';  // #migrate / #convert / raw PCRE separator
  ARROW_LINK    = ' <- ';  // #link separator (reversed)
  STUB_MARKER   = '???';   // explicit-unfilled path stub (skip validation)

function IsDecimalDigits(const S: string): Boolean;
var
  C: Char;
begin
  Result:= S <> '';
  for C in S do
    if not CharInSet(C, ['0'..'9']) then Exit(False);
end;

// Split raw text into lines on CRLF or LF (a total, allocation-light splitter).
function SplitLines(const AText: string): TArray<string>;
var
  Norm: string;
begin
  Norm:= StringReplace(AText, #13#10, #10, [rfReplaceAll]);
  Norm:= StringReplace(Norm , #13   , #10, [rfReplaceAll]);
  Result:= Norm.Split([#10]);
end;

// Parse a trailing ', U [, U ...]' unit list from the RHS of a migrate/convert
// rule. AInput is the whole RHS (e.g. 'TFDTable, FireDAC.Comp.Client'); the head
// (first comma-separated element, trimmed) is returned via AHead, and every
// remaining non-empty trimmed element becomes a UnitsAdd entry.
procedure SplitHeadAndUnits(const AInput: string; out AHead: string;
  out AUnits: TArray<string>);
var
  Parts: TArray<string>;
  i    : Integer       ;
  U    : TList<string> ;
  T    : string        ;
begin
  AHead := '';
  AUnits:= nil;
  Parts := AInput.Split([',']);
  if Length(Parts) = 0 then Exit;
  AHead:= Trim(Parts[0]);
  U:= TList<string>.Create;
  try
    for i:= 1 to High(Parts) do
    begin
      T:= Trim(Parts[i]);
      if T <> '' then U.Add(T);
    end;
    AUnits:= U.ToArray;
  finally
    U.Free;
  end;
end;

// For #migrate: peel any leading 'Class :' and/or 'obj .' scope prefixes off the
// LHS, folding what we peel (verbatim, whitespace-normalised) into AScope and
// leaving the bare old identifier in AOld. Pragmatic: we recognise a ' : '
// class-scope and a '.' object-scope; anything before the last such marker is
// scope, the remainder is Old.
procedure SplitMigrateLhs(const ALhs: string; out AScope, AOld: string);
var
  S      : string ;
  ColonAt: Integer;
  DotAt  : Integer;
begin
  AScope:= '';
  S     := Trim(ALhs);
  // Class-scope: '<Class> :' -- take up to and including the last ' :'.
  ColonAt:= S.LastIndexOf(':') + 1; // 1-based position, 0 if absent
  if ColonAt > 0 then
  begin
    AScope:= Trim(Copy(S, 1, ColonAt)); // includes the ':'
    S     := Trim(Copy(S, ColonAt + 1, MaxInt));
  end;
  // Object-scope: '<obj> .<old>' -- fold the receiver+'.' into Scope too.
  DotAt:= S.LastIndexOf('.') + 1; // 1-based, 0 if absent
  if DotAt > 0 then
  begin
    if AScope <> '' then AScope:= AScope + ' ' + Trim(Copy(S, 1, DotAt))
    else                 AScope:= Trim(Copy(S, 1, DotAt)); // includes the '.'
    S:= Trim(Copy(S, DotAt + 1, MaxInt));
  end;
  AOld:= Trim(S);
end;

{ Splits the optional `: CastFn` suffix off a #link FromPath.

  WHY THIS EXISTS. The engine's parser had no cast field at all, so
  `#link Size <- Size : Round` produced the literal FromPath `Size : Round`,
  which resolves against nothing -- and validation then reported the user's
  VALID line as a missing path:

      line 6: link FromPath not found in --from tree: Size : Round

  That fires on `convrules\sample.rules`, a file this repo SHIPS.
  `--print-parsed` made it worse by echoing `link Size <- Size : Round`, which
  reads as though the cast had been captured; it was echoing the corruption.

  THE PREDICATE IS THE EDITOR'S, DELIBERATELY. ConvRules.Model.pas already
  parses and re-emits this suffix correctly (search that unit for `N.Cast`), and
  the editor ROUND-TRIPS rule books. Two different notions of "is this a cast"
  would mean the editor and the engine disagree about the same file, and the
  failure mode of that is silent DATA LOSS on save -- so this mirrors it exactly
  rather than inventing a second rule: split on the LAST colon, and accept the
  tail only when it is a single bare identifier (no space, no dot, no '<'). A
  path that merely contains a colon is therefore left alone. }
procedure SplitCastSuffix(var APath: string; out ACast: string);
var
  ColonAt: Integer;
  Tail   : string ;
begin
  ACast:= '';
  ColonAt:= LastDelimiter(':', APath);
  if ColonAt <= 0 then Exit;
  Tail:= Trim(Copy(APath, ColonAt + 1, MaxInt));
  if (Tail = '') or (Pos(' ', Tail) > 0) or (Pos('.', Tail) > 0) or (Pos('<', Tail) > 0) then Exit;
  ACast:= Tail;
  APath:= Trim(Copy(APath, 1, ColonAt - 1));
end;

{ Splits an optional glyph expression off a #link FromPath (G-grammar design
  3.1): everything from the first ' G[' on is the expression, kept verbatim; a
  FromPath never contains ' G[' itself. Runs AFTER SplitCastSuffix, so
  'Picture G[*/4] : AssignGraphic' has already lost its cast. }
procedure SplitGlyphExpr(var APath: string; out AGlyphExpr: string);
const
  GlyphMarker = ' G[';
var
  At: Integer;
begin
  AGlyphExpr:= '';
  At:= Pos(GlyphMarker, APath);
  if At <= 0 then Exit;
  AGlyphExpr:= Trim(Copy(APath, At + 1, MaxInt));
  APath     := Trim(Copy(APath, 1, At - 1));
end;

function ParseConversionRules(const AText: string): TConversionRuleSet;
var
  Lines : TArray<string>       ;
  Rules : TList<TConversionRule>;
  Errs  : TList<TRuleError>    ;
  LineNo: Integer              ;
  Raw   : string               ;
  Line  : string               ;
  Low   : string               ;
  { True once a '#convert' has been seen. '#tag' is scoped to the enclosing
    #convert block, so a '#tag' before the first one is an error rather than a
    silent no-op -- see the '#tag' arm below. }
  SeenConvert: Boolean;
  { The book's '#depth N' and its line (0 = none yet); see TConversionRuleSet. }
  BookDepth    : Integer;
  BookDepthLine: Integer;

  procedure AddError(const AMsg: string; AIsDepth: Boolean = False);
  var
    E: TRuleError;
  begin
    E             := Default(TRuleError);
    E.LineNo      := LineNo;
    E.Message     := AMsg;
    E.IsDepthError:= AIsDepth;
    Errs.Add(E);
  end;

  // Returns True + the argument text if Line starts with the (case-insensitive)
  // directive keyword AKey ('#unuse' etc.) followed by whitespace or end.
  function Directive(const AKey: string; out AArg: string): Boolean;
  var
    KLen: Integer;
  begin
    AArg := '';
    KLen := Length(AKey);
    Result:= (Length(Line) >= KLen) and
             SameText(Copy(Line, 1, KLen), AKey) and
             ((Length(Line) = KLen) or CharInSet(Line[KLen + 1], [' ', #9]));
    if Result then AArg:= Trim(Copy(Line, KLen + 1, MaxInt));
  end;

  { -- #mapping helpers, PORTED VERBATIM from the converter editor
    (ConvRules.Model.pas SplitTopLevelCommas / ParseSetList / SplitBareArrow).

    THE ENGINE'S GRAMMAR MUST BE NO STRICTER THAN THE EDITOR'S. The editor
    ROUND-TRIPS rule books: it parses a file, lets the user edit, and re-emits
    every line. If the engine rejects a line the editor accepts, the editor's
    save-validate fails and RULES ARE SILENTLY LOST. Two independent notions of
    "is this well-formed" is the failure mode; one shared one is the fix. Any
    change here must be mirrored there, and vice versa. }

  { Split S on TOP-LEVEL commas. A comma nested in (), [] or <>, or inside a
    quoted string, is part of one item and does not separate items -- so a
    generic target class ('Unit.TList<A, B>') stays one entry. Blank items are
    dropped. Tradeoff (the editor's, kept): '<' is treated as an opener, so an
    unbalanced '<' would swallow the commas after it; generics are far likelier
    here than a bare '<' in a class name or an enum value. }
  function SplitTopLevelCommas(const S: string): TArray<string>;
  var
    L    : TList<string>;
    i    : Integer      ;
    Depth: Integer      ;
    InStr: Boolean      ;
    Start: Integer      ;
    Item : string       ;
  begin
    L := TList<string>.Create;
    try
      Depth := 0;
      InStr := False;
      Start := 1;
      for i := 1 to Length(S) do
      begin
        case S[i] of
          '''': InStr := not InStr;
          '(', '[', '<': if not InStr then Inc(Depth);
          ')', ']', '>': if (not InStr) and (Depth > 0) then Dec(Depth);
          ',':
            if (not InStr) and (Depth = 0) then
            begin
              Item := Trim(Copy(S, Start, i - Start));
              if Item <> '' then L.Add(Item);
              Start := i + 1;
            end;
        end;
      end;
      Item := Trim(Copy(S, Start, MaxInt));
      if Item <> '' then L.Add(Item);
      Result := L.ToArray;
    finally
      L.Free;
    end;
  end;

  { Parse a #mapping clause's set list -- '<ToPath> = <Value>[, ...]' -- into
    pairs. Each item splits on its FIRST '=' so a value containing '=' survives
    whole, and ToPath keeps its dots ('Style.ModalResult.Default' is one path,
    never segments). An item with no '=' yields a bare ToPath with an empty
    Value. }
  function ParseSetList(const S: string): TArray<TMappingSetPair>;
  var
    L   : TList<TMappingSetPair>;
    Item: string         ;
    P   : Integer        ;
    Pair: TMappingSetPair       ;
  begin
    L := TList<TMappingSetPair>.Create;
    try
      for Item in SplitTopLevelCommas(S) do
      begin
        P := Pos('=', Item);
        if P > 0 then
        begin
          Pair.ToPath := Trim(Copy(Item, 1, P - 1));
          Pair.Value  := Trim(Copy(Item, P + 1, MaxInt));
        end
        else
        begin
          Pair.ToPath := Item;
          Pair.Value  := '';
        end;
        L.Add(Pair);
      end;
      Result := L.ToArray;
    finally
      L.Free;
    end;
  end;

  { Split on the FIRST bare '->', with or without the surrounding spaces -- a
    #mapping clause writes '#else -> x', where the arrow has no space to its
    left. }
  function SplitBareArrow(const S: string; out L, R: string): Boolean;
  var
    Q: Integer;
  begin
    L := '';
    R := '';
    Q := Pos('->', S);
    Result := Q > 0;
    if Result then
    begin
      L := Trim(Copy(S, 1, Q - 1));
      R := Trim(Copy(S, Q + 2, MaxInt));
    end;
  end;

  procedure AddRule(const ARule: TConversionRule);
  var
    R: TConversionRule;
  begin
    R:= ARule;
    R.LineNo:= LineNo;
    Rules.Add(R);
  end;

  { 1.26.3: '#warn <FromPath> "<text>"'. The path is the first token; the text
    runs from the first double quote to the LAST one, so a quote inside the
    text needs no escape. Anything else is a line error and makes no rule. }
  procedure ParseWarnDirective(const AArg: string);
  const
    QUOTE = '"';
  var
    W    : TConversionRule;
    SpAt : Integer;
    Rest : string;
  begin
    W:= Default(TConversionRule);
    W.Kind:= rkWarn;
    SpAt:= Pos(' ', AArg);
    if SpAt > 0 then
    begin
      W.FromPath:= Trim(Copy(AArg, 1, SpAt - 1));
      Rest      := Trim(Copy(AArg, SpAt + 1, MaxInt));
    end
    else
    begin
      W.FromPath:= Trim(AArg);
      Rest      := '';
    end;
    if (W.FromPath = '') or W.FromPath.StartsWith(QUOTE) or (Length(Rest) < 2) or
       not Rest.StartsWith(QUOTE) or not Rest.EndsWith(QUOTE) then
    begin
      AddError('#warn needs <FromPath> "<text>"');
      Exit;
    end;
    W.Text:= Copy(Rest, 2, Length(Rest) - 2);
    if Trim(W.Text) = '' then
    begin
      AddError('#warn text is empty');
      Exit;
    end;
    AddRule(W);
  end;

  { 1.26.3: '#check-ref <ToPath> <Class>.<Prop>[, <Class>.<Prop> ...]'. Each
    target needs a dot with a name on both sides of the last one. }
  procedure ParseCheckRefDirective(const AArg: string);
  var
    C   : TConversionRule;
    SpAt: Integer;
    T   : string;
    Dot : Integer;
  begin
    C:= Default(TConversionRule);
    C.Kind:= rkCheckRef;
    SpAt:= Pos(' ', AArg);
    if SpAt = 0 then
    begin
      AddError('#check-ref needs <ToPath> <Class>.<Prop>[, <Class>.<Prop> ...]');
      Exit;
    end;
    C.ToPath:= Trim(Copy(AArg, 1, SpAt - 1));
    for var S: string in Copy(AArg, SpAt + 1, MaxInt).Split([',']) do
    begin
      T  := Trim(S);
      Dot:= T.LastIndexOf('.') + 1;
      if (Dot <= 1) or (Dot >= Length(T)) or (Pos(' ', T) > 0) then
      begin
        AddError(Format('#check-ref target "%s" is not <Class>.<Prop>', [T]));
        Exit;
      end;
      C.RefTargets:= C.RefTargets + [T];
    end;
    AddRule(C);
  end;

  { Parse ONE '#mapping ...' line. AArg is everything after the directive.

    Three FLAT SIBLING line forms, tied together only by <Name> -- there is no
    nested block:
      #mapping <Name> from <EnumType> to <Class>[, <Class> ...]   (declaration)
      #mapping <Name> #when <Path> = <Value> -> <ToPath> = <V>[, ...]
      #mapping <Name> #else -> <ToPath> = <V>[, ...]

    Mirrors ConvRules.Model.pas's parser exactly, INCLUDING its tolerance: a
    bare '#mapping Name', a '#when' with no '->', a '#else' with no '->' and a
    declaration with no ' to ' must ALL parse as rules and never become
    ParseErrors. See the grammar-parity note on the helpers above -- a stricter
    engine makes the editor's save-validate fail and silently lose rules.

    Extracted rather than inlined into the directive chain: as one more arm it
    took ParseConversionRules' cognitive complexity from 173 to 309 (max 65). }
  procedure ParseMappingDirective(const AArg: string);
  var
    M      : TConversionRule;
    Rest   : string ;
    Cond   : string ;
    SetsTxt: string ;
    SpPos  : Integer;
    EqPos  : Integer;
    ToPos  : Integer;
  begin
    M       := Default(TConversionRule);
    M.Kind  := rkMapping;
    M.LineNo:= LineNo;

    SpPos:= Pos(' ', AArg);
    if SpPos = 0 then
    begin
      { Name only. The tail round-trips from the source line. }
      M.MapName:= AArg;
      AddRule(M);
      Exit;
    end;

    M.MapName:= Trim(Copy(AArg, 1, SpPos - 1));
    Rest     := Trim(Copy(AArg, SpPos + 1, MaxInt));

    if StartsText('#when', Rest) then
    begin
      Rest:= Trim(Copy(Rest, Length('#when') + 1, MaxInt));
      { Branch on the RESULT: SplitBareArrow finalizes its out-mode strings to
        '' before it runs, so on False they are empty rather than whatever was
        there. A #when with no '->' must keep its condition. }
      if not SplitBareArrow(Rest, Cond, SetsTxt) then
      begin
        Cond   := Rest;
        SetsTxt:= '';
      end;
      EqPos:= Pos('=', Cond);
      if EqPos > 0 then
      begin
        M.WhenFrom := Trim(Copy(Cond, 1, EqPos - 1));
        M.WhenValue:= Trim(Copy(Cond, EqPos + 1, MaxInt));
      end
      else
        M.WhenFrom:= Cond;
      M.Sets:= ParseSetList(SetsTxt);
      AddRule(M);
      Exit;
    end;

    if StartsText('#else', Rest) then
    begin
      M.IsElse:= True;
      Rest    := Trim(Copy(Rest, Length('#else') + 1, MaxInt));
      if SplitBareArrow(Rest, Cond, SetsTxt) then
        M.Sets:= ParseSetList(SetsTxt);
      AddRule(M);
      Exit;
    end;

    if StartsText('from ', Rest) then
    begin
      Rest := Trim(Copy(Rest, Length('from ') + 1, MaxInt));
      ToPos:= Pos(' to ', LowerCase(Rest));
      if ToPos > 0 then
      begin
        M.MapFromType:= Trim(Copy(Rest, 1, ToPos - 1));
        M.MapToTypes := SplitTopLevelCommas(Copy(Rest, ToPos + Length(' to '), MaxInt));
      end
      else
        M.MapFromType:= Rest;
    end;
    AddRule(M);
  end;

var
  Arg  : string        ;
  Head : string        ;
  Units: TArray<string>;
  ArrPos: Integer      ;
  Lhs, Rhs: string     ;
  R    : TConversionRule;
begin
  Rules:= TList<TConversionRule>.Create;
  Errs := TList<TRuleError>.Create;
  SeenConvert:= False;
  BookDepth    := 0;
  BookDepthLine:= 0;
  try
    Lines:= SplitLines(AText);
    for LineNo:= 1 to Length(Lines) do
    begin
      Raw := Lines[LineNo - 1];
      Line:= Trim(Raw);
      if Line = '' then Continue;                                // blank
      if Line.StartsWith('//') or Line.StartsWith(';') then Continue; // comment

      R:= Default(TConversionRule);

      if Directive('#unuse', Arg) then
      begin
        R.Kind    := rkUnuse;
        R.UnitName:= Arg;
        AddRule(R);
      end
      else if Directive('#useswap', Arg) then
      begin
        // #useswap <Old> -> <New1>[, <New2> ...]  -- UnitName=Old, UnitsAdd=News.
        R.Kind:= rkUseSwap;
        { Arg is trimmed, so a From-only '#useswap X -> ' has lost the space
          after its arrow: match against Arg + ' ' (R27) }
        ArrPos:= Pos(ARROW_MIGRATE, Arg + ' ');
        if ArrPos > 0 then
        begin
          R.UnitName:= Trim(Copy(Arg, 1, ArrPos - 1));
          Rhs       := Trim(Copy(Arg, ArrPos + Length(ARROW_MIGRATE), MaxInt));
        end
        else begin R.UnitName:= Trim(Arg); Rhs:= ''; end;
        // Rhs is a pure comma list of New units; fold Head + rest into UnitsAdd.
        SplitHeadAndUnits(Rhs, Head, Units);
        if Head <> '' then Insert(Head, Units, 0);
        R.UnitsAdd:= Units;
        if Length(Units) = 0 then AddError(Format('#useswap %s has no replacement unit', [R.UnitName]));
        AddRule(R);
      end
      else if Directive('#use', Arg) then
      begin
        R.Kind    := rkUse;
        R.UnitName:= Arg;
        AddRule(R);
      end
      else if Directive('#remove', Arg) then
      begin
        R.Kind:= rkRemove;
        // '#remove DFM: <prop>' -> DFM-only. Match a leading 'DFM:' (any case).
        if SameText(Copy(Arg, 1, 4), 'DFM:') then
        begin
          R.DfmOnly := True;
          R.PropName:= Trim(Copy(Arg, 5, MaxInt));
        end
        else
        begin
          R.DfmOnly := False;
          R.PropName:= Arg;
        end;
        AddRule(R);
      end
      else if Directive('#migrate', Arg) then
      begin
        R.Kind:= rkMigrate;
        { as #useswap: a From-only '#migrate Foo -> ' must read Old 'Foo' (R27) }
        ArrPos:= Pos(ARROW_MIGRATE, Arg + ' ');
        if ArrPos > 0 then
        begin
          Lhs:= Trim(Copy(Arg, 1, ArrPos - 1));
          Rhs:= Trim(Copy(Arg, ArrPos + Length(ARROW_MIGRATE), MaxInt));
        end
        else begin Lhs:= Trim(Arg); Rhs:= ''; end;
        SplitMigrateLhs(Lhs, R.Scope, R.Old);
        SplitHeadAndUnits(Rhs, Head, Units);
        R.New     := Head;
        R.UnitsAdd:= Units;
        AddRule(R);
      end
      else if Directive('#convert', Arg) then
      begin
        R.Kind:= rkConvert;
        { as #useswap: a From-only '#convert TFoo -> ' must read From 'TFoo' (R27) }
        ArrPos:= Pos(ARROW_MIGRATE, Arg + ' ');
        if ArrPos > 0 then
        begin
          R.FromType:= Trim(Copy(Arg, 1, ArrPos - 1));
          Rhs       := Trim(Copy(Arg, ArrPos + Length(ARROW_MIGRATE), MaxInt));
        end
        else begin R.FromType:= Trim(Arg); Rhs:= ''; end;
        SplitHeadAndUnits(Rhs, Head, Units);
        R.ToType  := Head;
        R.UnitsAdd:= Units;
        if Head = '' then AddError(Format('#convert %s has no To type', [R.FromType]));
        SeenConvert:= True;
        AddRule(R);
      end
      else if Directive('#link', Arg) then
      begin
        R.Kind:= rkLink;
        ArrPos:= Pos(ARROW_LINK, Arg);
        if ArrPos > 0 then
        begin
          R.ToPath  := Trim(Copy(Arg, 1, ArrPos - 1));
          R.FromPath:= Trim(Copy(Arg, ArrPos + Length(ARROW_LINK), MaxInt));
          SplitCastSuffix(R.FromPath, R.Cast);
          SplitGlyphExpr(R.FromPath, R.GlyphExpr);
        end
        else
        begin
          // Malformed link (no '<-') -- keep the LHS as ToPath, empty FromPath.
          R.ToPath  := Trim(Arg);
          R.FromPath:= '';
        end;
        AddRule(R);
      end
      else if Directive('#default', Arg) then
      begin
        R.Kind:= rkDefault;
        ArrPos:= Pos('=', Arg);
        if ArrPos > 0 then
        begin
          R.ToPath:= Trim(Copy(Arg, 1, ArrPos - 1));
          R.Value := Trim(Copy(Arg, ArrPos + 1, MaxInt));
        end
        else
        begin
          R.ToPath:= Trim(Arg);
          R.Value := '';
        end;
        AddRule(R);
      end
      else if Directive('#ignore', Arg) then
      begin
        R.Kind    := rkIgnore;
        R.FromPath:= Arg;
        AddRule(R);
      end
      else if Directive('#warn', Arg) then
        ParseWarnDirective(Arg)
      else if Directive('#check-ref', Arg) then
        ParseCheckRefDirective(Arg)
      else if Directive('#note', Arg) then
      begin
        R.Kind:= rkNote;
        R.Text:= Arg;
        AddRule(R);
      end
      else if Directive('#mapping', Arg) then
        ParseMappingDirective(Arg)
      else if Directive('#apply', Arg) then
      begin
        { '#apply <Name>' -- apply a named mapping. Scope is resolved at re-emit
          time (the nearest preceding #convert whose From type matches the
          component), not here; the parser only captures the name. }
        R:= Default(TConversionRule);
        R.Kind   := rkApply;
        R.LineNo := LineNo;
        R.MapName:= Arg;
        AddRule(R);
      end
      else if Directive('#depth', Arg) then
      begin
        { '#depth N' -- the book's tree-expansion depth for proptree /
          convert-scaffold (TConversionRuleSet.Depth). One per book: a second
          one is an error on ITS line and the first stands. An invalid value
          makes no rule, so Depth stays 0 and the caller's default applies. }
        R.Depth:= if IsDecimalDigits(Arg) then StrToIntDef(Arg, 0) else 0;
        if BookDepthLine > 0 then
          AddError(Format('duplicate #depth (first on line %d) -- one #depth per book', [BookDepthLine]), True)
        else if (R.Depth < MIN_BOOK_DEPTH) or (R.Depth > MAX_BOOK_DEPTH) then
          AddError(Format('#depth must be an integer %d..%d', [MIN_BOOK_DEPTH, MAX_BOOK_DEPTH]), True)
        else
        begin
          R.Kind       := rkDepth;
          BookDepth    := R.Depth;
          BookDepthLine:= LineNo;
          AddRule(R);
        end;
      end
      else if Directive('#tag', Arg) then
      begin
        { '#tag <Ident>' -- TOLERATED, and deliberately nothing more. The rule
          corpus wants to label a #convert block so a job can select rules by
          tag; until that selection exists, the only thing the engine owes is to
          stop REJECTING the directive, because `convert-validate` failing with
          'unknown directive: #tag' is what blocks the corpus from carrying tags
          at all. The tag is NOT captured into the rule model, so it cannot yet
          be typo-checked or selected on -- that is a separate, unrequested ask.

          It must not invent a rule either: no AddRule here, so the rule COUNT
          of a file is identical with and without its #tag lines.

          SCOPE. A tag labels the enclosing #convert block, so a '#tag' before
          the first '#convert' has nothing to label and is an ERROR rather than
          a silent no-op -- a silently-ignored tag is exactly the failure a
          corpus of tagged rules cannot afford. }
        if not SeenConvert then
          AddError('#tag before any #convert -- a tag labels the enclosing #convert block')
        else if Trim(Arg) = '' then
          AddError('#tag requires a tag name');
      end
      else if Line.StartsWith('#') then
      begin
        // An unknown '#directive' -- capture a parse error, never raise.
        Low:= Line;
        ArrPos:= Pos(' ', Low);
        if ArrPos > 0 then Low:= Copy(Low, 1, ArrPos - 1);
        AddError('unknown directive: ' + Low);
      end
      else if Pos(ARROW_MIGRATE, Line) > 0 then
      begin
        // A non-'#' line with ' -> ' -- the raw PCRE find/replace escape hatch.
        R.Kind := rkPcre;
        ArrPos := Pos(ARROW_MIGRATE, Line);
        R.Search := Trim(Copy(Line, 1, ArrPos - 1));
        R.Replace:= Trim(Copy(Line, ArrPos + Length(ARROW_MIGRATE), MaxInt));
        AddRule(R);
      end
      else
      begin
        // A non-blank, non-comment, non-directive line without ' -> ' cannot be
        // interpreted -- record it so nothing is silently swallowed.
        AddError('unrecognised line (no directive and no '' -> '' pattern)');
      end;
    end;

    Result.Rules      := Rules.ToArray;
    Result.ParseErrors:= Errs.ToArray;
    Result.Depth      := BookDepth;
    Result.DepthLine  := BookDepthLine;
  finally
    Rules.Free;
    Errs.Free;
  end;
end;

// The one warning text of an UNREACHABLE rule path -- see TUnreachablePath.
function UnreachableMessage(ALineNo: Integer; const APath, AMember, AVisibility, AClass: string): string;
begin
  Result:= Format('line %d: warning: %s: %s is %s in %s; never applied unless a descendant class changes its visibility',
    [ALineNo, APath, AMember, AVisibility, AClass]);
end;

function WarnPlaceholders(const AText: string): TArray<string>;
var
  I, J: Integer;
  Name: string;
begin
  Result:= nil;
  I:= Pos('{', AText);
  while I > 0 do
  begin
    J:= Pos('}', AText, I + 1);
    if J = 0 then Break;
    Name:= Copy(AText, I + 1, J - I - 1);
    if IsValidIdent(Name, True) then Result:= Result + [Name];
    I:= Pos('{', AText, J + 1);
  end;
end;

// The #convert block of every rule, index-aligned with ARules.Rules: 0 before
// the first #convert, then 1, 2, ... -- a block starts AT its #convert line.
function ConvertBlocks(const ARules: TConversionRuleSet): TArray<Integer>;
var
  I    : Integer;
  Block: Integer;
begin
  SetLength(Result, Length(ARules.Rules));
  Block:= 0;
  for I:= 0 to High(ARules.Rules) do
  begin
    if ARules.Rules[I].Kind = rkConvert then Inc(Block);
    Result[I]:= Block;
  end;
end;

// True for a #link carrying an IMAGE glyph expression -- any G-expression that
// is not a well-formed 'G[count]'. A malformed one still counts: it is an image
// link with an error, and counting it keeps a sibling G[count] from reporting a
// second, misleading "found 0".
function IsGlyphImageLink(const ARule: TConversionRule): Boolean;
var
  Expr: TGlyphExpr;
begin
  Result:= (ARule.Kind = rkLink) and (ARule.GlyphExpr <> '') and
           ((Length(ParseGlyphExpr(ARule.GlyphExpr, Expr)) > 0) or not IsGlyphCountExpr(Expr));
end;

{ The one validator behind ValidateConversionRules and
  ValidateConversionRulesPerBlock. ABlockClasses is index-aligned with
  ConvertBlocks' numbering. APerBlock selects the mapping scope and the message
  suffix: False = the single-pair contract (every mapping line against the
  classes of the block it sits in, no suffix -- the caller passes the same pair
  for every block, so that is the one pair); True = the per-block contract
  documented on ValidateConversionRulesPerBlock. }
function ValidateBlocks(const ARules: TConversionRuleSet;
  const ABlockClasses: TArray<TBlockClasses>; APerBlock: Boolean;
  out AUnreachable: TArray<TUnreachablePath>): TArray<TRuleError>;
var
  Unr    : TList<TUnreachablePath>;
  Errs   : TList<TRuleError>;
  R      : TConversionRule ;
  PE     : TRuleError      ;
  Blocks : TArray<Integer>;
  ConvAt : TArray<Integer>;
  I      : Integer        ;
  B      : Integer        ;

  procedure Add(ALineNo: Integer; const AMsg: string);
  var
    E: TRuleError;
  begin
    E        := Default(TRuleError);
    E.LineNo := ALineNo;
    E.Message:= AMsg;
    Errs.Add(E);
  end;

  function IsStub(const APath: string): Boolean;
  begin
    Result:= Trim(APath) = STUB_MARKER;
  end;

  function ClassesOf(ABlock: Integer): TBlockClasses;
  begin
    if (ABlock >= 0) and (ABlock <= High(ABlockClasses)) then Result:= ABlockClasses[ABlock]
    else Result:= Default(TBlockClasses);
  end;

  // ' (#convert line N: From -> To)' naming the block a path was checked in;
  // '' in single-pair mode, whose messages must stay byte-identical.
  function Where(ABlock: Integer): string;
  var
    C: TConversionRule;
  begin
    Result:= '';
    if (not APerBlock) or (ABlock <= 0) or (ABlock > High(ConvAt)) then Exit;
    C:= ARules.Rules[ConvAt[ABlock]];
    Result:= Format(' (#convert line %d: %s -> %s)', [C.LineNo, C.FromType, C.ToType]);
  end;

  // Records an UNREACHABLE path once per (line, block, #when-or-target, path,
  // offending member and its class): a #mapping line checked in several blocks
  // gets one record per block (WithoutUnreachableRules filters per block;
  // DistinctUnreachable prints each message once), and a #link naming the same
  // path on both sides warns once per side whose class blocks it.
  procedure AddUnreachable(ALineNo, ABlock: Integer; AIsWhen: Boolean; const APath: string;
    const ARes: TPathResolution);
  var
    U: TUnreachablePath;
  begin
    for U in Unr do
    begin
      var SameRule: Boolean:= (U.LineNo = ALineNo) and (U.Block = ABlock) and (U.IsWhen = AIsWhen);
      var SameHit : Boolean:= SameText(U.Path, APath) and SameText(U.Member, ARes.Member);
      if SameRule and SameHit and SameText(U.DeclaringClass, ARes.DeclaringClass) then Exit;
    end;
    U.Block         := ABlock;
    U.IsWhen        := AIsWhen;
    U.LineNo        := ALineNo;
    U.Path          := APath;
    U.Member        := ARes.Member;
    U.Visibility    := ARes.Visibility;
    U.DeclaringClass:= ARes.DeclaringClass;
    U.Message       := UnreachableMessage(ALineNo, APath, ARes.Member, ARes.Visibility, ARes.DeclaringClass);
    Unr.Add(U);
  end;

  // A path is missing when the class was supplied and resolves, the path is
  // real (not empty, not the '???' stub) and some segment names NO member
  // (TPropMemberCache.ResolvePathEx on the DFM surface -- ruling R8; see
  // TPropSurface). A path whose members all exist but fail R8 is not missing:
  // it is recorded as UNREACHABLE (owner ruling R12) for rule line ALineNo,
  // checked in block ABlock; AIsWhen marks a #mapping #when source path.
  function Missing(const AClass: TClassRef; const APath: string; ALineNo, ABlock: Integer;
    AIsWhen: Boolean): Boolean;
  var
    Res: TPathResolution;
  begin
    Result:= False;
    if (APath = '') or IsStub(APath) or (AClass.RootType = '') then Exit;
    Res:= AClass.ResolvePathEx(APath, psDfm);
    case Res.Outcome of
      poNotFound   : Result:= True;
      poUnreachable: AddUnreachable(ALineNo, ABlock, AIsWhen, APath, Res);
    end;
  end;

  // True when some rkMapping line declares AName. Case-insensitive, matching
  // how the rest of the DSL compares identifiers.
  function MappingDeclared(const AName: string): Boolean;
  var
    M: TConversionRule;
  begin
    Result:= False;
    for M in ARules.Rules do
      if (M.Kind = rkMapping) and SameText(M.MapName, AName) then Exit(True);
  end;

  { The blocks whose trees check the #mapping line at AIdx. Blocks[] never
    decreases along the book, so comparing with the last block added is enough
    to add each applying block once. }
  function MappingBlocks(AIdx: Integer): TArray<Integer>;
  var
    J: Integer;
  begin
    if not APerBlock then Exit(TArray<Integer>.Create(Blocks[AIdx]));
    Result:= nil;
    for J:= 0 to High(ARules.Rules) do
      if (ARules.Rules[J].Kind = rkApply) and (Blocks[J] > 0) and
         SameText(ARules.Rules[J].MapName, ARules.Rules[AIdx].MapName) and
         ((Length(Result) = 0) or (Result[High(Result)] <> Blocks[J])) then
        Result:= Result + [Blocks[J]];
    if (Length(Result) = 0) and (Blocks[AIdx] > 0) then Result:= TArray<Integer>.Create(Blocks[AIdx]);
  end;

  { A #when branch's condition names a path in the F tree, and its set list
    assigns paths in the T tree -- same checks, same stub/empty-tree skips, as
    #link/#default. Nothing here validates the mapping NAME: the three line
    forms are flat siblings, so a #when may legally appear before its
    declaration. }
  procedure CheckMapping(const AMap: TConversionRule; ABlock: Integer);
  var
    T : TBlockClasses;
    SP: TMappingSetPair;
  begin
    T:= ClassesOf(ABlock);
    if Missing(T.FromClass, AMap.WhenFrom, AMap.LineNo, ABlock, True) then
      Add(AMap.LineNo, Format('mapping %s #when path not found in --from tree: %s',
        [AMap.MapName, AMap.WhenFrom]) + Where(ABlock));
    for SP in AMap.Sets do
      if Missing(T.ToClass, SP.ToPath, AMap.LineNo, ABlock, False) then
        Add(AMap.LineNo, Format('mapping %s target path not found in --to tree: %s',
          [AMap.MapName, SP.ToPath]) + Where(ABlock));
  end;

  procedure CheckLinkOrDefault(const ARule: TConversionRule; ABlock: Integer);
  var
    T: TBlockClasses;
  begin
    T:= ClassesOf(ABlock);
    if ARule.Kind = rkDefault then
    begin
      if Missing(T.ToClass, ARule.ToPath, ARule.LineNo, ABlock, False) then
        Add(ARule.LineNo, Format('default ToPath not found in --to tree: %s', [ARule.ToPath]) + Where(ABlock));
      Exit;
    end;
    if Missing(T.ToClass, ARule.ToPath, ARule.LineNo, ABlock, False) then
      Add(ARule.LineNo, Format('link ToPath not found in --to tree: %s', [ARule.ToPath]) + Where(ABlock));
    if Missing(T.FromClass, ARule.FromPath, ARule.LineNo, ABlock, False) then
      Add(ARule.LineNo, Format('link FromPath not found in --from tree: %s', [ARule.FromPath]) + Where(ABlock));
  end;

  { G-grammar design 3.2/3.3/8: the expression's own syntax and ranges, then --
    for 'G[count]' -- exactly one image link from the same FromPath in the same
    #convert block. Needs no property tree, so it fires in parse-only mode too
    (the editor's save-validate). }
  procedure CheckGlyphLink(AIdx: Integer);
  var
    Link : TConversionRule;
    Expr : TGlyphExpr;
    GErrs: TArray<TGlyphExprError>;
    GE   : TGlyphExprError;
    J    : Integer;
    Found: Integer;
  begin
    Link := ARules.Rules[AIdx];
    GErrs:= ParseGlyphExpr(Link.GlyphExpr, Expr);
    if Length(GErrs) = 0 then GErrs:= ValidateGlyphExpr(Expr);
    for GE in GErrs do
      Add(Link.LineNo, Format('link %s <- %s: G-expression column %d: %s (in "%s")',
        [Link.ToPath, Link.FromPath, GE.Column, GE.Message, Link.GlyphExpr]));
    if (Length(GErrs) > 0) or not IsGlyphCountExpr(Expr) then Exit;
    Found:= 0;
    for J:= 0 to High(ARules.Rules) do
      if (Blocks[J] = Blocks[AIdx]) and SameText(ARules.Rules[J].FromPath, Link.FromPath) and
         IsGlyphImageLink(ARules.Rules[J]) then
        Inc(Found);
    if Found <> 1 then
      Add(Link.LineNo, Format('G[count] needs exactly one image link from %s; found %d',
        [Link.FromPath, Found]));
  end;

begin
  Errs:= TList<TRuleError>.Create;
  Unr := TList<TUnreachablePath>.Create;
  try
    // 1. Fold in any parse errors first (source order preserved by LineNo).
    for PE in ARules.ParseErrors do
      Errs.Add(PE);

    Blocks:= ConvertBlocks(ARules);
    SetLength(ConvAt, Length(ARules.Rules) + 1);
    for I:= 0 to High(ARules.Rules) do
      if ARules.Rules[I].Kind = rkConvert then ConvAt[Blocks[I]]:= I;

    // 2. Path checks for #link, #default and #mapping; glyph-expression checks
    //    for #link; the undeclared-mapping check for #apply.
    for I:= 0 to High(ARules.Rules) do
    begin
      R:= ARules.Rules[I];
      case R.Kind of
        rkLink, rkDefault:
        begin
          CheckLinkOrDefault(R, Blocks[I]);
          if (R.Kind = rkLink) and (R.GlyphExpr <> '') then CheckGlyphLink(I);
        end;
        rkWarn:
        begin
          // 1.26.3: the path and every brace placeholder must name a member
          // of the block's From type, exactly as a #link FromPath must.
          var WT: TBlockClasses:= ClassesOf(Blocks[I]);
          if Missing(WT.FromClass, R.FromPath, R.LineNo, Blocks[I], False) then
            Add(R.LineNo, Format('warn FromPath not found in --from tree: %s', [R.FromPath]) + Where(Blocks[I]));
          for var Ph: string in WarnPlaceholders(R.Text) do
            if Missing(WT.FromClass, Ph, R.LineNo, Blocks[I], False) then
              Add(R.LineNo, Format('warn placeholder {%s} not found in --from tree', [Ph]) + Where(Blocks[I]));
        end;
        rkCheckRef:
          if Missing(ClassesOf(Blocks[I]).ToClass, R.ToPath, R.LineNo, Blocks[I], False) then
            Add(R.LineNo, Format('check-ref ToPath not found in --to tree: %s', [R.ToPath]) + Where(Blocks[I]));
        rkMapping:
          for B in MappingBlocks(I) do CheckMapping(R, B);
        rkApply:
        begin
          { An #apply naming a mapping that was never declared is the one error
            worth raising here, and it needs no property tree -- so unlike every
            check above it fires in tree-less (parse-only) mode too, which is the
            mode the editor's save-validate runs in.

            Mirrors the editor's mikUndefined. A DECLARATION is the 'from' form
            (it is the line that says what the mapping IS); a bare '#mapping
            Name' counts too, since the editor emits that while a rule is being
            authored and rejecting it would fail the round-trip. }
          if (R.MapName <> '') and (not MappingDeclared(R.MapName)) then
            Add(R.LineNo, Format('apply names an undeclared mapping: %s', [R.MapName]));
        end;
        // rkConvert is informational; rkUnuse/rkRemove/rkMigrate/rkNote/rkPcre
        // carry no index-checkable paths in Batch 1 -- no checks.
      end;
    end;

    Result      := Errs.ToArray;
    AUnreachable:= Unr.ToArray;
  finally
    Unr.Free;
    Errs.Free;
  end;
end;

function ValidateConversionRules(const ARules: TConversionRuleSet;
  const AFrom, ATo: TClassRef; out AUnreachable: TArray<TUnreachablePath>): TArray<TRuleError>;
var
  Classes: TArray<TBlockClasses>;
  I      : Integer;
begin
  // One pair for every block, the region before the first #convert included.
  SetLength(Classes, Length(ARules.Rules) + 1);
  for I:= 0 to High(Classes) do
  begin
    Classes[I].FromClass:= AFrom;
    Classes[I].ToClass  := ATo;
  end;
  Result:= ValidateBlocks(ARules, Classes, False, AUnreachable);
end;

function ValidateConversionRulesPerBlock(const ARules: TConversionRuleSet;
  const ABlockClasses: TArray<TBlockClasses>; out AUnreachable: TArray<TUnreachablePath>): TArray<TRuleError>;
begin
  Result:= ValidateBlocks(ARules, ABlockClasses, True, AUnreachable);
end;

function WithoutUnreachableRules(const ARules: TConversionRuleSet;
  const AUnreachable: TArray<TUnreachablePath>; ABlock: Integer): TConversionRuleSet;
var
  U       : TUnreachablePath;
  R       : TConversionRule;
  Kept    : TList<TConversionRule>;
  DeadLine: TDictionary<Integer, Boolean>; // #link / #default lines, any block
  DeadMap : TDictionary<string, Boolean>;  // UPPER(mapping name): #when source unreachable in ABlock
  Stripped: TList<TMappingSetPair>;

  // True when ABlock's records name ASet's target on the #mapping line ALineNo.
  function TargetDead(ALineNo: Integer; const ASet: TMappingSetPair): Boolean;
  var
    V: TUnreachablePath;
  begin
    for V in AUnreachable do
      if (V.Block = ABlock) and (not V.IsWhen) and (V.LineNo = ALineNo) and SameText(V.Path, ASet.ToPath) then
        Exit(True);
    Result:= False;
  end;

begin
  Result:= ARules;
  if Length(AUnreachable) = 0 then Exit;
  DeadLine:= TDictionary<Integer, Boolean>.Create;
  DeadMap := TDictionary<string, Boolean>.Create;
  Kept    := TList<TConversionRule>.Create;
  Stripped:= TList<TMappingSetPair>.Create;
  try
    for U in AUnreachable do
      if U.IsWhen and (U.Block = ABlock) and (ABlock > 0) then
      begin
        for R in ARules.Rules do
          if (R.Kind = rkMapping) and (R.LineNo = U.LineNo) then DeadMap.AddOrSetValue(UpperCase(R.MapName), True);
      end
      else if not U.IsWhen then
        DeadLine.AddOrSetValue(U.LineNo, True);
    for R in ARules.Rules do
    begin
      if (R.Kind in [rkLink, rkDefault]) and DeadLine.ContainsKey(R.LineNo) then Continue;
      if R.Kind <> rkMapping then
      begin
        Kept.Add(R);
        Continue;
      end;
      if DeadMap.ContainsKey(UpperCase(R.MapName)) then Continue;
      var M: TConversionRule:= R;
      if ABlock > 0 then
      begin
        Stripped.Clear;
        for var SP: TMappingSetPair in R.Sets do
          if not TargetDead(R.LineNo, SP) then Stripped.Add(SP);
        M.Sets:= Stripped.ToArray;
      end;
      Kept.Add(M);
    end;
    Result.Rules:= Kept.ToArray;
  finally
    Stripped.Free;
    Kept.Free;
    DeadMap.Free;
    DeadLine.Free;
  end;
end;

function DistinctUnreachable(const AUnreachable: TArray<TUnreachablePath>): TArray<TUnreachablePath>;
var
  Seen: TDictionary<string, Boolean>;
  U   : TUnreachablePath;
begin
  Result:= nil;
  Seen  := TDictionary<string, Boolean>.Create;
  try
    for U in AUnreachable do
      if not Seen.ContainsKey(U.Message) then
      begin
        Seen.Add(U.Message, True);
        Result:= Result + [U];
      end;
  finally
    Seen.Free;
  end;
end;

function ConversionRuleWarnings(const ARules: TConversionRuleSet): TArray<TRuleError>;
var
  Blocks: TArray<Integer>;
  I     : Integer;
  J     : Integer;
  R     : TConversionRule;
  G     : TConversionRule;
  W     : TRuleError;
begin
  Result:= nil;
  Blocks:= ConvertBlocks(ARules);
  for I:= 0 to High(ARules.Rules) do
  begin
    R:= ARules.Rules[I];
    if (R.Kind <> rkLink) or (R.GlyphExpr <> '') or not IsGlyphCountPropName(R.FromPath) then Continue;
    for J:= 0 to High(ARules.Rules) do
    begin
      if (Blocks[J] <> Blocks[I]) or not IsGlyphImageLink(ARules.Rules[J]) then Continue;
      G:= ARules.Rules[J];
      W:= Default(TRuleError); // IsDepthError and any later field start clean (T2i)
      W.LineNo := R.LineNo;
      W.Message:= Format('link %s <- %s is a straight carry of the source glyph count beside the G-link ' +
        'on line %d -- right only for identity alternatives; write "#link %s <- %s G[count]" instead',
        [R.ToPath, R.FromPath, G.LineNo, R.ToPath, G.FromPath]);
      Result:= Result + [W];
      Break;
    end;
  end;
end;

function UnrealisedGlyphLinks(const ARules: TConversionRuleSet): TArray<TRuleError>;
var
  R: TConversionRule;
  E: TRuleError;
begin
  Result:= nil;
  for R in ARules.Rules do
  begin
    if (R.Kind <> rkLink) or (R.GlyphExpr = '') then Continue;
    E        := Default(TRuleError);
    E.LineNo := R.LineNo;
    E.Message:= Format('link %s <- %s %s: glyph-expression links are validated but not yet realised ' +
      'by convert-apply (CV-2) -- refusing rather than carrying the source image whole',
      [R.ToPath, R.FromPath, R.GlyphExpr]);
    Result:= Result + [E];
  end;
end;

end.
