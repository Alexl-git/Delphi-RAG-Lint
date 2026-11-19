unit DRagLint.V151.APP.Support;

{ Wave v151 lane APP -- helpers of DRagLint.V151.APP (private to the lane).

  The lane's rules are text rules: they read the source once, blank out comments,
  strings and compiler directives (keeping every offset and line break), and then
  look at the remaining code with a token list, a routine table and a table of
  conditional-compilation blocks. No index and no parse tree is needed. }

interface

uses
  System.SysUtils
  , System.Classes
  , System.Generics.Collections
  , System.RegularExpressions
  , DRagLint.Core.Model
  ;

const
  RULE_TLS_VERIFY_OFF   = 'tls-verification-disabled';
  RULE_UI_CALL          = 'ui-call-in-console-or-service';
  RULE_DUNITX_NO_ASSERT = 'dunitx-test-without-assert';
  RULE_CONTRACT_CLASS   = 'contract-unit-declares-class';
  RULE_WEAK_CIPHER      = 'weak-cipher';
  RULE_ASM_NO_WIN64     = 'asm-without-win64-variant';
  RULE_WRITELN_GUI      = 'writeln-in-gui-app';

type
  /// <summary>One identifier-like word of the masked source.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.APP.Support.pas), DRagLint.V151.APP.Support.TAppChecks.AsmWithoutWin64Variant (DRagLint.V151.APP.Support.pas), DRagLint.V151.APP.Support.TAppSrc.BuildTokens (DRagLint.V151.APP.Support.pas), DRagLint.V151.APP.Support.TAppSrc.Create (DRagLint.V151.APP.Support.pas), DRagLint.V151.APP.Support.TAppSrc.ParseRoutine (DRagLint.V151.APP.Support.pas)</para>
  /// <para>Used in units: DRagLint.V151.APP.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TAppTok = record
    Text  : string;
    Low   : string;
    Pos   : Integer;  // 1-based offset of the first character
    EndPos: Integer;  // 1-based offset one past the last character
  end;

  /// <summary>One compiler directive `{$...}` found in the raw source.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.APP.Support.pas), DRagLint.V151.APP.Support.TAppSrc.BuildBlocks (DRagLint.V151.APP.Support.pas), DRagLint.V151.APP.Support.TAppSrc.Create (DRagLint.V151.APP.Support.pas), DRagLint.V151.APP.Support.TAppSrc.HasX64Directive (DRagLint.V151.APP.Support.pas), DRagLint.V151.APP.Support.TAppSrc.Mask (DRagLint.V151.APP.Support.pas)</para>
  /// <para>Used in units: DRagLint.V151.APP.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TAppDirective = record
    Pos : Integer;
    Text: string;  // upper case, trimmed, without braces, starts with '$'
  end;

  /// <summary>One conditional-compilation block, from its opening directive to its closing one.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.APP.Support.pas) ?, DRagLint.V151.APP.Support.TAppSrc.BranchArch (DRagLint.V151.APP.Support.pas) ?, DRagLint.V151.APP.Support.TAppSrc.BuildBlocks (DRagLint.V151.APP.Support.pas), DRagLint.V151.APP.Support.TAppSrc.Create (DRagLint.V151.APP.Support.pas) ?, DRagLint.V151.APP.Support.TAppSrc.Enclosing (DRagLint.V151.APP.Support.pas) ? (+2 more)</para>
  /// <para>Used in units: DRagLint.V151.APP.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TAppCondBlock = record
    StartPos: Integer;
    ElsePos : Integer;  // first $ELSE / $ELSEIF, or 0
    EndPos  : Integer;  // the $ENDIF / $IFEND, or MaxInt when the block is never closed
    Cond    : string;   // upper-case condition text after the directive name
    Negated : Boolean;  // opened by $IFNDEF
  end;

  /// <summary>One routine implementation found in the masked source.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.APP.Support.pas) ?, DRagLint.V151.APP.Support.TAppChecks.TlsVerificationDisabled (DRagLint.V151.APP.Support.pas) ?, DRagLint.V151.APP.Support.TAppSrc.BodyOf (DRagLint.V151.APP.Support.pas) ?, DRagLint.V151.APP.Support.TAppSrc.Create (DRagLint.V151.APP.Support.pas) ?, DRagLint.V151.APP.Support.TAppSrc.ParseRoutine (DRagLint.V151.APP.Support.pas) (+5 more)</para>
  /// <para>Used in units: DRagLint.V151.APP.Support, DRagLint.V152.APP2.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TAppRoutine = record
    Name     : string;  // as written, e.g. 'TImportTests.LoadEmpty'
    HeaderPos: Integer;
    BodyPos  : Integer;  // the `begin` / `asm` token
    BodyEnd  : Integer;  // one past the closing `end`
  end;

  /// <summary>Which processor a conditional-compilation branch is written for.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.APP.Support.pas), DRagLint.V151.APP.Support.TAppChecks.AsmWithoutWin64Variant (DRagLint.V151.APP.Support.pas), DRagLint.V151.APP.Support.TAppSrc.BranchArch (DRagLint.V151.APP.Support.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TAppArch = (aaNone, aaX86, aaX64);

  /// <summary>A source file prepared for the lane's text rules.</summary>
  /// <remarks>
  /// Immutable after Create. Masked has exactly the length of the raw text:
  /// comments, string literals and directives become spaces, line breaks are kept,
  /// so an offset in Masked is an offset in the raw text.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.APP.Support.pas) ?, DRagLint.V151.APP.Support.MakeFinding (DRagLint.V151.APP.Support.pas) ?, DRagLint.V151.APP.Support.TAppChecks.TlsVerificationDisabled (DRagLint.V151.APP.Support.pas) ?, DRagLint.V151.APP.TV151APPRules.CheckFile (DRagLint.V151.APP.pas), DRagLint.V152.APP2.Support.TApp2CrossUnit.Run (DRagLint.V152.APP2.Support.pas) (+10 more)</para>
  /// <para>Used in units: DRagLint.V151.APP, DRagLint.V151.APP.Support, DRagLint.V152.APP2.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TAppSrc = class  // dl:ok high-response@2221 -- REVIEWED 2026-11-14 v151 INT: one scanner class holding the per-rule checks of one lane; a split is beyond 1.51
  strict private
    FRaw        : string;
    FMasked     : string;
    FLineStarts : TArray<Integer>;
    FDirs       : TList<TAppDirective>;
    FToks       : TList<TAppTok>;
    FRoutines   : TList<TAppRoutine>;
    FBlocks     : TList<TAppCondBlock>;
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.APP.Support.TAppSrc.Create (DRagLint.V151.APP.Support.pas)</para>
    /// <para>Calls: Copy, DRagLint.V151.APP.Support.TAppSrc.Mask.Blank, Trim, UpperCase</para>
    /// <para>Complexity: 30 (cyclomatic, outer body), 92 lines (full implementation)</para>
    /// <para>Reads: FRaw, FLineStarts, FDirs   Writes: FLineStarts, FMasked</para>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.Mask.Blank"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BodyOf"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BranchArch"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildBlocks"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildTokens"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure Mask;
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.APP.Support.TAppSrc.Create (DRagLint.V151.APP.Support.pas)</para>
    /// <para>Calls: CharInSet, Copy, DRagLint.V151.APP.Support.IsIdentChar, DRagLint.V151.APP.Support.IsIdentStart, LowerCase</para>
    /// <para>Reads: FMasked, FToks</para>
    /// <seealso cref="DRagLint.V151.APP.Support.IsIdentChar"/>
    /// <seealso cref="DRagLint.V151.APP.Support.IsIdentStart"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BodyOf"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BranchArch"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildBlocks"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure BuildTokens;
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.APP.Support.TAppSrc.Create (DRagLint.V151.APP.Support.pas)</para>
    /// <para>Calls: Copy, Default, Pos, Trim</para>
    /// <para>Complexity: 13 (cyclomatic, outer body), 52 lines (full implementation)</para>
    /// <para>Reads: FDirs, FBlocks   Writes: FBlocks</para>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BodyOf"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BranchArch"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildTokens"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.ColOf"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure BuildBlocks;
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.APP.Support.TAppSrc.Create (DRagLint.V151.APP.Support.pas)</para>
    /// <para>Calls: DRagLint.V151.APP.Support.TAppSrc.IsRoutineStart, DRagLint.V151.APP.Support.TAppSrc.IsTypeBodyStart, DRagLint.V151.APP.Support.TAppSrc.ParseRoutine, DRagLint.V151.APP.Support.TAppSrc.SkipTypeBody</para>
    /// <para>Reads: FToks</para>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.IsRoutineStart"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.IsTypeBodyStart"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.ParseRoutine"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.SkipTypeBody"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BodyOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure FindRoutines;
    /// <param name="APos"><!-- drag-lint:auto type -->Integer</param>
    /// <returns><!-- drag-lint:auto type -->Integer</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.APP.Support.TAppSrc.ParseRoutine (DRagLint.V151.APP.Support.pas), DRagLint.V151.APP.Support.TAppSrc.SkipTypeBody (DRagLint.V151.APP.Support.pas)</para>
    /// <para>Calls: CharInSet</para>
    /// <para>Reads: FMasked</para>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BodyOf"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BranchArch"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildBlocks"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildTokens"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.ColOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function NextNonWs(APos: Integer): Integer;
    /// <param name="APos"><!-- drag-lint:auto type -->Integer</param>
    /// <returns><!-- drag-lint:auto -->Char -- Observed: FMasked[P].</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.APP.Support.TAppSrc.IsRoutineStart (DRagLint.V151.APP.Support.pas), DRagLint.V151.APP.Support.TAppSrc.IsTypeBodyStart (DRagLint.V151.APP.Support.pas)</para>
    /// <para>Calls: CharInSet</para>
    /// <para>Reads: FMasked</para>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BodyOf"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BranchArch"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildBlocks"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildTokens"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.ColOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function PrevCh(APos: Integer): Char;
    /// <param name="AIdx"><!-- drag-lint:auto type -->Integer</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: (Low = 'procedure') or (Low =
    /// 'function') or (Low = 'constructor') or (Low = 'destructor').</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.APP.Support.TAppSrc.FindRoutines (DRagLint.V151.APP.Support.pas), DRagLint.V151.APP.Support.TAppSrc.ParseRoutine (DRagLint.V151.APP.Support.pas)</para>
    /// <para>Calls: CharInSet, DRagLint.V151.APP.Support.TAppSrc.PrevCh</para>
    /// <para>Reads: FToks</para>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.PrevCh"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BodyOf"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BranchArch"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildBlocks"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildTokens"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsRoutineStart(AIdx: Integer): Boolean;
    /// <param name="AIdx"><!-- drag-lint:auto type -->Integer</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: (Low = 'class') or (Low =
    /// 'record') or (Low = 'object') or (Low = 'interface') or (Low = 'dispinterface');
    /// PrevCh(P) = '='.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.APP.Support.TAppSrc.FindRoutines (DRagLint.V151.APP.Support.pas), DRagLint.V151.APP.Support.TAppSrc.ParseRoutine (DRagLint.V151.APP.Support.pas)</para>
    /// <para>Calls: DRagLint.V151.APP.Support.TAppSrc.PrevCh</para>
    /// <para>Reads: FToks</para>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.PrevCh"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BodyOf"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BranchArch"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildBlocks"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildTokens"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsTypeBodyStart(AIdx: Integer): Boolean;
    /// <param name="AIdx"><!-- drag-lint:auto type -->var Integer</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.APP.Support.TAppSrc.FindRoutines (DRagLint.V151.APP.Support.pas), DRagLint.V151.APP.Support.TAppSrc.ParseRoutine (DRagLint.V151.APP.Support.pas)</para>
    /// <para>Calls: Copy, DRagLint.V151.APP.Support.IsIdentChar, DRagLint.V151.APP.Support.TAppSrc.NextNonWs, LowerCase</para>
    /// <para>Complexity: 22 (cyclomatic, outer body), 49 lines (full implementation)</para>
    /// <para>Reads: FToks, FMasked</para>
    /// <para>Mutates: AIdx (var)</para>
    /// <seealso cref="DRagLint.V151.APP.Support.IsIdentChar"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.NextNonWs"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BodyOf"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BranchArch"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildBlocks"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure SkipTypeBody(var AIdx: Integer);
    /// <param name="AIdx"><!-- drag-lint:auto type -->var Integer</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.APP.Support.TAppSrc.FindRoutines (DRagLint.V151.APP.Support.pas), DRagLint.V151.APP.Support.TAppSrc.ParseRoutine (DRagLint.V151.APP.Support.pas)</para>
    /// <para>Calls: CharInSet, Copy, Default, DRagLint.V151.APP.Support.IsIdentChar, DRagLint.V151.APP.Support.TAppSrc.IsRoutineStart, DRagLint.V151.APP.Support.TAppSrc.IsTypeBodyStart, DRagLint.V151.APP.Support.TAppSrc.NextNonWs, DRagLint.V151.APP.Support.TAppSrc.ParseRoutine, DRagLint.V151.APP.Support.TAppSrc.SkipTypeBody, Pos</para>
    /// <para>Complexity: 28 (cyclomatic, outer body), 69 lines (full implementation)</para>
    /// <para>Reads: FToks, FMasked, FRoutines</para>
    /// <para>Recursive</para>
    /// <para>Mutates: AIdx (var)</para>
    /// <seealso cref="DRagLint.V151.APP.Support.IsIdentChar"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.IsRoutineStart"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.IsTypeBodyStart"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.NextNonWs"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.SkipTypeBody"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure ParseRoutine(var AIdx: Integer);
  public
    /// <summary>Prepares ARaw: masks it and builds the token, routine and conditional tables.</summary>
    /// <param name="ARaw">The source text as read from disk.</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.APP.TV151APPRules.CheckFile (DRagLint.V151.APP.pas), DRagLint.V152.APP2.Support.TApp2CrossUnit.Run (DRagLint.V152.APP2.Support.pas)</para>
    /// <para>Calls: DRagLint.V151.APP.Support.TAppSrc.BuildBlocks, DRagLint.V151.APP.Support.TAppSrc.BuildTokens, DRagLint.V151.APP.Support.TAppSrc.FindRoutines, DRagLint.V151.APP.Support.TAppSrc.Mask</para>
    /// <para>constructor</para>
    /// <para>Writes: FRaw, FDirs, FToks, FRoutines, FBlocks</para>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildBlocks"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildTokens"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.FindRoutines"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.Mask"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BodyOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create(const ARaw: string);
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: FBlocks, FRoutines, FToks, FDirs</para>
    /// <para>Directives: override</para>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BodyOf"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BranchArch"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildBlocks"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildTokens"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.ColOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    destructor Destroy; override;
    /// <summary>1-based line of an offset.</summary>
    /// <param name="APos"><!-- drag-lint:auto type -->Integer</param>
    /// <returns><!-- drag-lint:auto -->Integer -- Observed: Lo + 1.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.APP.Support.MakeFinding (DRagLint.V151.APP.Support.pas), DRagLint.V151.APP.Support.TAppSrc.ColOf (DRagLint.V151.APP.Support.pas), DRagLint.V152.APP2.Support.CheckProgram (DRagLint.V152.APP2.Support.pas)</para>
    /// <para>Reads: FLineStarts</para>
    /// <para>Effect-free (proven)</para>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BodyOf"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BranchArch"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildBlocks"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildTokens"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.ColOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function LineOf(APos: Integer): Integer;
    /// <summary>1-based column of an offset.</summary>
    /// <param name="APos"><!-- drag-lint:auto type -->Integer</param>
    /// <returns><!-- drag-lint:auto -->Integer -- Observed: APos -
    /// FLineStarts[LineOf(APos) - 1] + 1.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.APP.Support.MakeFinding (DRagLint.V151.APP.Support.pas), DRagLint.V152.APP2.Support.CheckProgram (DRagLint.V152.APP2.Support.pas)</para>
    /// <para>Calls: DRagLint.V151.APP.Support.TAppSrc.LineOf</para>
    /// <para>Reads: FLineStarts</para>
    /// <para>Effect-free (proven)</para>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.LineOf"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BodyOf"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BranchArch"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildBlocks"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildTokens"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ColOf(APos: Integer): Integer;
    /// <summary>The conditional blocks that contain an offset, outermost first.</summary>
    /// <param name="APos"><!-- drag-lint:auto type -->Integer</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TAppCondBlock&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.APP.Support.TAppChecks.AsmWithoutWin64Variant (DRagLint.V151.APP.Support.pas), DRagLint.V151.APP.Support.TAppChecks.WritelnInGuiApp (DRagLint.V151.APP.Support.pas)</para>
    /// <para>Reads: FBlocks</para>
    /// <para>Effect-free (proven)</para>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BodyOf"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BranchArch"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildBlocks"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildTokens"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.ColOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Enclosing(APos: Integer): TArray<TAppCondBlock>;
    /// <summary>The architecture a block's branch at an offset is written for.</summary>
    /// <param name="ABlock"><!-- drag-lint:auto type -->const TAppCondBlock</param>
    /// <param name="APos"><!-- drag-lint:auto type -->Integer</param>
    /// <returns><!-- drag-lint:auto -->TAppArch -- Observed: aaX64.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.APP.Support.TAppChecks.AsmWithoutWin64Variant (DRagLint.V151.APP.Support.pas)</para>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BodyOf"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildBlocks"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildTokens"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.ColOf"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function BranchArch(const ABlock: TAppCondBlock; APos: Integer): TAppArch;
    /// <summary>True when any directive of the file names a 64-bit target.</summary>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.APP.Support.TAppChecks.AsmWithoutWin64Variant (DRagLint.V151.APP.Support.pas)</para>
    /// <para>Reads: FDirs</para>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BodyOf"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BranchArch"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildBlocks"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildTokens"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.ColOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function HasX64Directive: Boolean;
    /// <summary>The body text (masked) of a routine.</summary>
    /// <param name="ARoutine"><!-- drag-lint:auto type -->const TAppRoutine</param>
    /// <returns><!-- drag-lint:auto -->string -- Observed: Copy(FMasked,
    /// ARoutine.BodyPos, ARoutine.BodyEnd - ARoutine.BodyPos).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.APP.Support.TAppChecks.DunitxTestWithoutAssert (DRagLint.V151.APP.Support.pas), DRagLint.V151.APP.Support.TAppChecks.TlsVerificationDisabled (DRagLint.V151.APP.Support.pas), DRagLint.V151.APP.Support.TAppChecks.UiCallInConsoleOrService (DRagLint.V151.APP.Support.pas), DRagLint.V151.APP.Support.TAppChecks.WritelnInGuiApp (DRagLint.V151.APP.Support.pas), DRagLint.V152.APP2.Support.DialogRoutines (DRagLint.V152.APP2.Support.pas)</para>
    /// <para>Calls: Copy</para>
    /// <para>Reads: FMasked</para>
    /// <para>Effect-free (proven)</para>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BranchArch"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildBlocks"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BuildTokens"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.ColOf"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function BodyOf(const ARoutine: TAppRoutine): string;
    property Raw: string read FRaw;
    property Masked: string read FMasked;
    property Dirs: TList<TAppDirective> read FDirs;
    property Toks: TList<TAppTok> read FToks;
    property Routines: TList<TAppRoutine> read FRoutines;
    property Blocks: TList<TAppCondBlock> read FBlocks;
  end;

  /// <summary>The lane's seven checks. Each appends findings for ONE rule to AOut.</summary>
  /// <remarks>
  /// Stateless; all methods are pure functions of the prepared source.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.V151.APP.TV151APPRules.CheckFile (DRagLint.V151.APP.pas)</para>
  /// <para>Used in units: DRagLint.V151.APP</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TAppChecks = class
  public
    /// <summary>Certificate checks that are switched off: empty VerifyMode, accept-everything verify handlers, ignore-certificate flags.</summary>
    /// <param name="ASrc"><!-- drag-lint:auto type -->const TAppSrc</param>
    /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AOut"><!-- drag-lint:auto type -->TList&lt;TLintFinding&gt;</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.APP.TV151APPRules.CheckFile (DRagLint.V151.APP.pas)</para>
    /// <para>Calls: Copy, DRagLint.V151.APP.Support.IsIdentChar, DRagLint.V151.APP.Support.MakeFinding, DRagLint.V151.APP.Support.TAppSrc.BodyOf, LastDelimiter, Pos, SameText</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.APP.Support.IsIdentChar"/>
    /// <seealso cref="DRagLint.V151.APP.Support.MakeFinding"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BodyOf"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppChecks.AsmWithoutWin64Variant"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppChecks.ContractUnitDeclaresClass"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class procedure TlsVerificationDisabled(const ASrc: TAppSrc; const APath: string; AOut: TList<TLintFinding>); static;
    /// <summary>A dialog call in a console program or in a method of a Windows service class.</summary>
    /// <param name="ASrc"><!-- drag-lint:auto type -->const TAppSrc</param>
    /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AOut"><!-- drag-lint:auto type -->TList&lt;TLintFinding&gt;</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.APP.TV151APPRules.CheckFile (DRagLint.V151.APP.pas)</para>
    /// <para>Calls: Copy, DRagLint.V151.APP.Support.TAppChecks.UiCallInConsoleOrService.Report, DRagLint.V151.APP.Support.TAppSrc.BodyOf, LowerCase, MakeFinding, Pos</para>
    /// <para>Complexity: 13 (cyclomatic, outer body), 59 lines (full implementation)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppChecks.UiCallInConsoleOrService.Report"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BodyOf"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppChecks.AsmWithoutWin64Variant"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppChecks.ContractUnitDeclaresClass"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppChecks.DunitxTestWithoutAssert"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class procedure UiCallInConsoleOrService(const ASrc: TAppSrc; const APath: string; AOut: TList<TLintFinding>); static;
    /// <summary>A [Test] / [TestCase] method that checks nothing, directly or through the routines of the same file.</summary>
    /// <param name="ASrc"><!-- drag-lint:auto type -->const TAppSrc</param>
    /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AOut"><!-- drag-lint:auto type -->TList&lt;TLintFinding&gt;</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.APP.TV151APPRules.CheckFile (DRagLint.V151.APP.pas)</para>
    /// <para>Calls: Copy, DRagLint.V151.APP.Support.MakeFinding, DRagLint.V151.APP.Support.TAppChecks.DunitxTestWithoutAssert.IsAssertWord, DRagLint.V151.APP.Support.TAppSrc.BodyOf, LastDelimiter, LowerCase, SameText</para>
    /// <para>Complexity: 16 (cyclomatic, outer body), 85 lines (full implementation)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.APP.Support.MakeFinding"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppChecks.DunitxTestWithoutAssert.IsAssertWord"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BodyOf"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppChecks.AsmWithoutWin64Variant"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppChecks.ContractUnitDeclaresClass"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class procedure DunitxTestWithoutAssert(const ASrc: TAppSrc; const APath: string; AOut: TList<TLintFinding>); static;
    /// <summary>A unit named like a contract unit (Intf, Interfaces, Contracts) that declares a class.</summary>
    /// <param name="ASrc"><!-- drag-lint:auto type -->const TAppSrc</param>
    /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AOut"><!-- drag-lint:auto type -->TList&lt;TLintFinding&gt;</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.APP.TV151APPRules.CheckFile (DRagLint.V151.APP.pas)</para>
    /// <para>Calls: Copy, DRagLint.V151.APP.Support.MakeFinding, LastDelimiter</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.APP.Support.MakeFinding"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppChecks.AsmWithoutWin64Variant"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppChecks.DunitxTestWithoutAssert"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppChecks.TlsVerificationDisabled"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppChecks.UiCallInConsoleOrService"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class procedure ContractUnitDeclaresClass(const ASrc: TAppSrc; const APath: string; AOut: TList<TLintFinding>); static;
    /// <summary>DES, 3DES, RC2, RC4 and ECB-mode ciphers.</summary>
    /// <param name="ASrc"><!-- drag-lint:auto type -->const TAppSrc</param>
    /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AOut"><!-- drag-lint:auto type -->TList&lt;TLintFinding&gt;</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.APP.TV151APPRules.CheckFile (DRagLint.V151.APP.pas)</para>
    /// <para>Calls: DRagLint.V151.APP.Support.MakeFinding</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.APP.Support.MakeFinding"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppChecks.AsmWithoutWin64Variant"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppChecks.ContractUnitDeclaresClass"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppChecks.DunitxTestWithoutAssert"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppChecks.TlsVerificationDisabled"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class procedure WeakCipher(const ASrc: TAppSrc; const APath: string; AOut: TList<TLintFinding>); static;
    /// <summary>An asm block that has no 64-bit variant in the file.</summary>
    /// <param name="ASrc"><!-- drag-lint:auto type -->const TAppSrc</param>
    /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AOut"><!-- drag-lint:auto type -->TList&lt;TLintFinding&gt;</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.APP.TV151APPRules.CheckFile (DRagLint.V151.APP.pas)</para>
    /// <para>Calls: DRagLint.V151.APP.Support.MakeFinding, DRagLint.V151.APP.Support.TAppSrc.BranchArch, DRagLint.V151.APP.Support.TAppSrc.Enclosing, DRagLint.V151.APP.Support.TAppSrc.HasX64Directive</para>
    /// <para>Complexity: 11 (cyclomatic, outer body), 36 lines (full implementation)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.APP.Support.MakeFinding"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BranchArch"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.Enclosing"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.HasX64Directive"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppChecks.ContractUnitDeclaresClass"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class procedure AsmWithoutWin64Variant(const ASrc: TAppSrc; const APath: string; AOut: TList<TLintFinding>); static;
    /// <summary>Write / WriteLn to the console from a program or unit that has no console.</summary>
    /// <param name="ASrc"><!-- drag-lint:auto type -->const TAppSrc</param>
    /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AOut"><!-- drag-lint:auto type -->TList&lt;TLintFinding&gt;</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.APP.TV151APPRules.CheckFile (DRagLint.V151.APP.pas)</para>
    /// <para>Calls: DRagLint.V151.APP.Support.MakeFinding, DRagLint.V151.APP.Support.TAppSrc.BodyOf, DRagLint.V151.APP.Support.TAppSrc.Enclosing, Trim</para>
    /// <para>Complexity: 14 (cyclomatic, outer body), 36 lines (full implementation)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.APP.Support.MakeFinding"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.BodyOf"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppSrc.Enclosing"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppChecks.AsmWithoutWin64Variant"/>
    /// <seealso cref="DRagLint.V151.APP.Support.TAppChecks.ContractUnitDeclaresClass"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class procedure WritelnInGuiApp(const ASrc: TAppSrc; const APath: string; AOut: TList<TLintFinding>); static;
  end;

/// <summary>Reads a source file for the lane's rules.</summary>
/// <param name="APath">Path of the .pas / .dpr file.</param>
/// <returns>The file text; '' when it cannot be read.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.APP.TV151APPRules.CheckFile (DRagLint.V151.APP.pas), DRagLint.V152.APP2.Support.TApp2CrossUnit.Run (DRagLint.V152.APP2.Support.pas)</para>
/// <para>Returns: TFile.ReadAllText(APath); ''</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>Touches: file system</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ReadAppSource(const APath: string): string;

implementation

uses
  System.IOUtils
  ;

const
  OPENER_WORDS = ',begin,case,try,asm,record,';
  DIRECTIVE_WORDS = ',overload,inline,stdcall,cdecl,register,safecall,virtual,override,reintroduce,static,deprecated,platform,dynamic,final,';
  ARCH64_RE = '\b(CPUX64|WIN64|CPU64BITS|CPU64)\b';
  ARCH32_RE = '\b(CPUX86|CPU386|WIN32|CPU32BITS)\b';

function ReadAppSource(const APath: string): string;
begin
  try
    Result:= TFile.ReadAllText(APath);
  except
    on Exception do Result:= '';  { unreadable file: nothing to lint }
  end;
end;

function IsIdentStart(C: Char): Boolean;
begin
  Result:= CharInSet(C, ['A'..'Z', 'a'..'z', '_']);
end;

function IsIdentChar(C: Char): Boolean;
begin
  Result:= CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

function MakeFinding(const ASrc: TAppSrc; const APath, ARule, ASeverity, AMessage: string; AStart, AEnd: Integer): TLintFinding;
begin
  Result:= Default(TLintFinding);
  Result.RuleId   := ARule;
  Result.FilePath := APath;
  Result.StartLine:= ASrc.LineOf(AStart);
  Result.StartCol := ASrc.ColOf(AStart);
  Result.EndLine  := ASrc.LineOf(AEnd);
  Result.EndCol   := ASrc.ColOf(AEnd);
  Result.Severity := ASeverity;
  Result.Message  := AMessage;
end;

{ TAppSrc }

constructor TAppSrc.Create(const ARaw: string);
begin
  inherited Create;
  FRaw      := ARaw;
  FDirs     := TList<TAppDirective>.Create;
  FToks     := TList<TAppTok>.Create;
  FRoutines := TList<TAppRoutine>.Create;
  FBlocks   := TList<TAppCondBlock>.Create;
  Mask;
  BuildTokens;
  BuildBlocks;
  FindRoutines;
end;

destructor TAppSrc.Destroy;
begin
  FBlocks.Free;
  FRoutines.Free;
  FToks.Free;
  FDirs.Free;
  inherited;
end;

procedure TAppSrc.Mask;
var
  Chars: TArray<Char>;
  N, I, E, K, Cnt: Integer;
  D: TAppDirective;

  procedure Blank(AFrom, ATo: Integer);
  var J: Integer;
  begin
    for J:= AFrom to ATo do
      if (Chars[J - 1] <> #10) and (Chars[J - 1] <> #13) then Chars[J - 1]:= ' ';
  end;

begin
  N:= Length(FRaw);
  Chars:= FRaw.ToCharArray;
  Cnt:= 1;
  for K:= 1 to N do
    if FRaw[K] = #10 then Inc(Cnt);
  SetLength(FLineStarts, Cnt);
  FLineStarts[0]:= 1;
  Cnt:= 1;
  for K:= 1 to N do
    if FRaw[K] = #10 then
    begin
      FLineStarts[Cnt]:= K + 1;
      Inc(Cnt);
    end;
  I:= 1;
  while I <= N do
  begin
    if FRaw[I] = '{' then
    begin
      E:= FRaw.IndexOf('}', I) + 1;  // IndexOf is 0-based and starts after the brace
      if E = 0 then E:= N;
      if (I < N) and (FRaw[I + 1] = '$') then
      begin
        D.Pos := I;
        D.Text:= UpperCase(Trim(Copy(FRaw, I + 1, E - I - 1)));
        FDirs.Add(D);
      end;
      Blank(I, E);
      I:= E + 1;
    end
    else if (FRaw[I] = '(') and (I < N) and (FRaw[I + 1] = '*') then
    begin
      E:= FRaw.IndexOf('*)', I + 1) + 2;  // 0-based index of '*)' + 1 = 1-based end of the pair
      if E = 1 then E:= N;
      if (I + 2 <= N) and (FRaw[I + 2] = '$') then  // dl:ok duplicate-code@6a1f -- REVIEWED 2026-11-14 v151 INT: same shape over different fields; a helper would need more parameters than it saves
      begin
        D.Pos := I;
        D.Text:= UpperCase(Trim(Copy(FRaw, I + 2, E - I - 3)));  // dl:ok magic-literal@6809 -- REVIEWED 2026-11-14 v151 INT: a spec value / fixed offset or length read at its single use site; a named constant adds nothing
        FDirs.Add(D);
      end;
      Blank(I, E);
      I:= E + 1;
    end
    else if (FRaw[I] = '/') and (I < N) and (FRaw[I + 1] = '/') then
    begin
      E:= I;
      while (E < N) and (FRaw[E + 1] <> #10) and (FRaw[E + 1] <> #13) do Inc(E);
      Blank(I, E);
      I:= E + 1;
    end
    else if FRaw[I] = '''' then
    begin
      E:= I + 1;
      while E <= N do
      begin
        if FRaw[E] = '''' then
        begin
          if (E < N) and (FRaw[E + 1] = '''') then
            Inc(E, 2)
          else
            Break;
        end
        else if (FRaw[E] = #10) or (FRaw[E] = #13) then
        begin
          Dec(E);
          Break;
        end
        else
          Inc(E);
      end;
      if E > N then E:= N;
      Blank(I, E);
      I:= E + 1;
    end
    else
      Inc(I);
  end;
  FMasked:= string.Create(Chars);
end;

procedure TAppSrc.BuildTokens;
var
  I, N, S: Integer;
  T: TAppTok;
begin
  N:= Length(FMasked);
  I:= 1;
  while I <= N do
  begin
    if IsIdentStart(FMasked[I]) then
    begin
      S:= I;
      while (I <= N) and IsIdentChar(FMasked[I]) do Inc(I);
      T.Text  := Copy(FMasked, S, I - S);
      T.Low   := LowerCase(T.Text);
      T.Pos   := S;
      T.EndPos:= I;
      FToks.Add(T);
    end
    else if CharInSet(FMasked[I], ['0'..'9', '$']) then
    begin
      Inc(I);
      while (I <= N) and IsIdentChar(FMasked[I]) do Inc(I);
    end
    else
      Inc(I);
  end;
end;

procedure TAppSrc.BuildBlocks;
var
  Stack: TList<Integer>;
  D: TAppDirective;
  B: TAppCondBlock;
  Name, Rest: string;
  SP: Integer;
begin
  Stack:= TList<Integer>.Create;
  try
    for D in FDirs do
    begin
      SP:= Pos(' ', D.Text);
      if SP = 0 then
      begin
        Name:= D.Text;
        Rest:= '';
      end
      else
      begin
        Name:= Copy(D.Text, 1, SP - 1);
        Rest:= Trim(Copy(D.Text, SP + 1, MaxInt));
      end;
      if (Name = '$IFDEF') or (Name = '$IFNDEF') or (Name = '$IF') or (Name = '$IFOPT') then
      begin
        B:= Default(TAppCondBlock);
        B.StartPos:= D.Pos;
        B.EndPos  := MaxInt;
        B.Cond    := Rest;
        B.Negated := Name = '$IFNDEF';
        Stack.Add(FBlocks.Add(B));
      end
      else if ((Name = '$ELSE') or (Name = '$ELSEIF')) and (Stack.Count > 0) then
      begin
        B:= FBlocks[Stack[Stack.Count - 1]];
        if B.ElsePos = 0 then
        begin
          B.ElsePos:= D.Pos;
          FBlocks[Stack[Stack.Count - 1]]:= B;
        end;
      end
      else if ((Name = '$ENDIF') or (Name = '$IFEND')) and (Stack.Count > 0) then
      begin
        B:= FBlocks[Stack[Stack.Count - 1]];
        B.EndPos:= D.Pos;
        FBlocks[Stack[Stack.Count - 1]]:= B;
        Stack.Delete(Stack.Count - 1);
      end;
    end;
  finally
    Stack.Free;
  end;
end;

function TAppSrc.NextNonWs(APos: Integer): Integer;
begin
  Result:= APos;
  while (Result <= Length(FMasked)) and CharInSet(FMasked[Result], [' ', #9, #10, #13]) do Inc(Result);
  if Result > Length(FMasked) then Result:= 0;
end;

function TAppSrc.PrevCh(APos: Integer): Char;
var P: Integer;
begin
  P:= APos - 1;
  while (P >= 1) and CharInSet(FMasked[P], [' ', #9, #10, #13]) do Dec(P);
  if P >= 1 then Result:= FMasked[P] else Result:= #0;  // dl:ok ifthen-to-if-expression@3eb5 -- REVIEWED 2026-11-14 v151 INT: classic if/else kept in a lane unit written before the ternary sweep
end;

function TAppSrc.IsRoutineStart(AIdx: Integer): Boolean;
var Low: string;
begin
  Low:= FToks[AIdx].Low;
  Result:= (Low = 'procedure') or (Low = 'function') or (Low = 'constructor') or (Low = 'destructor');
  if not Result then Exit;
  if CharInSet(PrevCh(FToks[AIdx].Pos), ['=', ':', '(', ',', '<']) then Exit(False);
  if (AIdx > 0) and ((FToks[AIdx - 1].Low = 'to') or (FToks[AIdx - 1].Low = 'of')) then Exit(False);
end;

function TAppSrc.IsTypeBodyStart(AIdx: Integer): Boolean;
var Low: string; P: Integer;
begin
  Low:= FToks[AIdx].Low;
  Result:= (Low = 'class') or (Low = 'record') or (Low = 'object') or (Low = 'interface') or (Low = 'dispinterface');
  if not Result then Exit;
  P:= FToks[AIdx].Pos;
  if (Low = 'record') and (AIdx > 0) and (FToks[AIdx - 1].Low = 'packed') then P:= FToks[AIdx - 1].Pos;
  Result:= PrevCh(P) = '=';
end;

procedure TAppSrc.SkipTypeBody(var AIdx: Integer);
var
  Low: string;
  Q, Depth, Lvl: Integer;
begin
  Low:= FToks[AIdx].Low;
  if Low <> 'record' then
  begin
    Q:= NextNonWs(FToks[AIdx].EndPos);
    if (Low = 'class') and (Q > 0) and (Copy(LowerCase(Copy(FMasked, Q, 3)), 1, 3) = 'of ') then  // dl:ok magic-literal@9982 -- REVIEWED 2026-11-14 v151 INT: a spec value / fixed offset or length read at its single use site; a named constant adds nothing
    begin
      Inc(AIdx);
      Exit;
    end;
    // optional modifiers, then an optional ancestor list, then ';' = forward declaration
    while (Q > 0) and ((LowerCase(Copy(FMasked, Q, 8)) = 'abstract') or (LowerCase(Copy(FMasked, Q, 6)) = 'sealed')) do  // dl:ok uppercase-compare@5086, magic-literal@5086 -- REVIEWED 2026-11-14 v151 INT: keyword match on a Copy of the masked source; SameText would need the same Copy; a spec value / fixed offset or length read at its single use site; a named constant adds nothing
    begin
      while (Q <= Length(FMasked)) and IsIdentChar(FMasked[Q]) do Inc(Q);
      Q:= NextNonWs(Q);
    end;
    if (Q > 0) and (FMasked[Q] = '(') then
    begin
      Lvl:= 0;
      while Q <= Length(FMasked) do
      begin
        if FMasked[Q] = '(' then Inc(Lvl)
        else if FMasked[Q] = ')' then
        begin
          Dec(Lvl);
          if Lvl = 0 then Break;
        end;
        Inc(Q);
      end;
      Q:= NextNonWs(Q + 1);
    end;
    if (Q > 0) and (FMasked[Q] = ';') then
    begin
      Inc(AIdx);
      Exit;
    end;
  end;
  Depth:= 1;
  Inc(AIdx);
  while (AIdx < FToks.Count) and (Depth > 0) do
  begin
    if FToks[AIdx].Low = 'record' then Inc(Depth)
    else if FToks[AIdx].Low = 'end' then Dec(Depth);
    Inc(AIdx);
  end;
end;

procedure TAppSrc.ParseRoutine(var AIdx: Integer);
var
  KwTok: TAppTok;
  R: TAppRoutine;
  P, Lvl, NameStart: Integer;
  Low: string;
  Depth: Integer;
  Done: Boolean;
begin
  KwTok:= FToks[AIdx];
  P:= NextNonWs(KwTok.EndPos);
  if P = 0 then
  begin
    AIdx:= FToks.Count;
    Exit;
  end;
  NameStart:= P;
  while (P <= Length(FMasked)) and (IsIdentChar(FMasked[P]) or CharInSet(FMasked[P], ['.', '<', '>'])) do Inc(P);
  R:= Default(TAppRoutine);
  R.Name     := Copy(FMasked, NameStart, P - NameStart);
  R.HeaderPos:= KwTok.Pos;
  // header ends at the first ';' outside parentheses
  Lvl:= 0;
  while P <= Length(FMasked) do
  begin
    if FMasked[P] = '(' then Inc(Lvl)
    else if FMasked[P] = ')' then Dec(Lvl)
    else if (FMasked[P] = ';') and (Lvl <= 0) then Break;
    Inc(P);
  end;
  if P > Length(FMasked) then
  begin
    AIdx:= FToks.Count;
    Exit;
  end;
  while (AIdx < FToks.Count) and (FToks[AIdx].Pos < P) do Inc(AIdx);
  // directives after the header
  while (AIdx < FToks.Count) and (Pos(',' + FToks[AIdx].Low + ',', DIRECTIVE_WORDS) > 0) do Inc(AIdx);  // dl:ok pos-for-contains@687d -- REVIEWED 2026-11-14 v151 INT: Pos over a delimited keyword list, as the rest of the unit does
  if (AIdx < FToks.Count) and ((FToks[AIdx].Low = 'forward') or (FToks[AIdx].Low = 'external')) then
  begin
    Inc(AIdx);
    Exit;
  end;
  Done:= False;
  while (AIdx < FToks.Count) and not Done do
  begin
    Low:= FToks[AIdx].Low;
    if (Low = 'begin') or (Low = 'asm') then
    begin
      R.BodyPos:= FToks[AIdx].Pos;
      Depth:= 1;
      Inc(AIdx);
      while (AIdx < FToks.Count) and (Depth > 0) do
      begin
        if Pos(',' + FToks[AIdx].Low + ',', OPENER_WORDS) > 0 then Inc(Depth)  // dl:ok pos-for-contains@c89f -- REVIEWED 2026-11-14 v151 INT: Pos over a delimited keyword list, as the rest of the unit does
        else if FToks[AIdx].Low = 'end' then Dec(Depth);
        Inc(AIdx);
      end;
      R.BodyEnd:= FToks[AIdx - 1].EndPos;
      FRoutines.Add(R);
      Done:= True;
    end
    else if IsRoutineStart(AIdx) then
      ParseRoutine(AIdx)
    else if IsTypeBodyStart(AIdx) then
      SkipTypeBody(AIdx)
    else
      Inc(AIdx);
  end;
end;

procedure TAppSrc.FindRoutines;
var
  I: Integer;
begin
  I:= 0;
  while (I < FToks.Count) and (FToks[I].Low <> 'implementation') do Inc(I);
  if I >= FToks.Count then I:= 0 else Inc(I);
  while I < FToks.Count do
  begin
    if IsTypeBodyStart(I) then
      SkipTypeBody(I)
    else if IsRoutineStart(I) then
      ParseRoutine(I)
    else
      Inc(I);
  end;
end;

function TAppSrc.LineOf(APos: Integer): Integer;
var Lo, Hi, Mid: Integer;
begin
  Lo:= 0;
  Hi:= High(FLineStarts);
  while Lo < Hi do
  begin
    Mid:= (Lo + Hi + 1) div 2;
    if FLineStarts[Mid] <= APos then Lo:= Mid else Hi:= Mid - 1;
  end;
  Result:= Lo + 1;
end;

function TAppSrc.ColOf(APos: Integer): Integer;
begin
  Result:= APos - FLineStarts[LineOf(APos) - 1] + 1;
end;

function TAppSrc.Enclosing(APos: Integer): TArray<TAppCondBlock>;
var B: TAppCondBlock;
begin
  Result:= nil;
  for B in FBlocks do
    if (B.StartPos < APos) and (APos < B.EndPos) then Result:= Result + [B];
end;

function TAppSrc.BranchArch(const ABlock: TAppCondBlock; APos: Integer): TAppArch;
var Then64, Then32, Neg: Boolean;
begin
  Then64:= TRegEx.IsMatch(ABlock.Cond, ARCH64_RE);
  Then32:= TRegEx.IsMatch(ABlock.Cond, ARCH32_RE);
  Neg   := ABlock.Negated or TRegEx.IsMatch(ABlock.Cond, '\bNOT\b');
  if Then64 = Then32 then Exit(aaNone);  // names neither, or both
  if Neg then
    Then64:= not Then64;
  if (ABlock.ElsePos > 0) and (APos > ABlock.ElsePos) then
    Then64:= not Then64;
  if Then64 then Result:= aaX64 else Result:= aaX86;  // dl:ok ifthen-to-if-expression@89a2 -- REVIEWED 2026-11-14 v151 INT: classic if/else kept in a lane unit written before the ternary sweep
end;

function TAppSrc.HasX64Directive: Boolean;
var D: TAppDirective;
begin
  Result:= False;
  for D in FDirs do
    if TRegEx.IsMatch(D.Text, ARCH64_RE) then Exit(True);
end;

function TAppSrc.BodyOf(const ARoutine: TAppRoutine): string;
begin
  Result:= Copy(FMasked, ARoutine.BodyPos, ARoutine.BodyEnd - ARoutine.BodyPos);
end;

{ TAppChecks }

class procedure TAppChecks.TlsVerificationDisabled(const ASrc: TAppSrc; const APath: string; AOut: TList<TLintFinding>);
const
  CERT_WORDS_RE = 'cert|verif|x509|ssl|tls|peer';
  HEADER_RE =
    '\A((?:(?!\bbegin\b|\b(?:procedure|function)\b)[\s\S]){0,400}?)\)?\s*(?::\s*Boolean)?\s*;\s*' +
    '(?:(?:stdcall|cdecl|register|safecall|inline|overload|virtual|override)\s*;\s*)*\z';
  ACCEPT_LHS = 'Result|Accepted|AAccepted|IsValid|AIsValid|Valid|AValid|AOk|Ok';
var
  M, H: TMatch;
  R: TAppRoutine;
  KwLen: Integer;
  Header, Body, Stmt, OwnName: string;
begin
  for M in TRegEx.Matches(ASrc.Masked, '\bVerifyMode\s*:=\s*\[\s*\]', [roIgnoreCase]) do
    AOut.Add(MakeFinding(ASrc, APath, RULE_TLS_VERIFY_OFF, 'warning',
      'The TLS peer verification mode is set to the empty set -- the server certificate is never checked, so any man in the middle is accepted.',
      M.Index + 1, M.Index + 1 + M.Length));
  for M in TRegEx.Matches(ASrc.Masked, '\b[A-Z_]*IGNORE_(?:UNKNOWN_CA|CERT_CN_INVALID|CERT_DATE_INVALID|REVOCATION|WRONG_USAGE)\b(?!\s*=)', [roIgnoreCase]) do
    AOut.Add(MakeFinding(ASrc, APath, RULE_TLS_VERIFY_OFF, 'warning',
      'A flag that tells the HTTP stack to ignore certificate errors is used -- the connection is no longer authenticated.',
      M.Index + 1, M.Index + 1 + M.Length));
  for M in TRegEx.Matches(ASrc.Masked, '\b(?:VerifyPeer|VerifyServerCert\w*|VerifyCert\w*|CheckServerCert\w*|ValidateServerCert\w*)\s*:=\s*False\b', [roIgnoreCase]) do
    AOut.Add(MakeFinding(ASrc, APath, RULE_TLS_VERIFY_OFF, 'warning',
      'Certificate verification is switched off by this assignment -- the server certificate is no longer checked.',
      M.Index + 1, M.Index + 1 + M.Length));
  // Structural scan over the parsed routines: a handler is a procedure/function whose header names a certificate
  // and whose whole body only returns True (Result / Accepted / ... / the routine's own name := True, Exit(True);
  // the last statement may omit its semicolon). A file that never says cert/verif/x509/ssl/tls/peer cannot hold one.
  if TRegEx.IsMatch(ASrc.Masked, CERT_WORDS_RE, [roIgnoreCase]) then
    for R in ASrc.Routines do
    begin
      KwLen:= 0;
      while IsIdentChar(ASrc.Masked[R.HeaderPos + KwLen]) do Inc(KwLen);
      if not (SameText(Copy(ASrc.Masked, R.HeaderPos, KwLen), 'procedure') or SameText(Copy(ASrc.Masked, R.HeaderPos, KwLen), 'function')) then Continue;
      Header:= Copy(ASrc.Masked, R.HeaderPos + KwLen, R.BodyPos - R.HeaderPos - KwLen);
      H:= TRegEx.Match(Header, HEADER_RE, [roIgnoreCase]);
      if not H.Success or not TRegEx.IsMatch(H.Groups[1].Value, CERT_WORDS_RE, [roIgnoreCase]) then Continue;
      OwnName:= R.Name;
      if Pos('.', OwnName) > 0 then OwnName:= Copy(OwnName, LastDelimiter('.', OwnName) + 1, MaxInt);
      Stmt:= '(?:(?:' + ACCEPT_LHS + '|' + TRegEx.Escape(OwnName) + ')\s*:=\s*True|Exit\s*\(\s*True\s*\))';
      Body:= ASrc.BodyOf(R);
      if TRegEx.IsMatch(Body, '\Abegin\s*(?:' + Stmt + '\s*;\s*)*' + Stmt + '\s*;?\s*end\z', [roIgnoreCase]) then
        AOut.Add(MakeFinding(ASrc, APath, RULE_TLS_VERIFY_OFF, 'warning',
          'This certificate verification handler accepts every certificate unconditionally -- it makes the TLS check a no-op.',
          R.HeaderPos + 1, R.HeaderPos + 10));  // dl:ok magic-literal@1581 -- REVIEWED 2026-11-14 v151 INT: a spec value / fixed offset or length read at its single use site; a named constant adds nothing
    end;
end;
class procedure TAppChecks.UiCallInConsoleOrService(const ASrc: TAppSrc; const APath: string; AOut: TList<TLintFinding>);
const
  CALL_RE =
    '(\b(?:procedure|function)\s+)?(?:(?<![\w\.])|\b(?:(?:Vcl|FMX)\.)?Dialogs\.)' +
    '(?:ShowMessage|ShowMessageFmt|ShowMessagePos|MessageDlg|MessageDlgPos|TaskMessageDlg|InputBox|InputQuery)\s*\(' +
    '|\bApplication\s*\.\s*MessageBox\s*\(|\bTDialogService\s*\.\s*\w+\s*\(';
var
  M: TMatch;
  IsConsoleApp: Boolean;
  Services: TList<string>;
  Pair: TMatch;
  Added: Boolean;
  R: TAppRoutine;
  Body: string;
  Cls: string;
  Reported: TList<Integer>;

  procedure Report(APos, ALen: Integer; const AWhere: string);
  begin
    if Reported.Contains(APos) then Exit;
    Reported.Add(APos);
    AOut.Add(MakeFinding(ASrc, APath, RULE_UI_CALL, 'warning',
      'A dialog is shown ' + AWhere + ' -- there is no desktop to show it on, so the call blocks forever or fails.',
      APos, APos + ALen));
  end;

begin
  IsConsoleApp:= TRegEx.IsMatch(ASrc.Raw, '\{\$APPTYPE\s+CONSOLE\s*\}', [roIgnoreCase]);
  Services:= TList<string>.Create;
  Reported:= TList<Integer>.Create;
  try
    if IsConsoleApp then
      for M in TRegEx.Matches(ASrc.Masked, CALL_RE, [roIgnoreCase]) do
        if (M.Groups.Count < 2) or not M.Groups[1].Success then Report(M.Index + 1, M.Length, 'in a console program');
    // classes that descend from a service class (transitively, within this file)
    Services.Add('tservice');
    Services.Add('tserviceapplication');
    repeat
      Added:= False;
      for Pair in TRegEx.Matches(ASrc.Masked, '\b(\w+)\s*=\s*class\s*\(\s*(\w+)\s*[,)]', [roIgnoreCase]) do
        if Services.Contains(LowerCase(Pair.Groups[2].Value)) and not Services.Contains(LowerCase(Pair.Groups[1].Value)) then
        begin
          Services.Add(LowerCase(Pair.Groups[1].Value));
          Added:= True;
        end;
    until not Added;
    for R in ASrc.Routines do
    begin
      if Pos('.', R.Name) = 0 then Continue;  // dl:ok pos-for-contains@eb1e -- REVIEWED 2026-11-14 v151 INT: Pos over a delimited keyword list, as the rest of the unit does
      Cls:= LowerCase(Copy(R.Name, 1, Pos('.', R.Name) - 1));
      if (Cls = 'tservice') or (Cls = 'tserviceapplication') or not Services.Contains(Cls) then Continue;
      Body:= ASrc.BodyOf(R);
      for M in TRegEx.Matches(Body, CALL_RE, [roIgnoreCase]) do
        if (M.Groups.Count < 2) or not M.Groups[1].Success then Report(R.BodyPos + M.Index, M.Length, 'in a method of a Windows service');
    end;
  finally
    Reported.Free;
    Services.Free;
  end;
end;

class procedure TAppChecks.DunitxTestWithoutAssert(const ASrc: TAppSrc; const APath: string; AOut: TList<TLintFinding>);
var
  Asserting, Known: TDictionary<string, Boolean>;
  Calls: TDictionary<string, TArray<string>>;
  R: TAppRoutine;
  W: TMatch;
  Last: string;
  Words: TArray<string>;
  Changed, IsA: Boolean;
  Pair: TPair<string, TArray<string>>;
  Cls, Attrs, Meth: string;
  AttrM: TMatch;
  ClassM: TMatch;
  Key: string;
  Seen: TList<string>;

  function IsAssertWord(const AWord: string): Boolean;
  begin
    Result:= TRegEx.IsMatch(AWord, '^(Assert\w*|Check\w*|Fail|Expect\w*|Verify\w*|StartExpectingException|Pass|Warn)$', [roIgnoreCase]);
  end;

begin
  if not TRegEx.IsMatch(ASrc.Masked, '\[\s*Test(Case)?\b', [roIgnoreCase]) then Exit;
  Asserting:= TDictionary<string, Boolean>.Create;
  Known:= TDictionary<string, Boolean>.Create;
  Calls:= TDictionary<string, TArray<string>>.Create;
  Seen:= TList<string>.Create;
  try
    // per routine: does it check anything itself, and which names does it mention
    for R in ASrc.Routines do
    begin
      Last:= LowerCase(R.Name);
      Last:= Copy(Last, LastDelimiter('.', Last) + 1, MaxInt);
      Words:= nil;
      IsA:= False;
      for W in TRegEx.Matches(ASrc.BodyOf(R), '[A-Za-z_]\w*') do
      begin
        if IsAssertWord(W.Value) then IsA:= True;
        Words:= Words + [LowerCase(W.Value)];
      end;
      if Asserting.ContainsKey(Last) then Asserting[Last]:= Asserting[Last] or IsA else Asserting.Add(Last, IsA);  // dl:ok double-dictionary-lookup@1be7 -- REVIEWED 2026-11-14 v151 INT: iterates one map and reads another by key, not a double lookup
      if Calls.ContainsKey(Last) then Calls[Last]:= Calls[Last] + Words else Calls.Add(Last, Words);  // dl:ok double-dictionary-lookup@9b31 -- REVIEWED 2026-11-14 v151 INT: iterates one map and reads another by key, not a double lookup
      Known.AddOrSetValue(Last, True);
    end;
    repeat
      Changed:= False;
      for Pair in Calls do
        if not Asserting[Pair.Key] then
          for Key in Pair.Value do
            if Known.ContainsKey(Key) and Asserting[Key] then
            begin
              Asserting[Pair.Key]:= True;
              Changed:= True;
              Break;
            end;
    until not Changed;
    for AttrM in TRegEx.Matches(ASrc.Masked, '((?:\[[^\]\[]*\]\s*)+)(?:class\s+)?(?:procedure|function)\s+(\w+)', [roIgnoreCase]) do
    begin
      Attrs:= AttrM.Groups[1].Value;
      Meth := AttrM.Groups[2].Value;
      if not TRegEx.IsMatch(Attrs, '\[\s*(?:[\w\s,\(\)]*,\s*)?Test(?:Case)?\b', [roIgnoreCase]) then Continue;
      if TRegEx.IsMatch(Attrs, '\b(?:Ignore|WillRaise|ExpectedException)\b', [roIgnoreCase]) then Continue;
      // the class this method belongs to: the nearest `X = class` before the attribute
      Cls:= '';
      for ClassM in TRegEx.Matches(Copy(ASrc.Masked, 1, AttrM.Index), '\b(\w+)\s*=\s*(?:class|record)\b', [roIgnoreCase]) do
        Cls:= ClassM.Groups[1].Value;
      if Cls = '' then Continue;
      Key:= LowerCase(Cls + '.' + Meth);
      for R in ASrc.Routines do
        if SameText(R.Name, Key) and not Seen.Contains(Key) then
        begin
          Seen.Add(Key);
          if not Asserting[LowerCase(Meth)] then
            AOut.Add(MakeFinding(ASrc, APath, RULE_DUNITX_NO_ASSERT, 'info',
              'The test ' + Meth + ' checks nothing -- it can only fail by raising, so it proves less than its name promises. Add an assertion, or mark it with WillRaise if an exception is the expected result.',
              R.HeaderPos, R.HeaderPos + 9));  // dl:ok magic-literal@f914 -- REVIEWED 2026-11-14 v151 INT: a spec value / fixed offset or length read at its single use site; a named constant adds nothing
          Break;
        end;
    end;
  finally
    Seen.Free;
    Calls.Free;
    Known.Free;
    Asserting.Free;
  end;
end;

class procedure TAppChecks.ContractUnitDeclaresClass(const ASrc: TAppSrc; const APath: string; AOut: TList<TLintFinding>);
var
  UnitM, M: TMatch;
  UnitName, LastSeg, Intf: string;
  ImplPos: Integer;
begin
  UnitM:= TRegEx.Match(ASrc.Masked, '^\s*unit\s+([\w\.]+)\s*;', [roIgnoreCase]);
  if not UnitM.Success then Exit;
  UnitName:= UnitM.Groups[1].Value;
  LastSeg:= Copy(UnitName, LastDelimiter('.', UnitName) + 1, MaxInt);
  if not TRegEx.IsMatch(LastSeg, '^(Intf|Interfaces?|Contracts?|Abstractions?)$', [roIgnoreCase]) then Exit;
  ImplPos:= Length(ASrc.Masked) + 1;
  M:= TRegEx.Match(ASrc.Masked, '\bimplementation\b', [roIgnoreCase]);
  if M.Success then ImplPos:= M.Index;
  Intf:= Copy(ASrc.Masked, 1, ImplPos - 1);
  for M in TRegEx.Matches(Intf, '\b(\w+)\s*=\s*(?:packed\s+)?(?:class|object)\b(?!\s+of\b)(?!\s*(?:abstract\s*|sealed\s*)?\(\s*(?:Exception|E[A-Z]\w*)\s*\))', [roIgnoreCase]) do
    AOut.Add(MakeFinding(ASrc, APath, RULE_CONTRACT_CLASS, 'info',
      'The contract unit ' + UnitName + ' declares the class ' + M.Groups[1].Value + ' -- contract units should hold only interfaces and plain types; move the class to an implementation unit.',
      M.Groups[1].Index + 1, M.Groups[1].Index + 1 + M.Groups[1].Length));
end;

class procedure TAppChecks.WeakCipher(const ASrc: TAppSrc; const APath: string; AOut: TList<TLintFinding>);
const
  CIPHER_RE =
    '\b(?:TDCP_(?:des|3des|rc2|rc4|rc5)|cmECB|CALG_(?:DES|3DES|3DES_112|RC2|RC4)|BCRYPT_(?:DES|3DES|3DES_112|RC2|RC4)_ALGORITHM|' +
    'BCRYPT_CHAIN_MODE_ECB|EVP_(?:des|rc2|rc4)\w*|EVP_\w+_ecb|DES_ecb_encrypt|TIdBlockCipherIntercept)\b(?!\s*=\s*(?:class|\$|\d))';
var
  M: TMatch;
begin
  for M in TRegEx.Matches(ASrc.Masked, CIPHER_RE, [roIgnoreCase]) do
    AOut.Add(MakeFinding(ASrc, APath, RULE_WEAK_CIPHER, 'warning',
      'The cipher or mode ' + M.Value + ' is broken or leaks plaintext structure (DES, 3DES, RC2, RC4, ECB) -- use AES in GCM or CBC mode with a random IV.',
      M.Index + 1, M.Index + 1 + M.Length));
end;

class procedure TAppChecks.AsmWithoutWin64Variant(const ASrc: TAppSrc; const APath: string; AOut: TList<TLintFinding>);
var
  T: TAppTok;
  Blocks: TArray<TAppCondBlock>;
  B: TAppCondBlock;
  Inner: Integer;
  HasElse, Fire: Boolean;
  Arch: TAppArch;
  I: Integer;
begin
  for T in ASrc.Toks do
  begin
    if T.Low <> 'asm' then Continue;
    Blocks:= ASrc.Enclosing(T.Pos);
    HasElse:= False;
    for B in Blocks do
      if B.ElsePos > 0 then HasElse:= True;
    Inner:= -1;
    for I:= High(Blocks) downto 0 do
      if ASrc.BranchArch(Blocks[I], T.Pos) <> aaNone then
      begin
        Inner:= I;
        Break;
      end;
    if Inner >= 0 then
    begin
      Arch:= ASrc.BranchArch(Blocks[Inner], T.Pos);
      Fire:= (Arch = aaX86) and (Blocks[Inner].ElsePos = 0) and not HasElse and not ASrc.HasX64Directive;
    end
    else
      Fire:= not HasElse and not ASrc.HasX64Directive;
    if Fire then
      AOut.Add(MakeFinding(ASrc, APath, RULE_ASM_NO_WIN64, 'warning',
        'This asm block has no 64-bit variant -- 32-bit assembler does not run on Win64; add a {$IFDEF CPUX64} version or a plain Pascal fallback.',
        T.Pos, T.EndPos));
  end;
end;

class procedure TAppChecks.WritelnInGuiApp(const ASrc: TAppSrc; const APath: string; AOut: TList<TLintFinding>);
var
  Uses_, FirstArg: string;  // dl:ok local-var-casing@9fb2 -- REVIEWED 2026-11-14 v151 INT: inline var spelled like the surrounding unit
  UM, M: TMatch;
  Gui, Console: Boolean;
  Blocks: TArray<TAppCondBlock>;
  B: TAppCondBlock;
  Skip: Boolean;
  R: TAppRoutine;
begin
  Console:= TRegEx.IsMatch(ASrc.Raw, '\{\$APPTYPE\s+CONSOLE\s*\}', [roIgnoreCase]) or
    TRegEx.IsMatch(ASrc.Masked, '\b(?:AllocConsole|IsConsole|AttachConsole)\b', [roIgnoreCase]);
  if Console then Exit;
  Uses_:= '';
  for UM in TRegEx.Matches(ASrc.Masked, '\buses\b([\s\S]*?);', [roIgnoreCase]) do Uses_:= Uses_ + ' ' + UM.Groups[1].Value;
  Gui:= TRegEx.IsMatch(Uses_, '\b(?:Vcl\.|FMX\.)?(?:Forms|Controls)\b', [roIgnoreCase]);
  if not Gui then Exit;
  for M in TRegEx.Matches(ASrc.Masked, '(?<![\w\.])(?:System\.)?(Write|WriteLn)\s*\(\s*([^,\)]*)', [roIgnoreCase]) do
  begin
    FirstArg:= Trim(M.Groups[2].Value);
    // a file / stream target: the first argument is a declared text file variable
    if (FirstArg <> '') and TRegEx.IsMatch(FirstArg, '^\w+$') and
       (TRegEx.IsMatch(FirstArg, '(?:File|Log|Txt|Writer|Stream)$', [roIgnoreCase]) or
        TRegEx.IsMatch(ASrc.Masked, '\b' + FirstArg + '\b\s*(?:,\s*\w+\s*)*:\s*(?:System\.)?(?:TextFile|Text|TStreamWriter|TTextWriter|TStringWriter)\b', [roIgnoreCase])) then Continue;
    Skip:= False;
    Blocks:= ASrc.Enclosing(M.Index + 1);
    for B in Blocks do
      if TRegEx.IsMatch(B.Cond, 'CONSOLE|DEBUG|TESTINSIGHT') then Skip:= True;
    if Skip then Continue;
    for R in ASrc.Routines do
      if (R.BodyPos <= M.Index + 1) and (M.Index + 1 < R.BodyEnd) and TRegEx.IsMatch(ASrc.BodyOf(R), '\bIsConsole\b', [roIgnoreCase]) then Skip:= True;
    if Skip then Continue;
    AOut.Add(MakeFinding(ASrc, APath, RULE_WRITELN_GUI, 'warning',
      M.Groups[1].Value + ' writes to the console, but this program has no console (a GUI application) -- the call raises I/O error 105 or goes nowhere. Log to a file or the debugger instead.',
      M.Groups[1].Index + 1, M.Groups[1].Index + 1 + Length(M.Groups[1].Value)));
  end;
end;

end.
