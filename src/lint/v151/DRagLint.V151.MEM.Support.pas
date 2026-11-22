unit DRagLint.V151.MEM.Support;

{ Wave v151 lane MEM -- the AST walker behind DRagLint.V151.MEM (private to the lane).
  Rules emitted: pchar-of-temporary, createprocess-readonly-commandline,
  managed-type-raw-memory, raw-memory-leak, handle-leak, char-count-as-bytes and the
  in-place expansion of unsafe-string-api (an Ansi API fed a converted Unicode string).
  Pure AST over the shared parse cache; declared types come from the source
  (DeclaredTypeAt), record / interface types from the file first and then from the
  project and library stores. Every question that cannot be answered completely is
  answered "unknown" (no finding): absence over wrong. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , TreeSitter
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

type
  /// <summary>One run of the MEM rules over one parsed file.</summary>
  /// <remarks>
  /// Create, Run once, Free. Not thread-safe; the owner is TV151MEMRules.CheckFile.
  /// The stores may be nil: type questions then fall back to the file alone.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.V151.MEM.TV151MEMRules.CheckFile (DRagLint.V151.MEM.pas)</para>
  /// <para>Used in units: DRagLint.V151.MEM</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TMemRun = class  // dl:ok high-response@413b -- REVIEWED 2026-11-14 v151 MEM: one walker per file run; the rules share its AST helpers and per-run state, splitting it would only pass that state around
  strict private
    FFile        : string;
    FSrc         : TBytes;
    FStore       : ISymbolStore;
    FLib         : ISymbolStore;
    FWants       : TFunc<string, Boolean>;
    FRoot        : TTSNode;
    FFindings    : TList<TLintFinding>;
    FTypeDecls   : TDictionary<string, TTSNode>;   // lower type name -> its declType node
    FConsts      : TDictionary<string, Boolean>;   // lower names of every const of the file
    FManagedCache: TDictionary<string, Boolean>;   // lower type name -> managed (store answers)
    /// <param name="N"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <returns><!-- drag-lint:auto -->string -- Observed: '';
    /// TEncoding.UTF8.GetString(FSrc, S, L).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.CallName (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.CheckAnsiApi (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.CheckAssignment (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.CheckCharCount (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.CheckCreateProcess (DRagLint.V151.MEM.Support.pas) (+16 more)</para>
    /// <para>Calls: Integer, TreeSitter.TTSNodeHelper.EndByte, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.StartByte</para>
    /// <para>Reads: FSrc</para>
    /// <seealso cref="TreeSitter.TTSNodeHelper.EndByte"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.IsNull"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.StartByte"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallArgs"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallName"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function NodeStr(const N: TTSNode): string;
    /// <param name="N"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <returns><!-- drag-lint:auto -->string -- Observed: B.ToString.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.CheckCharCount (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.CheckManagedRaw (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.IsManagedTypeNode (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.IsValueStringParam (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.PointeeType (DRagLint.V151.MEM.Support.pas) (+2 more)</para>
    /// <para>Calls: CharInSet, DRagLint.V151.MEM.Support.TMemRun.NodeStr, LowerCase</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.NodeStr"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallArgs"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallName"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckAnsiApi"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckAssignment"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function LowerText(const N: TTSNode): string;
    /// <param name="N"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <param name="ARule"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AMsg"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ASev"><!-- drag-lint:auto type -->const string</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.CheckAnsiApi (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.CheckAssignment (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.CheckCharCount (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.CheckCreateProcess (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.CheckManagedRaw (DRagLint.V151.MEM.Support.pas) (+2 more)</para>
    /// <para>Calls: Default, DRagLint.Diagnostics.ParseCache.TAstParseCache.CharCol, FWants, Integer, TreeSitter.TTSNodeHelper.EndPoint, TreeSitter.TTSNodeHelper.StartPoint</para>
    /// <para>Reads: FWants, FFile, FFindings</para>
    /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.CharCol"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.EndPoint"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.StartPoint"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallArgs"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallName"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure EmitAt(const N: TTSNode; const ARule, AMsg, ASev: string);
    /// <summary><!-- drag-lint:auto sum -->The callee's last name segment in lower case:
    /// Foo(..) -&gt; foo, A.B.Foo(..) -&gt; foo; '' when N is not a call.</summary>
    /// <param name="ACall"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <returns><!-- drag-lint:auto -->string -- Observed: ''; LowerCase(NodeStr(E)).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.CheckAnsiApi (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.CheckCall (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.CheckCharCount (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.CheckManagedRaw (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.IsPCharCast (DRagLint.V151.MEM.Support.pas) (+5 more)</para>
    /// <para>Calls: DRagLint.V151.MEM.Support.TMemRun.IsIdent, DRagLint.V151.MEM.Support.TMemRun.NodeStr, LowerCase, TreeSitter.TTSNodeHelper.ChildByField/1, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NodeType</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.IsIdent"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.NodeStr"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.IsNull"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.NodeType"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function CallName(const ACall: TTSNode): string;
    /// <param name="ACall"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TTSNode&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.CheckAnsiApi (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.CheckCharCount (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.CheckCreateProcess (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.CheckManagedRaw (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.CheckPostFamily (DRagLint.V151.MEM.Support.pas) (+4 more)</para>
    /// <para>Calls: TreeSitter.TTSNodeHelper.ChildByField/1, TreeSitter.TTSNodeHelper.IsExtra, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NamedChild, TreeSitter.TTSNodeHelper.NamedChildCount</para>
    /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.IsExtra"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.IsNull"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.NamedChild"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.NamedChildCount"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function CallArgs(const ACall: TTSNode): TArray<TTSNode>;
    /// <param name="N"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: (not N.IsNull) and
    /// (N.NodeType = 'identifier').</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.CallName (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.CheckAnsiApi (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.CheckManagedRaw (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.CollectDecls (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.ContainsIdent (DRagLint.V151.MEM.Support.pas) (+10 more)</para>
    /// <para>Calls: TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NodeType</para>
    /// <seealso cref="TreeSitter.TTSNodeHelper.IsNull"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.NodeType"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallArgs"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallName"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckAnsiApi"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsIdent(const N: TTSNode): Boolean;
    /// <summary><!-- drag-lint:auto sum -->Declared type of an identifier at its
    /// position, lower case, no whitespace, no System. prefix.</summary>
    /// <param name="AIdent"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <param name="AType"><!-- drag-lint:auto type -->out string</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False; T &lt;&gt; ''.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.CheckAnsiApi (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.CheckCharCount (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.CheckManagedRaw (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.CheckRoutineLeaks.AddAllocHandle (DRagLint.V151.MEM.Support.pas) ?, DRagLint.V151.MEM.Support.TMemRun.ReadOnlyCommandLine (DRagLint.V151.MEM.Support.pas)</para>
    /// <para>Calls: Delete, DRagLint.Lint.QueryRules.DeclaredTypeAt, DRagLint.V151.MEM.Support.TMemRun.IsIdent, DRagLint.V151.MEM.Support.TMemRun.NodeStr, LowerCase, StartsStr, TreeSitter.TTSNodeHelper.StartByte</para>
    /// <para>Reads: FRoot, FSrc</para>
    /// <para>Mutates: AType (out)</para>
    /// <seealso cref="DRagLint.Lint.QueryRules.DeclaredTypeAt"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.IsIdent"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.NodeStr"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.StartByte"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallArgs"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function DeclTypeOf(const AIdent: TTSNode; out AType: string): Boolean;
    /// <param name="AType"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: MatchStr(AType, ['string',
    /// 'unicodestring', 'widestring']).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.CheckAnsiApi (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.CheckCharCount (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.IsLongString (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.IsValueStringParam (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.ReadOnlyCommandLine (DRagLint.V151.MEM.Support.pas)</para>
    /// <para>Calls: MatchStr</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallArgs"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallName"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckAnsiApi"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckAssignment"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckCall"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsUtf16String(const AType: string): Boolean;
    /// <param name="AType"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: IsUtf16String(AType) or
    /// MatchStr(AType, ['ansistring', 'rawbytestring', 'utf8string']).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.CheckManagedRaw (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.IsManagedType (DRagLint.V151.MEM.Support.pas)</para>
    /// <para>Calls: DRagLint.V151.MEM.Support.TMemRun.IsUtf16String, MatchStr</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.IsUtf16String"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallArgs"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallName"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckAnsiApi"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckAssignment"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsLongString(const AType: string): Boolean;
    /// <summary><!-- drag-lint:auto sum -->Every type and const declaration of the file,
    /// any scope (a later one of the same name wins).</summary>
    /// <param name="N"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.CollectDecls (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.Run (DRagLint.V151.MEM.Support.pas)</para>
    /// <para>Calls: DRagLint.V151.MEM.Support.TMemRun.CollectDecls, DRagLint.V151.MEM.Support.TMemRun.IsIdent, DRagLint.V151.MEM.Support.TMemRun.NodeStr, LowerCase, TreeSitter.TTSNodeHelper.ChildByField/1, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NamedChild, TreeSitter.TTSNodeHelper.NamedChildCount, TreeSitter.TTSNodeHelper.NodeType</para>
    /// <para>Reads: FTypeDecls, FConsts</para>
    /// <para>Recursive</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.IsIdent"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.NodeStr"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.IsNull"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.NamedChild"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure CollectDecls(const N: TTSNode);
    /// <summary><!-- drag-lint:auto sum -->A type whose values hold a reference the
    /// compiler counts or finalizes: long strings, variants, interfaces, dynamic arrays,
    /// and records / static arrays that contain one. Unknown -&gt; False.</summary>
    /// <param name="AType"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ADepth"><!-- drag-lint:auto type -->Integer</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False; True;
    /// IsManagedType(Copy(T, P + Length(']of'), MaxInt), ADepth + 1);
    /// IsManagedTypeNode(D, ADepth + 1); StoreTypeManaged(T, ADepth + 1).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.CheckManagedRaw (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.IsManagedType (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.IsManagedTypeNode (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.IsManagedTypeNode.FieldsManaged (DRagLint.V151.MEM.Support.pas) ?, DRagLint.V151.MEM.Support.TMemRun.StoreTypeManaged.Verdict (DRagLint.V151.MEM.Support.pas) ?</para>
    /// <para>Calls: Copy, Delete, DRagLint.V151.MEM.Support.TMemRun.IsLongString, DRagLint.V151.MEM.Support.TMemRun.IsManagedType, DRagLint.V151.MEM.Support.TMemRun.IsManagedTypeNode, DRagLint.V151.MEM.Support.TMemRun.StoreTypeManaged, MatchStr, Pos, StartsStr</para>
    /// <para>Complexity: 16 (cyclomatic, outer body), 27 lines (full implementation)</para>
    /// <para>Reads: FTypeDecls</para>
    /// <para>Recursive</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.IsLongString"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.IsManagedTypeNode"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.StoreTypeManaged"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallArgs"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallName"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsManagedType(const AType: string; ADepth: Integer): Boolean;
    /// <param name="ADecl"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <param name="ADepth"><!-- drag-lint:auto type -->Integer</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False; FieldsManaged(Inner);
    /// IsManagedType(LowerText(T), ADepth).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto -->ADecl is a declType node of this file.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.IsManagedType (DRagLint.V151.MEM.Support.pas)</para>
    /// <para>Calls: DRagLint.V151.MEM.Support.TMemRun.IsManagedType, DRagLint.V151.MEM.Support.TMemRun.IsManagedTypeNode.FieldsManaged, DRagLint.V151.MEM.Support.TMemRun.LowerText, MatchStr, TreeSitter.TTSNodeHelper.Child, TreeSitter.TTSNodeHelper.ChildByField/1, TreeSitter.TTSNodeHelper.ChildCount, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NamedChild, TreeSitter.TTSNodeHelper.NamedChildCount, TreeSitter.TTSNodeHelper.NodeType</para>
    /// <para>Complexity: 10 (cyclomatic, outer body), 44 lines (full implementation)</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.IsManagedType"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.IsManagedTypeNode.FieldsManaged"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.LowerText"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsManagedTypeNode(const ADecl: TTSNode; ADepth: Integer): Boolean;
    /// <summary><!-- drag-lint:auto sum -->A type declared outside the file: ask the
    /// project index, then the library. Every row of the name must agree; a name the
    /// stores do not know, or know ambiguously, is not managed.</summary>
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ADepth"><!-- drag-lint:auto type -->Integer</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: Verdict(FStore, Known);
    /// Verdict(FLib, Known); False.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.IsManagedType (DRagLint.V151.MEM.Support.pas)</para>
    /// <para>Calls: DRagLint.V151.MEM.Support.TMemRun.StoreTypeManaged.Verdict, IsManagedType, LowerCase, StringReplace</para>
    /// <para>Reads: FManagedCache, FStore, FLib</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.StoreTypeManaged.Verdict"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallArgs"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallName"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckAnsiApi"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckAssignment"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function StoreTypeManaged(const AName: string; ADepth: Integer): Boolean;
    /// <summary><!-- drag-lint:auto sum -->^T -&gt; t; a pointer alias declared in the
    /// file (PFoo = ^TFoo) -&gt; tfoo; anything else ''.</summary>
    /// <param name="AType"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->string -- Observed: ''; Copy(T, 2, MaxInt).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.CheckManagedRaw (DRagLint.V151.MEM.Support.pas)</para>
    /// <para>Calls: Copy, DRagLint.V151.MEM.Support.TMemRun.LowerText, StartsStr, TreeSitter.TTSNodeHelper.ChildByField/1</para>
    /// <para>Reads: FTypeDecls</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.LowerText"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallArgs"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallName"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckAnsiApi"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function PointeeType(const AType: string): string;
    /// <param name="N"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <returns><!-- drag-lint:auto type -->TTSNode</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.CheckManagedRaw (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.ReadOnlyCommandLine (DRagLint.V151.MEM.Support.pas)</para>
    /// <para>Calls: TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NodeType, TreeSitter.TTSNodeHelper.Parent</para>
    /// <seealso cref="TreeSitter.TTSNodeHelper.IsNull"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.NodeType"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.Parent"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallArgs"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallName"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function EnclosingRoutine(const N: TTSNode): TTSNode;
    /// <param name="N"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <param name="ALowerName"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.CheckCharCount (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.ContainsIdent (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.LocalAssignedReadOnly.Scan (DRagLint.V151.MEM.Support.pas) ?, DRagLint.V151.MEM.Support.TMemRun.RoutineHasCallOn.Scan (DRagLint.V151.MEM.Support.pas) ?</para>
    /// <para>Calls: DRagLint.V151.MEM.Support.TMemRun.ContainsIdent, DRagLint.V151.MEM.Support.TMemRun.IsIdent, DRagLint.V151.MEM.Support.TMemRun.NodeStr, LowerCase, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NamedChild, TreeSitter.TTSNodeHelper.NamedChildCount</para>
    /// <para>Recursive</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.IsIdent"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.NodeStr"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.IsNull"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.NamedChild"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.NamedChildCount"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ContainsIdent(const N: TTSNode; const ALowerName: string): Boolean;
    /// <param name="N"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.ContainsStringLiteral (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.IsTemporaryString (DRagLint.V151.MEM.Support.pas)</para>
    /// <para>Calls: DRagLint.V151.MEM.Support.TMemRun.ContainsStringLiteral, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NamedChild, TreeSitter.TTSNodeHelper.NamedChildCount, TreeSitter.TTSNodeHelper.NodeType</para>
    /// <para>Recursive</para>
    /// <seealso cref="TreeSitter.TTSNodeHelper.IsNull"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.NamedChild"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.NamedChildCount"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.NodeType"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallArgs"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ContainsStringLiteral(const N: TTSNode): Boolean;
    /// <param name="N"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <param name="AArg"><!-- drag-lint:auto type -->out TTSNode</param>
    /// <param name="AWideOnly"><!-- drag-lint:auto type -->Boolean = False</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False; True.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.CheckAnsiApi (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.CheckAssignment (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.FindTemporaryCast (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.ReadOnlyCommandLine (DRagLint.V151.MEM.Support.pas)</para>
    /// <para>Calls: Default, DRagLint.V151.MEM.Support.TMemRun.CallArgs, DRagLint.V151.MEM.Support.TMemRun.CallName, MatchStr, TreeSitter.TTSNodeHelper.ChildByField/1</para>
    /// <para>Mutates: AArg (out)</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallArgs"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallName"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckAnsiApi"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckAssignment"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsPCharCast(const N: TTSNode; out AArg: TTSNode; AWideOnly: Boolean = False): Boolean;
    /// <summary><!-- drag-lint:auto sum -->A string value with no variable behind it: a
    /// concatenation with a string literal or the result of a well-known string function.</summary>
    /// <param name="N"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed:
    /// (N.ChildByField('operator').NodeType = 'kAdd') and ContainsStringLiteral(N);
    /// (N.NodeType = 'exprCall') and MatchStr(CallName(N), STRING_FUNCS).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.CheckAssignment (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.FindTemporaryCast (DRagLint.V151.MEM.Support.pas)</para>
    /// <para>Calls: DRagLint.V151.MEM.Support.TMemRun.CallName, DRagLint.V151.MEM.Support.TMemRun.ContainsStringLiteral, MatchStr, TreeSitter.TTSNodeHelper.ChildByField/1, TreeSitter.TTSNodeHelper.NodeType</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallName"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.ContainsStringLiteral"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.NodeType"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallArgs"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsTemporaryString(const N: TTSNode): Boolean;
    /// <param name="N"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <param name="ACast"><!-- drag-lint:auto type -->out TTSNode</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: True; False.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.CheckPostFamily (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.FindTemporaryCast (DRagLint.V151.MEM.Support.pas)</para>
    /// <para>Calls: Default, DRagLint.V151.MEM.Support.TMemRun.FindTemporaryCast, DRagLint.V151.MEM.Support.TMemRun.IsPCharCast, DRagLint.V151.MEM.Support.TMemRun.IsTemporaryString, TreeSitter.TTSNodeHelper.NamedChild, TreeSitter.TTSNodeHelper.NamedChildCount</para>
    /// <para>Recursive</para>
    /// <para>Mutates: ACast (out)</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.IsPCharCast"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.IsTemporaryString"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.NamedChild"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.NamedChildCount"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallArgs"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindTemporaryCast(const N: TTSNode; out ACast: TTSNode): Boolean;
    /// <summary><!-- drag-lint:auto sum -->'lit' + X or X + 'lit' with exactly two
    /// operands: when X is empty the RTL returns the literal itself.</summary>
    /// <param name="N"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False; (L.NodeType =
    /// 'literalString') &lt;&gt; (R.NodeType = 'literalString').</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.LocalAssignedReadOnly (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.ReadOnlyCommandLine (DRagLint.V151.MEM.Support.pas)</para>
    /// <para>Calls: TreeSitter.TTSNodeHelper.ChildByField/1, TreeSitter.TTSNodeHelper.NodeType</para>
    /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.NodeType"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallArgs"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallName"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckAnsiApi"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsLiteralPlusOne(const N: TTSNode): Boolean;
    /// <summary><!-- drag-lint:auto sum -->AIdent names a by-value or const parameter of
    /// ARoutine declared string / UnicodeString / WideString.</summary>
    /// <param name="ARoutine"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <param name="AIdent"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False; (not ByRef) and
    /// IsUtf16String(LowerText(Arg.ChildByField('type'))).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.ReadOnlyCommandLine (DRagLint.V151.MEM.Support.pas)</para>
    /// <para>Calls: DRagLint.V151.MEM.Support.TMemRun.IsIdent, DRagLint.V151.MEM.Support.TMemRun.IsUtf16String, DRagLint.V151.MEM.Support.TMemRun.LowerText, DRagLint.V151.MEM.Support.TMemRun.NodeStr, LowerCase, MatchStr, TreeSitter.TTSNodeHelper.Child, TreeSitter.TTSNodeHelper.ChildByField/1, TreeSitter.TTSNodeHelper.ChildCount, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NamedChild, TreeSitter.TTSNodeHelper.NamedChildCount, TreeSitter.TTSNodeHelper.NodeType</para>
    /// <para>Complexity: 12 (cyclomatic, outer body), 29 lines (full implementation)</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.IsIdent"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.IsUtf16String"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.LowerText"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.NodeStr"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsValueStringParam(const ARoutine, AIdent: TTSNode): Boolean;
    /// <summary><!-- drag-lint:auto sum -->The last assignment to the local AIdent before
    /// ACall gives it a literal-backed value (literal, const, 'lit' + X) and no
    /// UniqueString(AIdent) runs between the two.</summary>
    /// <param name="ARoutine"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <param name="AIdent"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <param name="ACall"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.ReadOnlyCommandLine (DRagLint.V151.MEM.Support.pas)</para>
    /// <para>Calls: CallName, ContainsIdent, Default, DRagLint.V151.MEM.Support.TMemRun.IsIdent, DRagLint.V151.MEM.Support.TMemRun.IsLiteralPlusOne, DRagLint.V151.MEM.Support.TMemRun.LocalAssignedReadOnly.Scan, DRagLint.V151.MEM.Support.TMemRun.NodeStr, LowerCase, TreeSitter.TTSNodeHelper.ChildByField/1, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NodeType</para>
    /// <para>Reads: FConsts</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.IsIdent"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.IsLiteralPlusOne"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.LocalAssignedReadOnly.Scan"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.NodeStr"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function LocalAssignedReadOnly(const ARoutine, AIdent, ACall: TTSNode): Boolean;
    /// <param name="AArg"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <param name="ACall"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <param name="AWhy"><!-- drag-lint:auto type -->out string</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False; True; AWhy &lt;&gt;
    /// ''.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.CheckCreateProcess (DRagLint.V151.MEM.Support.pas)</para>
    /// <para>Calls: DRagLint.V151.MEM.Support.TMemRun.DeclTypeOf, DRagLint.V151.MEM.Support.TMemRun.EnclosingRoutine, DRagLint.V151.MEM.Support.TMemRun.IsIdent, DRagLint.V151.MEM.Support.TMemRun.IsLiteralPlusOne, DRagLint.V151.MEM.Support.TMemRun.IsPCharCast, DRagLint.V151.MEM.Support.TMemRun.IsUtf16String, DRagLint.V151.MEM.Support.TMemRun.IsValueStringParam, DRagLint.V151.MEM.Support.TMemRun.LocalAssignedReadOnly, DRagLint.V151.MEM.Support.TMemRun.NodeStr, Format, LowerCase, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NodeType</para>
    /// <para>Complexity: 12 (cyclomatic, outer body), 32 lines (full implementation)</para>
    /// <para>Reads: FConsts</para>
    /// <para>Mutates: AWhy (out)</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.DeclTypeOf"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.EnclosingRoutine"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.IsIdent"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.IsLiteralPlusOne"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.IsPCharCast"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ReadOnlyCommandLine(const AArg, ACall: TTSNode; out AWhy: string): Boolean;
    /// <param name="ARoutine"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <param name="ANames"><!-- drag-lint:auto type -->const array of string</param>
    /// <param name="ALowerVar"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: Found.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.CheckManagedRaw (DRagLint.V151.MEM.Support.pas)</para>
    /// <para>Calls: CallName, ContainsIdent, DRagLint.V151.MEM.Support.TMemRun.RoutineHasCallOn.Scan, MatchStr, TreeSitter.TTSNodeHelper.IsNull</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.RoutineHasCallOn.Scan"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.IsNull"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallArgs"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallName"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckAnsiApi"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function RoutineHasCallOn(const ARoutine: TTSNode; const ANames: array of string; const ALowerVar: string): Boolean;
    /// <summary><!-- drag-lint:auto sum -->Rules</summary>
    /// <param name="N"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.Visit (DRagLint.V151.MEM.Support.pas)</para>
    /// <para>Calls: DRagLint.V151.MEM.Support.TMemRun.EmitAt, DRagLint.V151.MEM.Support.TMemRun.IsPCharCast, DRagLint.V151.MEM.Support.TMemRun.IsTemporaryString, DRagLint.V151.MEM.Support.TMemRun.NodeStr, Format, TreeSitter.TTSNodeHelper.ChildByField/1, TreeSitter.TTSNodeHelper.IsNull</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.EmitAt"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.IsPCharCast"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.IsTemporaryString"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.NodeStr"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure CheckAssignment(const N: TTSNode);
    /// <param name="N"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.Visit (DRagLint.V151.MEM.Support.pas)</para>
    /// <para>Calls: DRagLint.V151.MEM.Support.TMemRun.CallName, DRagLint.V151.MEM.Support.TMemRun.CheckAnsiApi, DRagLint.V151.MEM.Support.TMemRun.CheckCharCount, DRagLint.V151.MEM.Support.TMemRun.CheckCreateProcess, DRagLint.V151.MEM.Support.TMemRun.CheckManagedRaw, DRagLint.V151.MEM.Support.TMemRun.CheckPostFamily, MatchStr, StartsStr</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallName"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckAnsiApi"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckCharCount"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckCreateProcess"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckManagedRaw"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure CheckCall(const N: TTSNode);
    /// <param name="N"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.CheckCall (DRagLint.V151.MEM.Support.pas)</para>
    /// <para>Calls: DRagLint.V151.MEM.Support.TMemRun.CallArgs, DRagLint.V151.MEM.Support.TMemRun.EmitAt, DRagLint.V151.MEM.Support.TMemRun.FindTemporaryCast</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallArgs"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.EmitAt"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.FindTemporaryCast"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallName"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckAnsiApi"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure CheckPostFamily(const N: TTSNode);
    /// <param name="N"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.CheckCall (DRagLint.V151.MEM.Support.pas)</para>
    /// <para>Calls: DRagLint.V151.MEM.Support.TMemRun.CallArgs, DRagLint.V151.MEM.Support.TMemRun.EmitAt, DRagLint.V151.MEM.Support.TMemRun.NodeStr, DRagLint.V151.MEM.Support.TMemRun.ReadOnlyCommandLine, Format, MatchStr, TreeSitter.TTSNodeHelper.ChildByField/1</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallArgs"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.EmitAt"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.NodeStr"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.ReadOnlyCommandLine"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure CheckCreateProcess(const N: TTSNode; const AName: string);
    /// <param name="N"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.CheckCall (DRagLint.V151.MEM.Support.pas)</para>
    /// <para>Calls: DRagLint.V151.MEM.Support.TMemRun.CallArgs, DRagLint.V151.MEM.Support.TMemRun.CallName, DRagLint.V151.MEM.Support.TMemRun.DeclTypeOf, DRagLint.V151.MEM.Support.TMemRun.EmitAt, DRagLint.V151.MEM.Support.TMemRun.EnclosingRoutine, DRagLint.V151.MEM.Support.TMemRun.IsIdent, DRagLint.V151.MEM.Support.TMemRun.IsLongString, DRagLint.V151.MEM.Support.TMemRun.IsManagedType, DRagLint.V151.MEM.Support.TMemRun.LowerText, DRagLint.V151.MEM.Support.TMemRun.NodeStr (+8 more)</para>
    /// <para>Complexity: 24 (cyclomatic, outer body), 60 lines (full implementation)</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallArgs"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallName"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.DeclTypeOf"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.EmitAt"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.EnclosingRoutine"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure CheckManagedRaw(const N: TTSNode; const AName: string);
    /// <param name="N"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.CheckCall (DRagLint.V151.MEM.Support.pas)</para>
    /// <para>Calls: DRagLint.V151.MEM.Support.TMemRun.CallArgs, DRagLint.V151.MEM.Support.TMemRun.CallName, DRagLint.V151.MEM.Support.TMemRun.ContainsIdent, DRagLint.V151.MEM.Support.TMemRun.DeclTypeOf, DRagLint.V151.MEM.Support.TMemRun.EmitAt, DRagLint.V151.MEM.Support.TMemRun.IsUtf16String, DRagLint.V151.MEM.Support.TMemRun.LowerText, DRagLint.V151.MEM.Support.TMemRun.NodeStr, Format, LowerCase, MatchStr, TreeSitter.TTSNodeHelper.ChildByField/1, TreeSitter.TTSNodeHelper.NodeType</para>
    /// <para>Complexity: 39 (cyclomatic, outer body), 86 lines (full implementation)</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallArgs"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallName"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.ContainsIdent"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.DeclTypeOf"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.EmitAt"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure CheckCharCount(const N: TTSNode; const AName: string);
    /// <param name="N"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.CheckCall (DRagLint.V151.MEM.Support.pas)</para>
    /// <para>Calls: CharInSet, DRagLint.V151.MEM.Support.TMemRun.CallArgs, DRagLint.V151.MEM.Support.TMemRun.CallName, DRagLint.V151.MEM.Support.TMemRun.DeclTypeOf, DRagLint.V151.MEM.Support.TMemRun.EmitAt, DRagLint.V151.MEM.Support.TMemRun.IsIdent, DRagLint.V151.MEM.Support.TMemRun.IsPCharCast, DRagLint.V151.MEM.Support.TMemRun.IsUtf16String, DRagLint.V151.MEM.Support.TMemRun.NodeStr, Format, MatchStr, TreeSitter.TTSNodeHelper.ChildByField/1, TreeSitter.TTSNodeHelper.NodeType</para>
    /// <para>Complexity: 12 (cyclomatic, outer body), 24 lines (full implementation)</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallArgs"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallName"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.DeclTypeOf"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.EmitAt"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.IsIdent"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure CheckAnsiApi(const N: TTSNode);
    /// <summary><!-- drag-lint:auto sum -->raw-memory-leak and handle-leak: a local that
    /// receives memory or a handle and is neither released nor handed on anywhere in the
    /// routine (nested routines included).</summary>
    /// <param name="ADef"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.Visit (DRagLint.V151.MEM.Support.pas)</para>
    /// <para>Calls: AddAlloc, AddAllocHandle, AssignTarget, CallArgs, CallName, CharInSet, ContainsStr, ContainsText, DeclTypeOf, DRagLint.V151.MEM.Support.TMemRun.CheckRoutineLeaks.CollectAllocs (+16 more)</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckRoutineLeaks.CollectAllocs"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckRoutineLeaks.CollectLocals"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckRoutineLeaks.Handled"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.EmitAt"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.NodeStr"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure CheckRoutineLeaks(const ADef: TTSNode);
    /// <param name="N"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.Support.TMemRun.Run (DRagLint.V151.MEM.Support.pas), DRagLint.V151.MEM.Support.TMemRun.Visit (DRagLint.V151.MEM.Support.pas)</para>
    /// <para>Calls: DRagLint.V151.MEM.Support.TMemRun.CheckAssignment, DRagLint.V151.MEM.Support.TMemRun.CheckCall, DRagLint.V151.MEM.Support.TMemRun.CheckRoutineLeaks, DRagLint.V151.MEM.Support.TMemRun.Visit, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NamedChild, TreeSitter.TTSNodeHelper.NamedChildCount, TreeSitter.TTSNodeHelper.NodeType</para>
    /// <para>Recursive</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckAssignment"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckCall"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckRoutineLeaks"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.IsNull"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.NamedChild"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure Visit(const N: TTSNode);
  public
    /// <summary>Prepares a run over one file.</summary>
    /// <param name="AFile">Path reported on every finding.</param>
    /// <param name="ASrc">The parsed source bytes (UTF-8); the tree's byte offsets index into it.</param>
    /// <param name="AStore">Project index, or nil.</param>
    /// <param name="ALib">Platform library index, or nil.</param>
    /// <param name="AWants">Answers whether a rule id is wanted in this run (--rule narrowing, OFF rules).</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.MEM.TV151MEMRules.CheckFile (DRagLint.V151.MEM.pas)</para>
    /// <para>constructor</para>
    /// <para>Writes: FFile, FSrc, FStore, FLib, FWants, FFindings, FTypeDecls, FConsts (+1 more)</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallArgs"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallName"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckAnsiApi"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckAssignment"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckCall"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create(const AFile: string; const ASrc: TBytes; const AStore, ALib: ISymbolStore;
      const AWants: TFunc<string, Boolean>);
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: FManagedCache, FConsts, FTypeDecls, FFindings</para>
    /// <para>Directives: override</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallArgs"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallName"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckAnsiApi"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckAssignment"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckCall"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    destructor Destroy; override;
    /// <summary>Walks the tree once and returns every finding of the lane's rules.</summary>
    /// <param name="ARoot">Root node of the file's parse tree.</param>
    /// <returns>Findings in tree order; empty when none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas) ?, DRagLint.V151.MEM.TV151MEMRules.CheckFile (DRagLint.V151.MEM.pas)</para>
    /// <para>Calls: DRagLint.V151.MEM.Support.TMemRun.CollectDecls, DRagLint.V151.MEM.Support.TMemRun.Visit</para>
    /// <para>Returns: FFindings.ToArray</para>
    /// <para>Reads: FFindings   Writes: FRoot</para>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CollectDecls"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.Visit"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallArgs"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CallName"/>
    /// <seealso cref="DRagLint.V151.MEM.Support.TMemRun.CheckAnsiApi"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Run(const ARoot: TTSNode): TArray<TLintFinding>;
  end;

implementation

uses
  DRagLint.Diagnostics.ParseCache { 1.52 BK-COLS2: TAstParseCache.CharCol }
  , System.StrUtils
  , DRagLint.Lint.QueryRules { DeclaredTypeAt }
  ;

const
  RULE_TEMP    = 'pchar-of-temporary';
  RULE_CPROC   = 'createprocess-readonly-commandline';
  RULE_MANAGED = 'managed-type-raw-memory';
  RULE_RAWLEAK = 'raw-memory-leak';
  RULE_HLEAK   = 'handle-leak';
  RULE_CHARS   = 'char-count-as-bytes';
  RULE_ANSI    = 'unsafe-string-api';
  SEV_WARNING  = 'warning';
  MAX_TYPE_DEPTH = 4;

  STRING_FUNCS: array[0..43] of string = (
    'inttostr', 'uinttostr', 'inttohex', 'floattostr', 'floattostrf', 'formatfloat', 'currtostr',
    'format', 'formatdatetime', 'datetostr', 'timetostr', 'datetimetostr', 'booltostr',
    'extractfilepath', 'extractfilename', 'extractfiledir', 'extractfileext', 'extractfiledrive',
    'changefileext', 'includetrailingpathdelimiter', 'includetrailingbackslash',
    'excludetrailingpathdelimiter', 'excludetrailingbackslash', 'expandfilename',
    'trim', 'trimleft', 'trimright', 'uppercase', 'lowercase', 'ansiuppercase', 'ansilowercase',
    'copy', 'stringreplace', 'quotedstr', 'ansiquotedstr', 'stringofchar', 'dupestring',
    'leftstr', 'rightstr', 'midstr', 'concat', 'getcurrentdir', 'guidtostring', 'reversestring');

  POST_FAMILY: array[0..5] of string = (
    'postmessage', 'postmessagew', 'postmessagea', 'postthreadmessage', 'postthreadmessagew',
    'postthreadmessagea');

  RAW_RELEASE: array[0..3] of string = ('freemem', 'freememory', 'dispose', 'strdispose');

  ESCAPE_PREFIXES: array[0..16] of string = (
    'add', 'insert', 'push', 'enqueue', 'put', 'store', 'register', 'attach', 'assign', 'set',
    'own', 'take', 'post', 'send', 'append', 'create', 'init');

  RELEASE_WORDS: array[0..5] of string = ('free', 'dispose', 'release', 'close', 'destroy', 'delete');

{ TMemRun: plumbing }

constructor TMemRun.Create(const AFile: string; const ASrc: TBytes; const AStore, ALib: ISymbolStore;
  const AWants: TFunc<string, Boolean>);
begin
  inherited Create;
  FFile        := AFile;
  FSrc         := ASrc;
  FStore       := AStore;
  FLib         := ALib;
  FWants       := AWants;
  FFindings    := TList<TLintFinding>.Create;
  FTypeDecls   := TDictionary<string, TTSNode>.Create;
  FConsts      := TDictionary<string, Boolean>.Create;
  FManagedCache:= TDictionary<string, Boolean>.Create;
end;

destructor TMemRun.Destroy;
begin
  FManagedCache.Free;
  FConsts.Free;
  FTypeDecls.Free;
  FFindings.Free;
  inherited Destroy;
end;

function TMemRun.NodeStr(const N: TTSNode): string;  // dl:ok duplicate-code@a733 -- REVIEWED 2026-11-14 v151 INT: same shape over different fields; a helper would need more parameters than it saves
var
  S, L: Integer;
begin
  Result:= '';
  if N.IsNull then Exit;
  S:= Integer(N.StartByte);
  L:= Integer(N.EndByte) - S;
  if (L <= 0) or (S < 0) or (S + L > Length(FSrc)) then Exit;
  Result:= TEncoding.UTF8.GetString(FSrc, S, L);
end;

function TMemRun.LowerText(const N: TTSNode): string;
var
  I: Integer;
  B: TStringBuilder;
  S: string;
begin
  S:= LowerCase(NodeStr(N));
  B:= TStringBuilder.Create(Length(S));
  try
    for I:= 1 to Length(S) do
      if not CharInSet(S[I], [' ', #9, #10, #13]) then
        B.Append(S[I]);
    Result:= B.ToString;
  finally
    B.Free;
  end;
end;

procedure TMemRun.EmitAt(const N: TTSNode; const ARule, AMsg, ASev: string);  // dl:ok duplicate-code@86f9 -- REVIEWED 2026-11-14 v151 INT: same shape over different fields; a helper would need more parameters than it saves
var
  P, Q: TTSPoint;
  F   : TLintFinding;
begin
  if not FWants(ARule) then Exit;
  P:= N.StartPoint;
  Q:= N.EndPoint;
  F:= Default(TLintFinding);
  F.RuleId   := ARule;
  F.Severity := ASev;
  F.Message  := AMsg;
  F.FilePath := FFile;
  F.StartLine:= Integer(P.Row) + 1;
  F.StartCol := TAstParseCache.CharCol(F.FilePath, P); { 1.52 BK-COLS2: character column }
  F.EndLine  := Integer(Q.Row) + 1;
  F.EndCol   := TAstParseCache.CharCol(F.FilePath, Q); { 1.52 BK-COLS2: character column }
  FFindings.Add(F);
end;

function TMemRun.IsIdent(const N: TTSNode): Boolean;
begin
  Result:= (not N.IsNull) and (N.NodeType = 'identifier');
end;

{ The callee's last name segment in lower case: Foo(..) -> foo, A.B.Foo(..) -> foo; '' when N is not a call. }
function TMemRun.CallName(const ACall: TTSNode): string;
var
  E: TTSNode;
begin
  Result:= '';
  if ACall.IsNull or (ACall.NodeType <> 'exprCall') then Exit;
  E:= ACall.ChildByField('entity');
  if E.IsNull then Exit;
  if E.NodeType = 'exprDot' then
    E:= E.ChildByField('rhs');
  if IsIdent(E) then
    Result:= LowerCase(NodeStr(E));
end;

function TMemRun.CallArgs(const ACall: TTSNode): TArray<TTSNode>;
var
  A: TTSNode;
  I: Integer;
begin
  Result:= nil;
  A:= ACall.ChildByField('args');
  if A.IsNull then Exit;
  for I:= 0 to A.NamedChildCount - 1 do
    if not A.NamedChild(I).IsExtra then
      Result:= Result + [A.NamedChild(I)];
end;

{ Declared type of an identifier at its position, lower case, no whitespace, no System. prefix. }
function TMemRun.DeclTypeOf(const AIdent: TTSNode; out AType: string): Boolean;
var
  T: string;
begin
  AType:= '';
  Result:= False;
  if not IsIdent(AIdent) then Exit;
  if not DeclaredTypeAt(FRoot, FSrc, AIdent.StartByte, NodeStr(AIdent), T) then Exit;
  T:= LowerCase(T);
  if StartsStr('system.', T) then
    Delete(T, 1, Length('system.'));
  AType:= T;
  Result:= T <> '';
end;

function TMemRun.IsUtf16String(const AType: string): Boolean;
begin
  Result:= MatchStr(AType, ['string', 'unicodestring', 'widestring']);
end;

function TMemRun.IsLongString(const AType: string): Boolean;
begin
  Result:= IsUtf16String(AType) or MatchStr(AType, ['ansistring', 'rawbytestring', 'utf8string']);
end;

{ Every type and const declaration of the file, any scope (a later one of the same name wins). }
procedure TMemRun.CollectDecls(const N: TTSNode);
var
  I : Integer;
  Nm: TTSNode;
begin
  if N.IsNull then Exit;
  if N.NodeType = 'declType' then
  begin
    Nm:= N.ChildByField('name');
    if IsIdent(Nm) then
      FTypeDecls.AddOrSetValue(LowerCase(NodeStr(Nm)), N);
  end
  else if N.NodeType = 'declConst' then
  begin
    Nm:= N.ChildByField('name');
    if IsIdent(Nm) then
      FConsts.AddOrSetValue(LowerCase(NodeStr(Nm)), True);
  end;
  for I:= 0 to N.NamedChildCount - 1 do
    CollectDecls(N.NamedChild(I));
end;

{ A type whose values hold a reference the compiler counts or finalizes: long strings, variants,
  interfaces, dynamic arrays, and records / static arrays that contain one. Unknown -> False. }
function TMemRun.IsManagedType(const AType: string; ADepth: Integer): Boolean;  // dl:ok too-many-exit-points@6d54 -- REVIEWED 2026-11-14 v151 MEM: recursive type classifier; each guard clause answers one type shape, the early exits are the readable form
var
  T: string;
  P: Integer;
  D: TTSNode;
begin
  Result:= False;
  T:= AType;
  if StartsStr('system.', T) then
    Delete(T, 1, Length('system.'));
  if (T = '') or (ADepth > MAX_TYPE_DEPTH) then Exit;
  if IsLongString(T) or MatchStr(T, ['variant', 'olevariant', 'iinterface', 'iunknown', 'idispatch',
    'tbytes', 'tstringdynarray', 'tintegerdynarray']) then
    Exit(True);
  if StartsStr('tarray<', T) or StartsStr('arrayof', T) then Exit(True);
  if StartsStr('string[', T) or StartsStr('^', T) then Exit(False);
  if StartsStr('array[', T) or StartsStr('packedarray[', T) then
  begin
    P:= Pos(']of', T);
    if P > 0 then
      Result:= IsManagedType(Copy(T, P + Length(']of'), MaxInt), ADepth + 1);
    Exit;
  end;
  if T.Contains('<') or T.Contains('(') then Exit;
  if FTypeDecls.TryGetValue(T, D) then
    Exit(IsManagedTypeNode(D, ADepth + 1));
  Result:= StoreTypeManaged(T, ADepth + 1);
end;

{ ADecl is a declType node of this file. }
function TMemRun.IsManagedTypeNode(const ADecl: TTSNode; ADepth: Integer): Boolean;  // dl:ok too-many-exit-points@8020 -- REVIEWED 2026-11-14 v151 MEM: recursive type classifier; each guard clause answers one type shape, the early exits are the readable form

  function FieldsManaged(const N: TTSNode): Boolean;
  var
    I : Integer;
    C : TTSNode;
  begin
    Result:= False;
    for I:= 0 to N.NamedChildCount - 1 do
    begin
      C:= N.NamedChild(I);
      if C.NodeType = 'declField' then
      begin
        if IsManagedType(LowerText(C.ChildByField('type')), ADepth + 1) then Exit(True);
      end
      else if MatchStr(C.NodeType, ['declVariant', 'declVariantClause', 'declSection']) and FieldsManaged(C) then
        Exit(True);
    end;
  end;

var
  T, Inner: TTSNode;
  I       : Integer;
  IsRec   : Boolean;
begin
  Result:= False;
  if ADepth > MAX_TYPE_DEPTH then Exit;
  T:= ADecl.ChildByField('type');
  if T.IsNull then Exit;
  if T.NodeType = 'declIntf' then Exit(True);
  if T.NodeType <> 'type' then Exit;
  if T.NamedChildCount <> 1 then Exit(IsManagedType(LowerText(T), ADepth));
  Inner:= T.NamedChild(0);
  if Inner.NodeType = 'declClass' then
  begin
    IsRec:= False;
    for I:= 0 to Inner.ChildCount - 1 do
      if Inner.Child(I).NodeType = 'kRecord' then
        IsRec:= True;
    if IsRec then
      Result:= FieldsManaged(Inner);
    Exit;
  end;
  Result:= IsManagedType(LowerText(T), ADepth);
end;

{ A type declared outside the file: ask the project index, then the library. Every row of the
  name must agree; a name the stores do not know, or know ambiguously, is not managed. }
function TMemRun.StoreTypeManaged(const AName: string; ADepth: Integer): Boolean;

  function Verdict(const AStore: ISymbolStore; out AKnown: Boolean): Boolean;
  var
    Rows, Kids: TArray<TSymbol>;
    S, K      : TSymbol;
    One, Seen : Boolean;
  begin
    Result:= False;
    AKnown:= False;
    if AStore = nil then Exit;
    Rows:= AStore.FindSymbolsByExactName(AName);
    Seen:= False;
    for S in Rows do
    begin
      if not (S.Kind in [skRecord, skInterface, skClass, skEnum, skTypeAlias]) then Continue; // dl:ok nonminimal-bool@ae29 -- a set test has no <> form
      case S.Kind of
        skInterface: One:= True;
        skRecord:
          begin
            One:= False;
            Kids:= AStore.FindAllChildSymbols(S.Id);
            for K in Kids do
              if (K.Kind = skField) and
                 IsManagedType(LowerCase(StringReplace(K.Signature, ' ', '', [rfReplaceAll])), ADepth + 1) then
              begin
                One:= True;
                Break;
              end;
          end;
        skTypeAlias: One:= IsManagedType(LowerCase(StringReplace(S.Signature, ' ', '', [rfReplaceAll])), ADepth + 1);
      else
        One:= False;
      end;
      if Seen and (One <> Result) then
      begin
        AKnown:= False;
        Exit(False);
      end;
      Seen:= True;
      Result:= One;
    end;
    AKnown:= Seen;
  end;

var
  Known: Boolean;
begin
  if FManagedCache.TryGetValue(AName, Result) then Exit;
  FManagedCache.AddOrSetValue(AName, False); // cycle guard
  Result:= Verdict(FStore, Known);
  if not Known then
    Result:= Verdict(FLib, Known);
  if not Known then
    Result:= False;
  FManagedCache.AddOrSetValue(AName, Result);
end;

{ ^T -> t; a pointer alias declared in the file (PFoo = ^TFoo) -> tfoo; anything else ''. }
function TMemRun.PointeeType(const AType: string): string;
var
  D: TTSNode;
  T: string;
begin
  Result:= '';
  if StartsStr('^', AType) then Exit(Copy(AType, 2, MaxInt));
  if FTypeDecls.TryGetValue(AType, D) then
  begin
    T:= LowerText(D.ChildByField('type'));
    if StartsStr('^', T) then
      Result:= Copy(T, 2, MaxInt);
  end;
end;

function TMemRun.EnclosingRoutine(const N: TTSNode): TTSNode;
begin
  Result:= N.Parent;
  while (not Result.IsNull) and (Result.NodeType <> 'defProc') do
    Result:= Result.Parent;
end;

function TMemRun.ContainsIdent(const N: TTSNode; const ALowerName: string): Boolean;
var
  I: Integer;
begin
  if N.IsNull then Exit(False);
  if IsIdent(N) then Exit(LowerCase(NodeStr(N)) = ALowerName);
  for I:= 0 to N.NamedChildCount - 1 do
    if ContainsIdent(N.NamedChild(I), ALowerName) then Exit(True);
  Result:= False;
end;

function TMemRun.ContainsStringLiteral(const N: TTSNode): Boolean;
var
  I: Integer;
begin
  if N.IsNull then Exit(False);
  if N.NodeType = 'literalString' then Exit(True);
  if N.NodeType <> 'exprBinary' then Exit(False);
  for I:= 0 to N.NamedChildCount - 1 do
    if ContainsStringLiteral(N.NamedChild(I)) then Exit(True);
  Result:= False;
end;

function TMemRun.IsPCharCast(const N: TTSNode; out AArg: TTSNode; AWideOnly: Boolean): Boolean;
var
  Nm  : string;
  Args: TArray<TTSNode>;
begin
  Result:= False;
  AArg:= Default(TTSNode);
  Nm:= CallName(N);
  if AWideOnly then
  begin
    if not MatchStr(Nm, ['pchar', 'pwidechar']) then Exit;
  end
  else if not MatchStr(Nm, ['pchar', 'pwidechar', 'pansichar']) then Exit;
  if N.ChildByField('entity').NodeType <> 'identifier' then Exit;
  Args:= CallArgs(N);
  if Length(Args) <> 1 then Exit;
  AArg:= Args[0];
  Result:= True;
end;

{ A string value with no variable behind it: a concatenation with a string literal or the
  result of a well-known string function. }
function TMemRun.IsTemporaryString(const N: TTSNode): Boolean;
begin
  if N.NodeType = 'exprBinary' then
    Exit((N.ChildByField('operator').NodeType = 'kAdd') and ContainsStringLiteral(N));
  Result:= (N.NodeType = 'exprCall') and MatchStr(CallName(N), STRING_FUNCS);
end;

function TMemRun.FindTemporaryCast(const N: TTSNode; out ACast: TTSNode): Boolean;
var
  A: TTSNode;
  I: Integer;
begin
  ACast:= Default(TTSNode);
  if IsPCharCast(N, A) and IsTemporaryString(A) then
  begin
    ACast:= N;
    Exit(True);
  end;
  for I:= 0 to N.NamedChildCount - 1 do
    if FindTemporaryCast(N.NamedChild(I), ACast) then Exit(True);
  Result:= False;
end;

{ 'lit' + X or X + 'lit' with exactly two operands: when X is empty the RTL returns the literal itself. }
function TMemRun.IsLiteralPlusOne(const N: TTSNode): Boolean;
var
  L, R: TTSNode;
begin
  Result:= False;
  if (N.NodeType <> 'exprBinary') or (N.ChildByField('operator').NodeType <> 'kAdd') then Exit;
  L:= N.ChildByField('lhs');
  R:= N.ChildByField('rhs');
  if (L.NodeType = 'exprBinary') or (R.NodeType = 'exprBinary') then Exit;
  Result:= (L.NodeType = 'literalString') <> (R.NodeType = 'literalString');
end;

{ AIdent names a by-value or const parameter of ARoutine declared string / UnicodeString / WideString. }
function TMemRun.IsValueStringParam(const ARoutine, AIdent: TTSNode): Boolean;
var
  Hdr, Args, Arg, C: TTSNode;
  I, J            : Integer;
  Name            : string;
  ByRef, Hit      : Boolean;
begin
  Result:= False;
  if ARoutine.IsNull then Exit;
  Hdr:= ARoutine.ChildByField('header');
  if Hdr.IsNull then Exit;
  Args:= Hdr.ChildByField('args');
  if Args.IsNull then Exit;
  Name:= LowerCase(NodeStr(AIdent));
  for I:= 0 to Args.NamedChildCount - 1 do
  begin
    Arg:= Args.NamedChild(I);
    if Arg.NodeType <> 'declArg' then Continue;
    ByRef:= False;
    Hit:= False;
    for J:= 0 to Arg.ChildCount - 1 do
    begin
      C:= Arg.Child(J);
      if MatchStr(C.NodeType, ['kVar', 'kOut']) then ByRef:= True;
      if IsIdent(C) and (LowerCase(NodeStr(C)) = Name) then Hit:= True;
    end;
    if Hit then
      Exit((not ByRef) and IsUtf16String(LowerText(Arg.ChildByField('type'))));
  end;
end;

{ The last assignment to the local AIdent before ACall gives it a literal-backed value
  (literal, const, 'lit' + X) and no UniqueString(AIdent) runs between the two. }
function TMemRun.LocalAssignedReadOnly(const ARoutine, AIdent, ACall: TTSNode): Boolean;
var
  Name    : string;
  LastRhs : TTSNode;
  LastEnd : UInt32;
  Uniq    : Boolean;

  procedure Scan(const N: TTSNode);
  var
    I: Integer;
    L: TTSNode;
  begin
    if N.StartByte >= ACall.StartByte then Exit;
    if N.NodeType = 'assignment' then
    begin
      L:= N.ChildByField('lhs');
      if IsIdent(L) and (LowerCase(NodeStr(L)) = Name) and (N.EndByte <= ACall.StartByte) then
      begin
        LastRhs:= N.ChildByField('rhs');
        LastEnd:= N.EndByte;
        Uniq:= False;
      end;
    end
    else if (N.NodeType = 'exprCall') and (CallName(N) = 'uniquestring') and
      (N.StartByte >= LastEnd) and ContainsIdent(N.ChildByField('args'), Name) then
      Uniq:= True;
    for I:= 0 to N.NamedChildCount - 1 do
      Scan(N.NamedChild(I));
  end;

begin
  Result:= False;
  Name:= LowerCase(NodeStr(AIdent));
  LastRhs:= Default(TTSNode);
  LastEnd:= 0;
  Uniq:= False;
  Scan(ARoutine.ChildByField('body'));
  if LastRhs.IsNull or Uniq then Exit;
  Result:= (LastRhs.NodeType = 'literalString') or IsLiteralPlusOne(LastRhs) or
    (IsIdent(LastRhs) and FConsts.ContainsKey(LowerCase(NodeStr(LastRhs))));
end;

function TMemRun.ReadOnlyCommandLine(const AArg, ACall: TTSNode; out AWhy: string): Boolean;
var
  X, R: TTSNode;
  T   : string;
begin
  Result:= False;
  AWhy:= '';
  if AArg.NodeType = 'literalString' then
  begin
    AWhy:= 'a string literal';
    Exit(True);
  end;
  if not IsPCharCast(AArg, X, True) then Exit;
  if X.NodeType = 'literalString' then
    AWhy:= 'a string literal'
  else if IsLiteralPlusOne(X) then
    AWhy:= 'a literal plus one value, which IS the literal when the value is empty'
  else if IsIdent(X) then
  begin
    R:= EnclosingRoutine(ACall);
    if DeclTypeOf(X, T) then
    begin
      if not IsUtf16String(T) then Exit;
      if IsValueStringParam(R, X) then
        AWhy:= Format('the string parameter ''%s'', which may be a literal at the call site', [NodeStr(X)])
      else if (not R.IsNull) and LocalAssignedReadOnly(R, X, ACall) then
        AWhy:= Format('''%s'', last assigned a literal-backed value without UniqueString', [NodeStr(X)]);
    end
    else if FConsts.ContainsKey(LowerCase(NodeStr(X))) then
      AWhy:= Format('the constant ''%s''', [NodeStr(X)]);
  end;
  Result:= AWhy <> '';
end;

function TMemRun.RoutineHasCallOn(const ARoutine: TTSNode; const ANames: array of string; const ALowerVar: string): Boolean;
var
  Found: Boolean;
  Names: TArray<string>;

  procedure Scan(const N: TTSNode);
  var
    I: Integer;
  begin
    if Found or N.IsNull then Exit;
    if (N.NodeType = 'exprCall') and MatchStr(CallName(N), Names) and ContainsIdent(N.ChildByField('args'), ALowerVar) then
    begin
      Found:= True;
      Exit;
    end;
    for I:= 0 to N.NamedChildCount - 1 do
      Scan(N.NamedChild(I));
  end;

var
  I: Integer;
begin
  Found:= False;
  SetLength(Names, Length(ANames));
  for I:= 0 to High(ANames) do
    Names[I]:= ANames[I];
  if not ARoutine.IsNull then
    Scan(ARoutine);
  Result:= Found;
end;

{ Rules }

procedure TMemRun.CheckAssignment(const N: TTSNode);
var
  Rhs, A: TTSNode;
begin
  Rhs:= N.ChildByField('rhs');
  if Rhs.IsNull then Exit;
  if IsPCharCast(Rhs, A) and IsTemporaryString(A) then
    EmitAt(Rhs, RULE_TEMP, Format('%s of a temporary string is stored in ''%s'': the temporary is released or ' +
      'reused before the pointer is read. Keep the string in a variable that lives as long as the pointer.',
      [NodeStr(Rhs.ChildByField('entity')), NodeStr(N.ChildByField('lhs'))]), SEV_WARNING);
end;

procedure TMemRun.CheckPostFamily(const N: TTSNode);
var
  A, Cast: TTSNode;
begin
  for A in CallArgs(N) do
    if FindTemporaryCast(A, Cast) then
      EmitAt(Cast, RULE_TEMP, 'PChar of a temporary string is posted: the message is handled after this ' +
        'statement, when the temporary is already gone. Post a copy the handler frees (StrNew) instead.', SEV_WARNING);
end;

procedure TMemRun.CheckCreateProcess(const N: TTSNode; const AName: string);
var
  Idx : Integer;
  Args: TArray<TTSNode>;
  Why : string;
begin
  if MatchStr(AName, ['createprocess', 'createprocessw']) then Idx:= 1
  else if MatchStr(AName, ['createprocessasuser', 'createprocessasuserw']) then Idx:= 2
  else if AName = 'createprocesswithtokenw' then Idx:= 3 // dl:ok magic-literal@4b49 -- Win32 API argument position / count
  else if AName = 'createprocesswithlogonw' then Idx:= 5 // dl:ok magic-literal@5fd8 -- Win32 API argument position / count
  else Exit;
  Args:= CallArgs(N);
  if Length(Args) <= Idx then Exit;
  if ReadOnlyCommandLine(Args[Idx], N, Why) then
    EmitAt(Args[Idx], RULE_CPROC, Format('%s writes into lpCommandLine, but this buffer may be read-only (%s): ' +
      'an access violation. Copy the command line into a local string, call UniqueString on it, pass PChar of it.',
      [NodeStr(N.ChildByField('entity')), Why]), SEV_WARNING);
end;

procedure TMemRun.CheckManagedRaw(const N: TTSNode; const AName: string);
var
  Args   : TArray<TTSNode>;
  Targets: TArray<Integer>;
  I      : Integer;
  A, V   : TTSNode;
  T, X   : string;
  IsMem  : Boolean;
  R      : TTSNode;
begin
  IsMem:= False;
  if MatchStr(AName, ['fillchar', 'zeromemory', 'fillmemory', 'securezeromemory']) then Targets:= [0]
  else if MatchStr(AName, ['move', 'copymemory', 'movememory']) then Targets:= [0, 1]
  else if MatchStr(AName, ['getmem', 'freemem', 'reallocmem']) then
  begin
    Targets:= [0];
    IsMem:= True;
  end
  else Exit;
  { TFile.Move, Stream.FillChar ...: a method of the same name is not the RTL routine }
  if N.ChildByField('entity').NodeType <> 'identifier' then Exit;
  Args:= CallArgs(N);
  R:= EnclosingRoutine(N);
  for I in Targets do
  begin
    if I >= Length(Args) then Continue;
    A:= Args[I];
    if IsMem then
    begin
      if not DeclTypeOf(A, T) then Continue;
      X:= PointeeType(T);
      V:= A;
    end
    else if IsIdent(A) then
    begin
      if not DeclTypeOf(A, T) then Continue;
      { the host wrong-size-memory-op already reports FillChar(V, SizeOf(V), ..) over a directly managed V }
      if (Length(Targets) = 1) and (Length(Args) > 1) and (CallName(Args[1]) = 'sizeof') and  // dl:ok boolean-expression-complexity@2e39 -- REVIEWED 2026-11-14 v151 MEM: one exemption shape (SetLength(X, SizeOf(X)) on a managed array/string) spelled as its three conditions
         (LowerText(Args[1].ChildByField('args')) = LowerText(A)) and
         (IsLongString(T) or StartsStr('tarray<', T) or (T = 'tbytes')) then Continue;
      X:= T;
      V:= A;
    end
    else if (A.NodeType = 'exprUnary') and MatchStr(A.ChildByField('operator').NodeType, ['kHat', 'kAt']) then
    begin
      V:= A.ChildByField('operand');
      if not DeclTypeOf(V, T) then Continue;
      X:= T;
      if A.ChildByField('operator').NodeType = 'kHat' then
        X:= PointeeType(T);
    end
    else Continue;
    if (X = '') or not IsManagedType(X, 0) then Continue;
    if RoutineHasCallOn(R, ['initialize', 'finalize'], LowerCase(NodeStr(V))) then Continue;
    EmitAt(N, RULE_MANAGED, Format('%s on ''%s'' of type %s, which holds strings, interfaces or dynamic arrays: ' +
      'the references are overwritten or dropped without reference counting (leak or double free). Use ' +
      'Default(T), assignment, New/Dispose or Initialize/Finalize instead.', [NodeStr(N.ChildByField('entity')), NodeStr(V), X]),
      SEV_WARNING);
    Exit;
  end;
end;

procedure TMemRun.CheckCharCount(const N: TTSNode; const AName: string);  // dl:ok too-many-exit-points@5d7e -- REVIEWED 2026-11-14 v151 MEM: one guard clause per non-defect shape of the char-count call  // dl:ok cyclomatic-complexity@a563 -- REVIEWED 2026-11-14 v151 MEM: the decision list IS the rule (API x argument x declared type); split helpers would each need the same call context  // dl:ok cyclomatic-complexity@83b9 -- REVIEWED 2026-11-14 v151 MEM: the decision list IS the rule (API x argument x declared type); split helpers would each need the same call context  // dl:ok cyclomatic-complexity@83b9 -- REVIEWED 2026-11-14 v151 MEM: the decision list IS the rule (API x argument x declared type); split helpers would each need the same call context
var
  Args     : TArray<TTSNode>;
  CountIdx : Integer;
  BufIdx   : TArray<Integer>;
  C, Inner, Op, L, R, S: TTSNode;
  IsMethod, Exact, Related: Boolean;
  Fn, T, SName: string;
  I        : Integer;
begin
  IsMethod:= N.ChildByField('entity').NodeType = 'exprDot';
  if IsMethod then
  begin
    if not MatchStr(AName, ['read', 'write', 'readbuffer', 'writebuffer']) then Exit;
    CountIdx:= 1;
    BufIdx:= [0];
  end
  else if MatchStr(AName, ['move', 'copymemory', 'movememory', 'comparemem']) then
  begin
    CountIdx:= 2;
    BufIdx:= [0, 1];
  end
  else if MatchStr(AName, ['fillchar', 'zeromemory']) then
  begin
    CountIdx:= 1;
    BufIdx:= [0];
  end
  else if MatchStr(AName, ['blockread', 'blockwrite', 'readfile', 'writefile']) then
  begin
    CountIdx:= 2;
    BufIdx:= [1];
  end
  else if MatchStr(AName, ['getmem', 'reallocmem']) then
  begin
    CountIdx:= 1;
    BufIdx:= [0];
  end
  else Exit;
  Args:= CallArgs(N);
  if Length(Args) <= CountIdx then Exit;
  C:= Args[CountIdx];
  Inner:= C;
  Exact:= True;
  if C.NodeType = 'exprBinary' then
  begin
    Op:= C.ChildByField('operator');
    if not MatchStr(Op.NodeType, ['kAdd', 'kSub']) then Exit;
    L:= C.ChildByField('lhs');
    R:= C.ChildByField('rhs');
    if R.NodeType = 'literalNumber' then Inner:= L
    else if (L.NodeType = 'literalNumber') and (Op.NodeType = 'kAdd') then Inner:= R
    else Exit;
    Exact:= False;
  end;
  Fn:= CallName(Inner);
  if not MatchStr(Fn, ['length', 'strlen']) then Exit;
  if Length(CallArgs(Inner)) <> 1 then Exit;
  S:= CallArgs(Inner)[0];
  if not DeclTypeOf(S, T) then Exit;
  if Fn = 'length' then
  begin
    if not IsUtf16String(T) then Exit;
  end
  else if not MatchStr(T, ['pchar', 'pwidechar']) then Exit;
  SName:= LowerCase(NodeStr(S));
  { the host wrong-size-memory-op already reports Move(S[i], .., Length(S)) and friends }
  if Exact and (Fn = 'length') then
  begin
    if (not IsMethod) and (AName = 'move') and (Args[0].NodeType = 'exprSubscript') and
       (LowerText(Args[0].ChildByField('entity')) = SName) then Exit;
    if MatchStr(AName, ['copymemory', 'movememory']) and (Args[1].NodeType = 'exprSubscript') and
       (LowerText(Args[1].ChildByField('entity')) = SName) then Exit;
    if IsMethod and MatchStr(AName, ['write', 'writebuffer']) and (Args[0].NodeType = 'exprSubscript') and
       (LowerText(Args[0].ChildByField('entity')) = SName) then Exit;
  end;
  Related:= False;
  if (not IsMethod) and MatchStr(AName, ['getmem', 'reallocmem']) then
    Related:= DeclTypeOf(Args[0], T) and MatchStr(T, ['pchar', 'pwidechar', '^char', '^widechar'])
  else
    for I in BufIdx do
      if (I < Length(Args)) and (I <> CountIdx) and ContainsIdent(Args[I], SName) then
        Related:= True;
  if not Related then Exit;
  EmitAt(C, RULE_CHARS, Format('%s counts characters, but %s takes a byte count: a string character is ' +
    'SizeOf(Char) = 2 bytes, so half the data is handled. Multiply by SizeOf(Char) (or use ByteLength).',
    [NodeStr(Inner), NodeStr(N.ChildByField('entity'))]), SEV_WARNING);
end;

procedure TMemRun.CheckAnsiApi(const N: TTSNode);
var
  E, X, Inner: TTSNode;
  Nm, T      : string;
  Args       : TArray<TTSNode>;
  A          : TTSNode;
begin
  E:= N.ChildByField('entity');
  if E.NodeType = 'exprDot' then E:= E.ChildByField('rhs');
  if not IsIdent(E) then Exit;
  Nm:= NodeStr(E);
  if (Length(Nm) < 3) or (Nm[Length(Nm)] <> 'A') or not CharInSet(Nm[Length(Nm) - 1], ['a'..'z', '0'..'9']) then Exit;  // dl:ok magic-literal@511d -- REVIEWED 2026-11-14 v151 MEM: shortest Ansi-suffixed API name: a letter, a lower-case/digit, the A suffix
  for A in CallArgs(N) do
  begin
    if not (IsPCharCast(A, X) and (CallName(A) = 'pansichar')) then Continue;
    if not MatchStr(CallName(X), ['ansistring', 'rawbytestring']) then Continue;
    Args:= CallArgs(X);
    if Length(Args) <> 1 then Continue;
    Inner:= Args[0];
    if not (DeclTypeOf(Inner, T) and IsUtf16String(T)) then Continue;
    EmitAt(A, RULE_ANSI, Format('%s is the Ansi version of the API and gets a Unicode string converted to the ' +
      'system code page: every character outside it becomes ''?''. Call the W version with PChar(%s).', [Nm, NodeStr(Inner)]),
      SEV_WARNING);
  end;
end;

procedure TMemRun.CheckCall(const N: TTSNode);
var
  Nm: string;
begin
  Nm:= CallName(N);
  if Nm = '' then Exit;
  if MatchStr(Nm, POST_FAMILY) then CheckPostFamily(N);
  if StartsStr('createprocess', Nm) then CheckCreateProcess(N, Nm);
  CheckManagedRaw(N, Nm);
  CheckCharCount(N, Nm);
  CheckAnsiApi(N);
end;

{ raw-memory-leak and handle-leak: a local that receives memory or a handle and is neither released
  nor handed on anywhere in the routine (nested routines included). }
procedure TMemRun.CheckRoutineLeaks(const ADef: TTSNode);
type
  TAlloc = record
    Site   : TTSNode;
    VarNode: TTSNode;
    Name   : string;    // lower
    Fn     : string;    // display name of the allocator
    Rule   : string;
    Release: string;    // display names of the releasers
  end;
var
  Locals : TDictionary<string, Boolean>;
  Allocs : TList<TAlloc>;
  HasAsm : Boolean;

  function ReleaseFor(const AFn: string; out ARelease: string): Boolean;
  begin
    Result:= True;
    ARelease:= '';
    if MatchStr(AFn, ['createfile', 'createfilew', 'createfilea', 'createevent', 'createeventw', 'createeventa',
      'createeventex', 'createmutex', 'createmutexw', 'createmutexa', 'createsemaphore', 'createsemaphorew',
      'createsemaphorea', 'createwaitabletimer', 'openprocess', 'openthread', 'openevent', 'openeventw',
      'openmutex', 'openmutexw', 'opensemaphore', 'createfilemapping', 'createfilemappingw', 'createfilemappinga',
      'openfilemapping', 'openfilemappingw', 'createtoolhelp32snapshot', 'createnamedpipe', 'createnamedpipew',
      'createjobobject', 'createjobobjectw', 'createthread']) then
      ARelease:= 'CloseHandle'
    else if MatchStr(AFn, ['findfirstfile', 'findfirstfilew', 'findfirstfilea', 'findfirstfileex', 'findfirstfileexw']) then
      ARelease:= 'FindClose'
    else if MatchStr(AFn, ['findfirstchangenotification', 'findfirstchangenotificationw']) then
      ARelease:= 'FindCloseChangeNotification'
    else if MatchStr(AFn, ['loadlibrary', 'loadlibraryw', 'loadlibrarya', 'loadlibraryex', 'loadlibraryexw',
      'safeloadlibrary']) then
      ARelease:= 'FreeLibrary'
    else if MatchStr(AFn, ['getdc', 'getwindowdc', 'getdcex']) then
      ARelease:= 'ReleaseDC'
    else if MatchStr(AFn, ['createcompatibledc', 'createdc', 'createdcw', 'createic']) then
      ARelease:= 'DeleteDC'
    else if MatchStr(AFn, ['createpen', 'createpenindirect', 'extcreatepen', 'createsolidbrush', 'createhatchbrush',
      'createbrushindirect', 'createpatternbrush', 'createfont', 'createfontw', 'createfontindirect',
      'createfontindirectw', 'createbitmap', 'createcompatiblebitmap', 'createdibsection', 'createdibitmap',
      'createrectrgn', 'createrectrgnindirect', 'createellipticrgn', 'createroundrectrgn', 'createpolygonrgn']) then
      ARelease:= 'DeleteObject'
    else if MatchStr(AFn, ['openscmanager', 'openscmanagerw', 'openservice', 'openservicew', 'createservice',
      'createservicew']) then
      ARelease:= 'CloseServiceHandle'
    else if MatchStr(AFn, ['getmem', 'new', 'allocmem', 'getmemory', 'stralloc', 'strnew', 'ansistralloc']) then
      ARelease:= 'FreeMem / Dispose / StrDispose'
    else
      Result:= False;
  end;

  procedure AddAlloc(const ASite, AVar: TTSNode; const AFnDisplay, ARule: string);
  var
    A: TAlloc;
    Rel: string;
  begin
    if not IsIdent(AVar) then Exit;
    if not Locals.ContainsKey(LowerCase(NodeStr(AVar))) then Exit;
    if not ReleaseFor(LowerCase(AFnDisplay), Rel) then Exit;
    A.Site:= ASite;
    A.VarNode:= AVar;
    A.Name:= LowerCase(NodeStr(AVar));
    A.Fn:= AFnDisplay;
    A.Rule:= ARule;
    A.Release:= Rel;
    Allocs.Add(A);
  end;

  { an allocator that fills a var parameter: RegOpenKeyEx(.., K), FindFirst(.., SR) }
  procedure AddAllocHandle(const ASite, AVar: TTSNode; const AFnDisplay, ARelease: string);
  var
    A: TAlloc;
    T: string;
  begin
    if not IsIdent(AVar) then Exit;
    if not Locals.ContainsKey(LowerCase(NodeStr(AVar))) then Exit;
    if SameText(AFnDisplay, 'FindFirst') and not (DeclTypeOf(AVar, T) and (T = 'tsearchrec')) then Exit;
    A.Site:= ASite;
    A.VarNode:= AVar;
    A.Name:= LowerCase(NodeStr(AVar));
    A.Fn:= AFnDisplay;
    A.Rule:= RULE_HLEAK;
    A.Release:= ARelease;
    Allocs.Add(A);
  end;

  { Cast(X): one argument, a pointer / handle / integer type name -> the value flows on unchanged. }
  function IsCastCall(const ACall: TTSNode): Boolean;
  var
    E: string;
  begin
    Result:= False;
    if ACall.ChildByField('entity').NodeType <> 'identifier' then Exit;
    if Length(CallArgs(ACall)) <> 1 then Exit;
    E:= NodeStr(ACall.ChildByField('entity'));
    if MatchStr(LowerCase(E), ['pointer', 'nativeint', 'nativeuint', 'integer', 'cardinal', 'lparam', 'wparam',
      'dword', 'uintptr', 'intptr', 'int64', 'uint64']) then Exit(True);
    Result:= (Length(E) >= 2) and CharInSet(E[1], ['P', 'T', 'H']) and CharInSet(E[2], ['A'..'Z']);
  end;

  procedure CollectLocals(const N: TTSNode; ATop: Boolean);
  var
    I: Integer;
    C: TTSNode;
  begin
    if N.IsNull then Exit;
    if (not ATop) and MatchStr(N.NodeType, ['defProc', 'lambda']) then Exit;
    if N.NodeType = 'declVar' then
    begin
      for I:= 0 to N.NamedChildCount - 1 do
      begin
        C:= N.NamedChild(I);
        if IsIdent(C) then Locals.AddOrSetValue(LowerCase(NodeStr(C)), True);
      end;
      Exit;
    end;
    if MatchStr(N.NodeType, ['varDef', 'varAssignDef']) then
      for I:= 0 to N.NamedChildCount - 1 do
      begin
        C:= N.NamedChild(I);
        if IsIdent(C) then Locals.AddOrSetValue(LowerCase(NodeStr(C)), True);
      end;
    if N.NodeType = 'asm' then HasAsm:= True;
    for I:= 0 to N.NamedChildCount - 1 do
      CollectLocals(N.NamedChild(I), False);
  end;

  function AssignTarget(const N: TTSNode): TTSNode;
  var
    I: Integer;
  begin
    Result:= N.ChildByField('lhs');
    if (not Result.IsNull) and (Result.NodeType = 'varAssignDef') then
      for I:= 0 to Result.NamedChildCount - 1 do
        if IsIdent(Result.NamedChild(I)) then
          Exit(Result.NamedChild(I));
  end;

  procedure CollectAllocs(const N: TTSNode; ATop: Boolean);
  var
    I   : Integer;
    Nm  : string;
    Args: TArray<TTSNode>;
    Rhs, Lhs: TTSNode;
    Disp: string;
  begin
    if N.IsNull then Exit;
    if (not ATop) and MatchStr(N.NodeType, ['defProc', 'lambda']) then Exit;
    if N.NodeType = 'assignment' then
    begin
      Rhs:= N.ChildByField('rhs');
      Lhs:= AssignTarget(N);
      Nm:= CallName(Rhs);
      if (Nm <> '') and (Rhs.ChildByField('entity').NodeType = 'identifier') then
      begin
        Disp:= NodeStr(Rhs.ChildByField('entity'));
        if MatchStr(Nm, ['allocmem', 'getmemory', 'stralloc', 'strnew', 'ansistralloc']) then
          AddAlloc(Rhs, Lhs, Disp, RULE_RAWLEAK)
        else if not MatchStr(Nm, ['getmem', 'new']) then
          AddAlloc(Rhs, Lhs, Disp, RULE_HLEAK);
      end;
    end
    else if N.NodeType = 'exprCall' then
    begin
      Nm:= CallName(N);
      Args:= CallArgs(N);
      if (N.ChildByField('entity').NodeType = 'identifier') and (Length(Args) > 0) then
      begin
        Disp:= NodeStr(N.ChildByField('entity'));
        if (Nm = 'getmem') or ((Nm = 'new') and (Length(Args) = 1)) then
          AddAlloc(N, Args[0], Disp, RULE_RAWLEAK)
        else if MatchStr(Nm, ['regopenkeyex', 'regopenkeyexw', 'regopenkeyexa']) and (Length(Args) = 5) then // dl:ok magic-literal@7ae6 -- Win32 API argument position / count
          AddAllocHandle(N, Args[4], Disp, 'RegCloseKey')
        else if MatchStr(Nm, ['regcreatekeyex', 'regcreatekeyexw', 'regcreatekeyexa']) and (Length(Args) = 9) then // dl:ok magic-literal@da5c -- Win32 API argument position / count
          AddAllocHandle(N, Args[7], Disp, 'RegCloseKey')
        else if MatchStr(Nm, ['regopenkey', 'regcreatekey']) and (Length(Args) = 3) then // dl:ok magic-literal@09e2 -- Win32 API argument position / count
          AddAllocHandle(N, Args[2], Disp, 'RegCloseKey')
        else if (Nm = 'findfirst') and (Length(Args) = 3) then // dl:ok magic-literal@0cca -- Win32 API argument position / count
          AddAllocHandle(N, Args[2], Disp, 'FindClose');
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do
      CollectAllocs(N.NamedChild(I), False);
  end;

  function IsReleaseCall(const ACallName: string; const AAlloc: TAlloc; const AArgs: TArray<TTSNode>): Boolean;
  var
    W: string;
  begin
    if AAlloc.Rule = RULE_RAWLEAK then
    begin
      if MatchStr(ACallName, RAW_RELEASE) then Exit(True);
      if (ACallName = 'reallocmem') and (Length(AArgs) = 2) and (LowerText(AArgs[1]) = '0') then Exit(True);
    end
    else if ContainsText(AAlloc.Release, ACallName) then
      Exit(True);
    for W in RELEASE_WORDS do
      if ContainsStr(ACallName, W) then Exit(True);
    Result:= False;
  end;

  { True when the occurrence O of the variable releases it or hands it on. }
  function ReleasedOrEscapes(const O: TTSNode; const AAlloc: TAlloc): Boolean;  // dl:ok too-many-exit-points@e3f3 -- REVIEWED 2026-11-14 v151 MEM: escape walker; each exit is one way the allocation is released or escapes, guard clauses read better than a flag
  var
    P, Child, Args: TTSNode;
    Nm, Pre: string;
  begin
    Result:= False;
    Child:= O;
    P:= O.Parent;
    while not P.IsNull do
    begin
      if MatchStr(P.NodeType, ['lambda']) then Exit(True);
      if (P.NodeType = 'exprUnary') then
      begin
        if P.ChildByField('operator').NodeType = 'kHat' then Exit(False);  { P^: a read of the pointee }
        if P.ChildByField('operator').NodeType = 'kAt' then Exit(True);   { @P: anyone may change it }
      end;
      if (P.NodeType = 'exprSubscript') and (P.ChildByField('entity').StartByte = Child.StartByte) then Exit(False);
      if (P.NodeType = 'exprDot') and (P.ChildByField('lhs').StartByte = Child.StartByte) then Exit(False);
      if P.NodeType = 'exprCall' then
      begin
        Args:= P.ChildByField('args');
        if (not Args.IsNull) and (Child.StartByte >= Args.StartByte) and (Child.EndByte <= Args.EndByte) then
        begin
          Nm:= CallName(P);
          if Nm = 'exit' then Exit(True);
          if IsReleaseCall(Nm, AAlloc, CallArgs(P)) then Exit(True);
          for Pre in ESCAPE_PREFIXES do
            if StartsStr(Pre, Nm) then Exit(True);
          { a cast passes the value on to its own parent; any other call only reads it }
          if not IsCastCall(P) then
            Exit(False);
        end;
      end;
      if P.NodeType = 'assignment' then
      begin
        { right-hand side: the value is copied somewhere -> handed on; left-hand side: overwritten }
        Exit(Child.StartByte >= P.ChildByField('rhs').StartByte);
      end;
      if MatchStr(P.NodeType, ['statement', 'block', 'if', 'defProc']) then Exit(False);
      Child:= P;
      P:= P.Parent;
    end;
  end;

  function Handled(const N: TTSNode; const AAlloc: TAlloc): Boolean;
  var
    I: Integer;
  begin
    if N.IsNull then Exit(False);
    if IsIdent(N) and (LowerCase(NodeStr(N)) = AAlloc.Name) and (N.StartByte <> AAlloc.VarNode.StartByte) and
       ReleasedOrEscapes(N, AAlloc) then Exit(True);
    for I:= 0 to N.NamedChildCount - 1 do
      if Handled(N.NamedChild(I), AAlloc) then Exit(True);
    Result:= False;
  end;

var
  A: TAlloc;
  Done: TDictionary<string, Boolean>;
begin
  Locals:= TDictionary<string, Boolean>.Create;
  Allocs:= TList<TAlloc>.Create;
  Done:= TDictionary<string, Boolean>.Create;
  try
    HasAsm:= False;
    CollectLocals(ADef, True);
    if HasAsm or (Locals.Count = 0) then Exit;
    CollectAllocs(ADef.ChildByField('body'), False);
    for A in Allocs do
    begin
      if Done.ContainsKey(A.Name) then Continue;
      Done.Add(A.Name, True);
      if Handled(ADef, A) then Continue;
      if A.Rule = RULE_RAWLEAK then
        EmitAt(A.Site, A.Rule, Format('''%s'' receives memory from %s, but this routine never releases it (%s) ' +
          'and never hands it on: a leak on every call. Release it in a try..finally.', [NodeStr(A.VarNode), A.Fn, A.Release]),
          SEV_WARNING)
      else
        EmitAt(A.Site, A.Rule, Format('''%s'' receives a handle from %s, but this routine never closes it (%s) ' +
          'and never hands it on: the handle leaks on every call. Close it in a try..finally.', [NodeStr(A.VarNode), A.Fn, A.Release]),
          SEV_WARNING);
    end;
  finally
    Done.Free;
    Allocs.Free;
    Locals.Free;
  end;
end;

procedure TMemRun.Visit(const N: TTSNode);
var
  I: Integer;
begin
  if N.IsNull then Exit;
  if N.NodeType = 'defProc' then
    CheckRoutineLeaks(N)
  else if N.NodeType = 'assignment' then
    CheckAssignment(N)
  else if N.NodeType = 'exprCall' then
    CheckCall(N);
  for I:= 0 to N.NamedChildCount - 1 do
    Visit(N.NamedChild(I));
end;

function TMemRun.Run(const ARoot: TTSNode): TArray<TLintFinding>;
begin
  FRoot:= ARoot;
  CollectDecls(ARoot);
  Visit(ARoot);
  Result:= FFindings.ToArray;
end;

end.
