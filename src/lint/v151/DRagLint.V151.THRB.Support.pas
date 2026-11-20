unit DRagLint.V151.THRB.Support;

{ Wave v151 lane THRB -- helpers of DRagLint.V151.THRB (private to the lane).
  One TThrbFile per linted unit: the parse tree, the class tree spelled in the
  file, the unit-level variables, the optional index reader and the findings
  list. The four rules of the lane live in DRagLint.V151.THRB and ask this
  object; nothing here decides a finding on its own. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , TreeSitter
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Lint.RefTypeRules
  ;

type
  /// <summary>Kind of anonymous-method context a lambda literal is passed to.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.THRB.pas), declaration (DRagLint.V151.THRB.Support.pas), DRagLint.V151.THRB.Support.ThrbLambdaKind (DRagLint.V151.THRB.Support.pas), DRagLint.V151.THRB.TThrbRun.CheckParallelBody (DRagLint.V151.THRB.pas), DRagLint.V151.THRB.TThrbRun.Execute (DRagLint.V151.THRB.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TThrbLambdaKind = (
    /// <summary>Not an argument of a known threading call.</summary>
    tlkNone,
    /// <summary>Body of TParallel.For: every iteration runs it, concurrently.</summary>
    tlkParallelFor,
    /// <summary>Body of TTask.Run / Create / Future or TThread.CreateAnonymousThread started inside a loop.</summary>
    tlkTaskInLoop,
    /// <summary>Body of TTask.Run / Create / Future or TThread.CreateAnonymousThread started once.</summary>
    tlkTask,
    /// <summary>Body of TThread.Synchronize / Queue / ForceQueue: runs serialised on the main thread.</summary>
    tlkMainThread);

  /// <summary>One parsed unit as the THRB rules see it.</summary>
  /// <remarks>
  /// Owns its node list, dictionaries, index reader and findings; the parse tree itself
  /// belongs to TAstParseCache. Not thread-safe (the lint pipeline is single-threaded).
  /// Every index question degrades to "unknown" without a store, so a run with no index answers
  /// by spelling alone.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.THRB.Support.pas) ?, DRagLint.V151.THRB.Support.CallName (DRagLint.V151.THRB.Support.pas) ?, DRagLint.V151.THRB.Support.ThrbLambdaKind (DRagLint.V151.THRB.Support.pas) ?, DRagLint.V151.THRB.Support.ThrbTakesLock (DRagLint.V151.THRB.Support.pas) ?, DRagLint.V151.THRB.TThrbRun.Create (DRagLint.V151.THRB.pas) (+5 more)</para>
  /// <para>Used in units: DRagLint.V151.THRB, DRagLint.V151.THRB.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TThrbFile = class
  strict private
    FPath     : string;
    FSrc      : TBytes;
    FRawSrc   : TBytes;
    FRoot     : TTSNode;
    FOk       : Boolean;
    FStore    : ISymbolStore;
    FLibStore : ISymbolStore;
    FFileId   : Int64;
    FReader   : TExprTypeReader;
    FNodes    : TList<TTSNode>;
    FParentOf : TDictionary<string, string>;
    FFieldsOf : TDictionary<string, TList<string>>;
    FGlobals  : TDictionary<string, Boolean>;
    FFindings : TList<TLintFinding>;
    /// <param name="ANode"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.THRB.Support.TThrbFile.Create (DRagLint.V151.THRB.Support.pas), DRagLint.V151.THRB.Support.TThrbFile.Flatten (DRagLint.V151.THRB.Support.pas)</para>
    /// <para>Calls: DRagLint.V151.THRB.Support.TThrbFile.Flatten, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NamedChild, TreeSitter.TTSNodeHelper.NamedChildCount</para>
    /// <para>Reads: FNodes</para>
    /// <para>Recursive</para>
    /// <seealso cref="TreeSitter.TTSNodeHelper.IsNull"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.NamedChild"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.NamedChildCount"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.AddFieldNames"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.Canon"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure Flatten(const ANode: TTSNode);
    /// <param name="ADeclField"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <param name="AFields"><!-- drag-lint:auto type -->const TList&lt;string&gt;</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.THRB.Support.TThrbFile.CollectClass (DRagLint.V151.THRB.Support.pas)</para>
    /// <para>Calls: DRagLint.V151.THRB.Support.TThrbFile.Canon, TreeSitter.TTSNodeHelper.NamedChild, TreeSitter.TTSNodeHelper.NamedChildCount, TreeSitter.TTSNodeHelper.NodeType</para>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.Canon"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.NamedChild"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.NamedChildCount"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.NodeType"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.CollectClass"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure AddFieldNames(const ADeclField: TTSNode; const AFields: TList<string>);
    /// <param name="ADeclType"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.THRB.Support.TThrbFile.Create (DRagLint.V151.THRB.Support.pas)</para>
    /// <para>Calls: Default, DRagLint.V151.THRB.Support.ThrbLeaf, DRagLint.V151.THRB.Support.TThrbFile.AddFieldNames, DRagLint.V151.THRB.Support.TThrbFile.Canon, TreeSitter.TTSNodeHelper.ChildByField/1, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NamedChild, TreeSitter.TTSNodeHelper.NamedChildCount, TreeSitter.TTSNodeHelper.NodeType</para>
    /// <para>Complexity: 14 (cyclomatic, outer body), 29 lines (full implementation)</para>
    /// <para>Reads: FParentOf, FFieldsOf</para>
    /// <seealso cref="DRagLint.V151.THRB.Support.ThrbLeaf"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.AddFieldNames"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.Canon"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.IsNull"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure CollectClass(const ADeclType: TTSNode);
    /// <param name="ADeclVars"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.THRB.Support.TThrbFile.Create (DRagLint.V151.THRB.Support.pas)</para>
    /// <para>Calls: DRagLint.V151.THRB.Support.TThrbFile.Canon, TreeSitter.TTSNodeHelper.Child, TreeSitter.TTSNodeHelper.ChildCount, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NamedChild, TreeSitter.TTSNodeHelper.NamedChildCount, TreeSitter.TTSNodeHelper.NodeType, TreeSitter.TTSNodeHelper.Parent</para>
    /// <para>Complexity: 15 (cyclomatic, outer body), 26 lines (full implementation)</para>
    /// <para>Reads: FGlobals</para>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.Canon"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.Child"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.ChildCount"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.IsNull"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.NamedChild"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure CollectGlobals(const ADeclVars: TTSNode);
    /// <param name="AClass"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ASuffixes"><!-- drag-lint:auto type -->const array of string</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.THRB.Support.TThrbFile.IsFormClass (DRagLint.V151.THRB.Support.pas), DRagLint.V151.THRB.Support.TThrbFile.IsThreadClass (DRagLint.V151.THRB.Support.pas)</para>
    /// <para>Calls: EndsText, StartsText</para>
    /// <para>Reads: FParentOf</para>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.AddFieldNames"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.Canon"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.CollectClass"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.CollectGlobals"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function SpelledAncestorEndsWith(const AClass: string; const ASuffixes: array of string): Boolean;
  public
    /// <summary>Parses APath through the shared parse cache and collects the file-level facts.</summary>
    /// <param name="APath">The .pas being linted.</param>
    /// <param name="AStore">Project index or nil.</param>
    /// <param name="AFileId">APath's id in AStore, or 0.</param>
    /// <param name="ALibStore">Library index or nil.</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.THRB.TThrbRun.Create (DRagLint.V151.THRB.pas)</para>
    /// <para>Calls: DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, DRagLint.V151.THRB.Support.TThrbFile.CollectClass, DRagLint.V151.THRB.Support.TThrbFile.CollectGlobals, DRagLint.V151.THRB.Support.TThrbFile.Flatten, TreeSitter.TTSNodeHelper.NodeType, TreeSitter.TTSTree.RootNode</para>
    /// <para>constructor</para>
    /// <para>Reads: FOk, FRawSrc, FSrc, FRoot, FNodes   Writes: FPath, FStore, FLibStore, FFileId, FNodes, FParentOf, FFieldsOf, FGlobals (+5 more)</para>
    /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.CollectClass"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.CollectGlobals"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.Flatten"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.NodeType"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create(const APath: string; const AStore: ISymbolStore; AFileId: Int64; const ALibStore: ISymbolStore);
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: FReader, FFindings, FGlobals, FFieldsOf, FParentOf, FNodes</para>
    /// <para>Directives: override</para>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.AddFieldNames"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.Canon"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.CollectClass"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.CollectGlobals"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    destructor Destroy; override;
    /// <summary>False when the file could not be parsed; every rule then reports nothing.</summary>
    property Ok: Boolean read FOk;
    /// <summary>Every named node of the file in document order.</summary>
    property Nodes: TList<TTSNode> read FNodes;
    /// <summary>The source text of a node, '' for a null node.</summary>
    /// <param name="ANode">Any node of this file.</param>
    /// <returns>The node's text as written.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.THRB.Support.TThrbFile.Canon (DRagLint.V151.THRB.Support.pas), DRagLint.V151.THRB.TThrbRun.CheckTask (DRagLint.V151.THRB.pas), DRagLint.V151.THRB.TThrbRun.WalkBlocking (DRagLint.V151.THRB.pas), DRagLint.V151.THRB.TThrbRun.WalkIncrements (DRagLint.V151.THRB.pas), DRagLint.V151.THRB.TThrbRun.WalkWrites (DRagLint.V151.THRB.pas)</para>
    /// <para>Calls: Integer, TreeSitter.TTSNodeHelper.EndByte, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.StartByte</para>
    /// <para>Returns: ''; TEncoding.UTF8.GetString(FSrc, S, E - S)</para>
    /// <para>Reads: FSrc</para>
    /// <seealso cref="TreeSitter.TTSNodeHelper.EndByte"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.IsNull"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.StartByte"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.AddFieldNames"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.Canon"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Text(const ANode: TTSNode): string;
    /// <summary>The node's text lower-cased, blanks and line breaks removed, a leading `self.`,
    /// any `&amp;` escape and a generic argument list `&lt;...&gt;` dropped.</summary>
    /// <param name="ANode">Any node of this file.</param>
    /// <returns>The canonical spelling used for every name comparison of the lane.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.THRB.Support.AddIdentChildren (DRagLint.V151.THRB.Support.pas), DRagLint.V151.THRB.Support.CallName (DRagLint.V151.THRB.Support.pas), DRagLint.V151.THRB.Support.TThrbFile.AddFieldNames (DRagLint.V151.THRB.Support.pas), DRagLint.V151.THRB.Support.TThrbFile.CollectClass (DRagLint.V151.THRB.Support.pas), DRagLint.V151.THRB.Support.TThrbFile.CollectGlobals (DRagLint.V151.THRB.Support.pas) (+12 more)</para>
    /// <para>Calls: Delete, DRagLint.V151.THRB.Support.TThrbFile.Text, LowerCase, StartsText</para>
    /// <para>Returns: SB.ToString</para>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.Text"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.AddFieldNames"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.CollectClass"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.CollectGlobals"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Canon(const ANode: TTSNode): string;
    /// <summary>True when the file's raw text contains ASub, case-insensitively.</summary>
    /// <param name="ASub">Lower-case text to look for.</param>
    /// <returns>Whether it occurs.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.THRB.TThrbRun.Execute (DRagLint.V151.THRB.pas)</para>
    /// <para>Calls: ContainsText</para>
    /// <para>Returns: ContainsText(TEncoding.UTF8.GetString(FRawSrc), ASub)</para>
    /// <para>Reads: FRawSrc</para>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.AddFieldNames"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.Canon"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.CollectClass"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.CollectGlobals"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function SourceContains(const ASub: string): Boolean;
    /// <summary>Whether AClass is a thread class: a spelled ancestor in this file named T*Thread,
    /// overruled by the index when it proves the opposite, or added when the index proves descent.</summary>
    /// <param name="AClass">Canonical class name.</param>
    /// <returns>True for a thread class.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.THRB.TThrbRun.Execute (DRagLint.V151.THRB.pas)</para>
    /// <para>Calls: DRagLint.Lint.RefTypeRules.TExprTypeReader.Create, DRagLint.Lint.RefTypeRules.TExprTypeReader.Descends, DRagLint.V151.THRB.Support.TThrbFile.SpelledAncestorEndsWith</para>
    /// <para>Returns: if SpelledAncestorEndsWith(AClass, ['thread']) then D &lt;&gt; tdNo</para>
    /// <para>Reads: FStore, FReader, FLibStore, FFileId, FSrc, FParentOf   Writes: FReader</para>
    /// <seealso cref="DRagLint.Lint.RefTypeRules.TExprTypeReader.Create"/>
    /// <seealso cref="DRagLint.Lint.RefTypeRules.TExprTypeReader.Descends"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.SpelledAncestorEndsWith"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.AddFieldNames"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.Canon"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsThreadClass(const AClass: string): Boolean;
    /// <summary>Whether AClass is a form or frame: a spelled ancestor ending in `form` or `frame`,
    /// or the index proves descent from TCustomForm / TCustomFrame. A data module does not count:
    /// server code creates them per worker thread.</summary>
    /// <param name="AClass">Canonical class name.</param>
    /// <returns>True for a form or frame class.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.THRB.TThrbRun.Execute (DRagLint.V151.THRB.pas)</para>
    /// <para>Calls: DRagLint.Lint.RefTypeRules.TExprTypeReader.Create, DRagLint.Lint.RefTypeRules.TExprTypeReader.Descends, DRagLint.V151.THRB.Support.TThrbFile.SpelledAncestorEndsWith</para>
    /// <para>Returns: if SpelledAncestorEndsWith(AClass, ['form', 'frame']) then (DForm &lt;&gt; tdNo) or (DFrame &lt;&gt; tdNo)</para>
    /// <para>Reads: FStore, FReader, FLibStore, FFileId, FSrc, FParentOf   Writes: FReader</para>
    /// <seealso cref="DRagLint.Lint.RefTypeRules.TExprTypeReader.Create"/>
    /// <seealso cref="DRagLint.Lint.RefTypeRules.TExprTypeReader.Descends"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.SpelledAncestorEndsWith"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.AddFieldNames"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.Canon"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsFormClass(const AClass: string): Boolean;
    /// <summary>Whether AName is a unit-level variable of this file (not a threadvar) or a class var
    /// of a class declared in it.</summary>
    /// <param name="AName">Canonical identifier.</param>
    /// <returns>True for shared, process-wide storage.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.THRB.TThrbRun.WalkIncrements (DRagLint.V151.THRB.pas)</para>
    /// <para>Returns: FGlobals.ContainsKey(AName)</para>
    /// <para>Reads: FGlobals</para>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.AddFieldNames"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.Canon"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.CollectClass"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.CollectGlobals"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsGlobal(const AName: string): Boolean;
    /// <summary>Whether AName is a field declared by AClass in this file.</summary>
    /// <param name="AClass">Canonical class name.</param>
    /// <param name="AName">Canonical identifier.</param>
    /// <returns>True when the class declares a field of that name.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.THRB.TThrbRun.WalkIncrements (DRagLint.V151.THRB.pas)</para>
    /// <para>Returns: FFieldsOf.TryGetValue(AClass, Fields) and (Fields.IndexOf(AName) &gt;= 0)</para>
    /// <para>Reads: FFieldsOf</para>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.AddFieldNames"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.Canon"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.CollectClass"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.CollectGlobals"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsFieldOf(const AClass, AName: string): Boolean;
    /// <summary>Adds one finding at ANode's start.</summary>
    /// <param name="ANode">Where the finding points.</param>
    /// <param name="ARule">Rule id.</param>
    /// <param name="AMsg">Message.</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.THRB.TThrbRun.CheckTask (DRagLint.V151.THRB.pas), DRagLint.V151.THRB.TThrbRun.WalkBlocking (DRagLint.V151.THRB.pas), DRagLint.V151.THRB.TThrbRun.WalkIncrements (DRagLint.V151.THRB.pas), DRagLint.V151.THRB.TThrbRun.WalkWrites (DRagLint.V151.THRB.pas)</para>
    /// <para>Calls: Default, DRagLint.Diagnostics.ParseCache.TAstParseCache.CharCol, Integer, TreeSitter.TTSNodeHelper.StartPoint</para>
    /// <para>Reads: FPath, FFindings</para>
    /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.CharCol"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.StartPoint"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.AddFieldNames"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.Canon"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.CollectClass"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure Emit(const ANode: TTSNode; const ARule, AMsg: string);
    /// <summary>The findings collected so far.</summary>
    /// <returns>A copy of the list; nil when empty.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.THRB.TV151THRBRules.CheckFile (DRagLint.V151.THRB.pas)</para>
    /// <para>Returns: if FFindings.Count = 0 then nil</para>
    /// <para>Reads: FFindings</para>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.AddFieldNames"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.Canon"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.CollectClass"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.CollectGlobals"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Findings: TArray<TLintFinding>;
  end;

/// <summary>Same node: same type and the same byte range.</summary>
/// <param name="A">First node.</param>
/// <param name="B">Second node.</param>
/// <returns>True when both denote the same syntax node.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.THRB.TThrbRun.InsideWith (DRagLint.V151.THRB.pas), DRagLint.V151.THRB.TThrbRun.LocalUsedAgain (DRagLint.V151.THRB.pas), DRagLint.V151.THRB.TThrbRun.TaskObserved (DRagLint.V151.THRB.pas)</para>
/// <para>Calls: TreeSitter.TTSNodeHelper.EndByte, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NodeType, TreeSitter.TTSNodeHelper.StartByte</para>
/// <para>Returns: (not A.IsNull) and (not B.IsNull) and (A.StartByte = B.StartByte) and (A.EndByte = B.EndByte)</para>
/// <seealso cref="TreeSitter.TTSNodeHelper.EndByte"/>
/// <seealso cref="TreeSitter.TTSNodeHelper.IsNull"/>
/// <seealso cref="TreeSitter.TTSNodeHelper.NodeType"/>
/// <seealso cref="TreeSitter.TTSNodeHelper.StartByte"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ThrbSameNode(const A, B: TTSNode): Boolean;

/// <summary>The part after the last dot of a canonical name (`ttask.run` -> `run`).</summary>
/// <param name="AName">Canonical name.</param>
/// <returns>The leaf; AName itself when it has no dot.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.THRB.Support.ThrbTakesLock (DRagLint.V151.THRB.Support.pas), DRagLint.V151.THRB.Support.TThrbFile.CollectClass (DRagLint.V151.THRB.Support.pas), DRagLint.V151.THRB.TThrbRun.CheckTask (DRagLint.V151.THRB.pas), DRagLint.V151.THRB.TThrbRun.RoutineBodyByName (DRagLint.V151.THRB.pas), DRagLint.V151.THRB.TThrbRun.TornDownInRoutine (DRagLint.V151.THRB.pas) (+1 more)</para>
/// <para>Calls: Copy, LastDelimiter</para>
/// <para>Returns: Copy(AName, LastDelimiter('.', AName) + 1, MaxInt)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ThrbLeaf(const AName: string): string;

/// <summary>The part before the last dot of a canonical name (`fthread.waitfor` -> `fthread`).</summary>
/// <param name="AName">Canonical name.</param>
/// <returns>The receiver; '' when AName has no dot.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.THRB.TThrbRun.TornDownInRoutine (DRagLint.V151.THRB.pas), DRagLint.V151.THRB.TThrbRun.WalkBlocking (DRagLint.V151.THRB.pas)</para>
/// <para>Calls: Copy, LastDelimiter</para>
/// <para>Returns: if K &gt; 0 then Copy(AName, 1, K - 1)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ThrbReceiver(const AName: string): string;

/// <summary>What a lambda literal is passed to, and whether that call sits inside a loop.</summary>
/// <param name="AFile">The file.</param>
/// <param name="ALambda">A `lambda` node.</param>
/// <param name="ACall">Out: the exprCall the lambda is an argument of (null node for tlkNone).</param>
/// <returns>The context kind; a task started from inside a for / while / repeat loop of the same
/// routine or lambda is tlkTaskInLoop.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.THRB.TThrbRun.Execute (DRagLint.V151.THRB.pas)</para>
/// <para>Calls: Default, DRagLint.V151.THRB.Support.InList, DRagLint.V151.THRB.Support.IsLoop, DRagLint.V151.THRB.Support.TThrbFile.Canon, TreeSitter.TTSNodeHelper.ChildByField/1, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NodeType, TreeSitter.TTSNodeHelper.Parent</para>
/// <para>Returns: tlkNone; tlkTask</para>
/// <para>Complexity: 12 (cyclomatic, outer body), 22 lines (full implementation)</para>
/// <para>Mutates: ACall (out)</para>
/// <seealso cref="DRagLint.V151.THRB.Support.InList"/>
/// <seealso cref="DRagLint.V151.THRB.Support.IsLoop"/>
/// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.Canon"/>
/// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
/// <seealso cref="TreeSitter.TTSNodeHelper.IsNull"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ThrbLambdaKind(const AFile: TThrbFile; const ALambda: TTSNode; out ACall: TTSNode): TThrbLambdaKind;

/// <summary>True when ANode holds a call that takes a lock (Enter, Acquire, BeginWrite, Lock,
/// LockList, TryEnter, TMonitor.Enter, EnterCriticalSection), outside nested routines.</summary>
/// <param name="AFile">The file.</param>
/// <param name="ANode">A routine or lambda body.</param>
/// <returns>Whether any lock is taken in it.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.THRB.Support.ThrbTakesLock (DRagLint.V151.THRB.Support.pas), DRagLint.V151.THRB.TThrbRun.CheckIncrements (DRagLint.V151.THRB.pas), DRagLint.V151.THRB.TThrbRun.CheckParallelBody (DRagLint.V151.THRB.pas)</para>
/// <para>Calls: DRagLint.V151.THRB.Support.CallName, DRagLint.V151.THRB.Support.InList, DRagLint.V151.THRB.Support.ThrbLeaf, DRagLint.V151.THRB.Support.ThrbTakesLock, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NamedChild, TreeSitter.TTSNodeHelper.NamedChildCount, TreeSitter.TTSNodeHelper.NodeType</para>
/// <para>Returns: False</para>
/// <para>Recursive</para>
/// <seealso cref="DRagLint.V151.THRB.Support.CallName"/>
/// <seealso cref="DRagLint.V151.THRB.Support.InList"/>
/// <seealso cref="DRagLint.V151.THRB.Support.ThrbLeaf"/>
/// <seealso cref="TreeSitter.TTSNodeHelper.IsNull"/>
/// <seealso cref="TreeSitter.TTSNodeHelper.NamedChild"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ThrbTakesLock(const AFile: TThrbFile; const ANode: TTSNode): Boolean;

/// <summary>True when a routine / lambda body has a try..except as a top-level statement (possibly
/// inside a nested begin..end, or inside a top-level loop), i.e. its exceptions are handled.</summary>
/// <param name="ABody">A `block` node; a null node is not guarded.</param>
/// <returns>Whether the body handles its own exceptions.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.THRB.Support.ThrbGuarded (DRagLint.V151.THRB.Support.pas), DRagLint.V151.THRB.TThrbRun.CheckTask (DRagLint.V151.THRB.pas), DRagLint.V151.THRB.TThrbRun.RoutineBodyByName (DRagLint.V151.THRB.pas)</para>
/// <para>Calls: DRagLint.V151.THRB.Support.ContainsTryExcept, DRagLint.V151.THRB.Support.HasExcept, DRagLint.V151.THRB.Support.IsLoop, DRagLint.V151.THRB.Support.ThrbGuarded, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NamedChild, TreeSitter.TTSNodeHelper.NamedChildCount, TreeSitter.TTSNodeHelper.NodeType</para>
/// <para>Returns: False; True</para>
/// <para>Recursive</para>
/// <seealso cref="DRagLint.V151.THRB.Support.ContainsTryExcept"/>
/// <seealso cref="DRagLint.V151.THRB.Support.HasExcept"/>
/// <seealso cref="DRagLint.V151.THRB.Support.IsLoop"/>
/// <seealso cref="TreeSitter.TTSNodeHelper.IsNull"/>
/// <seealso cref="TreeSitter.TTSNodeHelper.NamedChild"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ThrbGuarded(const ABody: TTSNode): Boolean;

/// <summary>Canonical names a routine or lambda declares: parameters, its var sections and inline
/// `var` declarations (incl. `for var`), not descending into nested lambdas or routines.</summary>
/// <param name="AFile">The file.</param>
/// <param name="AScope">A `defProc` or `lambda` node.</param>
/// <param name="ANames">List to append to; owned by the caller.</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.THRB.TThrbRun.CheckParallelBody (DRagLint.V151.THRB.pas), DRagLint.V151.THRB.TThrbRun.LocalUsedAgain (DRagLint.V151.THRB.pas), DRagLint.V151.THRB.TThrbRun.ShadowedLocally (DRagLint.V151.THRB.pas)</para>
/// <para>Calls: DRagLint.V151.THRB.Support.CollectDecls</para>
/// <seealso cref="DRagLint.V151.THRB.Support.CollectDecls"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure ThrbDeclaredNames(const AFile: TThrbFile; const AScope: TTSNode; const ANames: TList<string>);

/// <summary>The variable a statement writes in a read-modify-write or plain store: the plain
/// identifier on the left of `:=`, or the first argument of Inc / Dec / Include / Exclude /
/// SetLength / Delete.</summary>
/// <param name="AFile">The file.</param>
/// <param name="ANode">An `assignment` or `exprCall` node.</param>
/// <param name="AIsIncrement">Out: True for Inc / Dec and for `X := X + e`, `X := X - e`, `X := e + X`.</param>
/// <returns>The written identifier node, or a null node when ANode writes no plain identifier.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.THRB.TThrbRun.WalkIncrements (DRagLint.V151.THRB.pas), DRagLint.V151.THRB.TThrbRun.WalkWrites (DRagLint.V151.THRB.pas)</para>
/// <para>Calls: Default, DRagLint.V151.THRB.Support.InList, DRagLint.V151.THRB.Support.TThrbFile.Canon, TreeSitter.TTSNodeHelper.ChildByField/1, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NamedChild, TreeSitter.TTSNodeHelper.NamedChildCount, TreeSitter.TTSNodeHelper.NodeType</para>
/// <para>Returns: Default(TTSNode); Lhs; First</para>
/// <para>Complexity: 16 (cyclomatic, outer body), 31 lines (full implementation)</para>
/// <para>Mutates: AIsIncrement (out)</para>
/// <seealso cref="DRagLint.V151.THRB.Support.InList"/>
/// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.Canon"/>
/// <seealso cref="TreeSitter.TTSNodeHelper.ChildByField"/>
/// <seealso cref="TreeSitter.TTSNodeHelper.IsNull"/>
/// <seealso cref="TreeSitter.TTSNodeHelper.NamedChild"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ThrbWrittenName(const AFile: TThrbFile; const ANode: TTSNode; out AIsIncrement: Boolean): TTSNode;

implementation

uses
  System.StrUtils
  , DRagLint.Diagnostics.ParseCache
  ;

const
  MAX_ANCESTRY = 16;
  LOOP_NODES  : array[0..3] of string = ('for', 'foreach', 'while', 'repeat');
  TASK_CALLS  : array[0..3] of string = ('ttask.run', 'ttask.create', 'ttask.future', 'tthread.createanonymousthread');
  MAIN_CALLS  : array[0..5] of string = ('synchronize', 'queue', 'forcequeue', 'tthread.synchronize',
    'tthread.queue', 'tthread.forcequeue');
  LOCK_LEAVES : array[0..7] of string = ('enter', 'acquire', 'beginwrite', 'lock', 'locklist', 'tryenter',
    'entercriticalsection', 'tryacquire');
  WRITE_CALLS : array[0..5] of string = ('inc', 'dec', 'include', 'exclude', 'setlength', 'delete');

function InList(const AValue: string; const AList: array of string): Boolean;
begin
  Result:= False;
  for var I: Integer:= Low(AList) to High(AList) do
    if AValue = AList[I] then Exit(True);
end;

function ThrbSameNode(const A, B: TTSNode): Boolean;
begin
  Result:= (not A.IsNull) and (not B.IsNull) and (A.StartByte = B.StartByte) and (A.EndByte = B.EndByte)
    and (A.NodeType = B.NodeType);
end;

function ThrbLeaf(const AName: string): string;
begin
  Result:= Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

function ThrbReceiver(const AName: string): string;
var
  K: Integer;
begin
  K:= LastDelimiter('.', AName);
  Result:= if K > 0 then Copy(AName, 1, K - 1) else '';
end;

{ TThrbFile }

constructor TThrbFile.Create(const APath: string; const AStore: ISymbolStore; AFileId: Int64;
  const ALibStore: ISymbolStore);
var
  PF: TParsedFile;
begin
  inherited Create;
  FPath    := APath;
  FStore   := AStore;
  FLibStore:= ALibStore;
  FFileId  := AFileId;
  FNodes   := TList<TTSNode>.Create;
  FParentOf:= TDictionary<string, string>.Create;
  FFieldsOf:= TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  FGlobals := TDictionary<string, Boolean>.Create;
  FFindings:= TList<TLintFinding>.Create;
  PF:= TAstParseCache.Get(APath);
  FOk:= PF.Tree <> nil;
  if not FOk then Exit;
  FSrc   := PF.Src;
  FRawSrc:= PF.RawSrc;
  if Length(FRawSrc) = 0 then FRawSrc:= FSrc;
  FRoot:= PF.Tree.RootNode;
  Flatten(FRoot);
  for var N: TTSNode in FNodes do
    if N.NodeType = 'declType' then CollectClass(N)
    else if N.NodeType = 'declVars' then CollectGlobals(N);
end;

destructor TThrbFile.Destroy;
begin
  FReader.Free;
  FFindings.Free;
  FGlobals.Free;
  FFieldsOf.Free;
  FParentOf.Free;
  FNodes.Free;
  inherited;
end;

procedure TThrbFile.Flatten(const ANode: TTSNode);
begin
  if ANode.IsNull then Exit;
  FNodes.Add(ANode);
  for var I: Integer:= 0 to ANode.NamedChildCount - 1 do Flatten(ANode.NamedChild(I));
end;

function TThrbFile.Text(const ANode: TTSNode): string;
var
  S, E: Integer;
begin
  Result:= '';
  if ANode.IsNull then Exit;
  S:= Integer(ANode.StartByte);
  E:= Integer(ANode.EndByte);
  if (E <= S) or (S < 0) or (E > Length(FSrc)) then Exit;
  Result:= TEncoding.UTF8.GetString(FSrc, S, E - S);
end;

function TThrbFile.Canon(const ANode: TTSNode): string;
var
  SB   : TStringBuilder;
  Depth: Integer;
begin
  SB:= TStringBuilder.Create;
  try
    Depth:= 0;
    for var C: Char in LowerCase(Text(ANode)) do
      case C of
        '<': Inc(Depth);
        '>': if Depth > 0 then Dec(Depth);
        ' ', #9, #13, #10, '&': ; { blanks and the & escape are dropped on purpose }
      else
        if Depth = 0 then SB.Append(C);
      end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
  if StartsText('self.', Result) then Delete(Result, 1, Length('self.'));
end;

function TThrbFile.SourceContains(const ASub: string): Boolean;
begin
  Result:= ContainsText(TEncoding.UTF8.GetString(FRawSrc), ASub);
end;

procedure TThrbFile.CollectClass(const ADeclType: TTSNode);
var
  Cls, TypeN, ParentN: TTSNode;
  Name, Par          : string;
  Fields             : TList<string>;
begin
  Name := Canon(ADeclType.ChildByField('name'));
  TypeN:= ADeclType.ChildByField('type');
  Cls  := Default(TTSNode);
  for var I: Integer:= 0 to TypeN.NamedChildCount - 1 do
    if TypeN.NamedChild(I).NodeType = 'declClass' then Cls:= TypeN.NamedChild(I);
  if Cls.IsNull or (Name = '') then Exit;
  { The grammar puts field 'parent' on the parentheses too: take the first typeref child. }
  ParentN:= Default(TTSNode);
  for var I: Integer:= 0 to Cls.NamedChildCount - 1 do
    if ParentN.IsNull and (Cls.NamedChild(I).NodeType = 'typeref') then ParentN:= Cls.NamedChild(I);
  Par:= ThrbLeaf(Canon(ParentN));
  if Par <> '' then FParentOf.AddOrSetValue(Name, Par);
  Fields:= TList<string>.Create;
  FFieldsOf.AddOrSetValue(Name, Fields);
  for var I: Integer:= 0 to Cls.NamedChildCount - 1 do
  begin
    var Sect: TTSNode:= Cls.NamedChild(I);
    { fields before the first visibility keyword sit directly under the class node }
    if Sect.NodeType = 'declField' then AddFieldNames(Sect, Fields)
    else if Sect.NodeType = 'declSection' then
      for var J: Integer:= 0 to Sect.NamedChildCount - 1 do
        if Sect.NamedChild(J).NodeType = 'declField' then AddFieldNames(Sect.NamedChild(J), Fields);
  end;
end;

procedure TThrbFile.AddFieldNames(const ADeclField: TTSNode; const AFields: TList<string>);
begin
  for var K: Integer:= 0 to ADeclField.NamedChildCount - 1 do
    if ADeclField.NamedChild(K).NodeType = 'identifier' then AFields.Add(Canon(ADeclField.NamedChild(K)));
end;

procedure TThrbFile.CollectGlobals(const ADeclVars: TTSNode);
var
  Par     : TTSNode;
  IsClass : Boolean;
  IsThread: Boolean;
begin
  Par:= ADeclVars.Parent;
  if Par.IsNull then Exit;
  IsClass := False;
  IsThread:= False;
  for var I: Integer:= 0 to ADeclVars.ChildCount - 1 do
  begin
    if ADeclVars.Child(I).NodeType = 'kClass' then IsClass:= True;
    if ADeclVars.Child(I).NodeType = 'kThreadvar' then IsThread:= True;
  end;
  if IsThread then Exit;
  { unit level: directly under interface / implementation; a class var: in a class section. }
  if not ((Par.NodeType = 'interface') or (Par.NodeType = 'implementation')
    or (((Par.NodeType = 'declSection') or (Par.NodeType = 'declClass')) and IsClass)) then Exit;
  for var I: Integer:= 0 to ADeclVars.NamedChildCount - 1 do
  begin
    var V: TTSNode:= ADeclVars.NamedChild(I);
    if V.NodeType <> 'declVar' then Continue;
    for var K: Integer:= 0 to V.NamedChildCount - 1 do
      if V.NamedChild(K).NodeType = 'identifier' then FGlobals.AddOrSetValue(Canon(V.NamedChild(K)), True);
  end;
end;

function TThrbFile.SpelledAncestorEndsWith(const AClass: string; const ASuffixes: array of string): Boolean;
var
  Cur, Par: string;
begin
  Result:= False;
  Cur:= AClass;
  for var Depth: Integer:= 1 to MAX_ANCESTRY do
  begin
    if not FParentOf.TryGetValue(Cur, Par) then Exit;
    for var S: string in ASuffixes do
      if (Length(Par) > Length(S)) and StartsText('t', Par) and EndsText(S, Par) then Exit(True);
    Cur:= Par;
  end;
end;

function TThrbFile.IsThreadClass(const AClass: string): Boolean;
var
  D: TDescent;
begin
  D:= tdUnknown;
  if FStore <> nil then
  begin
    if FReader = nil then FReader:= TExprTypeReader.Create(FStore, FLibStore, FFileId, FSrc);
    if FReader.Ready then D:= FReader.Descends(AClass, 'tthread');
  end;
  Result:= if SpelledAncestorEndsWith(AClass, ['thread']) then D <> tdNo
    else FParentOf.ContainsKey(AClass) and (D = tdYes);
end;

function TThrbFile.IsFormClass(const AClass: string): Boolean;
var
  DForm, DFrame: TDescent;
begin
  DForm := tdUnknown;
  DFrame:= tdUnknown;
  if FStore <> nil then
  begin
    if FReader = nil then FReader:= TExprTypeReader.Create(FStore, FLibStore, FFileId, FSrc);
    if FReader.Ready then
    begin
      DForm := FReader.Descends(AClass, 'tcustomform');
      DFrame:= FReader.Descends(AClass, 'tcustomframe');
    end;
  end;
  Result:= if SpelledAncestorEndsWith(AClass, ['form', 'frame']) then (DForm <> tdNo) or (DFrame <> tdNo)
    else FParentOf.ContainsKey(AClass) and ((DForm = tdYes) or (DFrame = tdYes));
end;

function TThrbFile.IsGlobal(const AName: string): Boolean;
begin
  Result:= FGlobals.ContainsKey(AName);
end;

function TThrbFile.IsFieldOf(const AClass, AName: string): Boolean;
var
  Fields: TList<string>;
begin
  Result:= FFieldsOf.TryGetValue(AClass, Fields) and (Fields.IndexOf(AName) >= 0);
end;

procedure TThrbFile.Emit(const ANode: TTSNode; const ARule, AMsg: string);
var
  P: TTSPoint;
  F: TLintFinding;
begin
  P:= ANode.StartPoint;
  F:= Default(TLintFinding);
  F.RuleId   := ARule;
  F.Severity := 'warning';
  F.Message  := AMsg;
  F.FilePath := FPath;
  F.StartLine:= Integer(P.Row) + 1;
  F.StartCol := TAstParseCache.CharCol(F.FilePath, P); { 1.52 BK-COLS2: character column }
  F.EndLine  := F.StartLine;
  F.EndCol   := F.StartCol;
  FFindings.Add(F);
end;

function TThrbFile.Findings: TArray<TLintFinding>;
begin
  Result:= if FFindings.Count = 0 then nil else FFindings.ToArray;
end;

{ free helpers }

function IsLoop(const ANode: TTSNode): Boolean;
begin
  Result:= InList(ANode.NodeType, LOOP_NODES);
end;

function ThrbLambdaKind(const AFile: TThrbFile; const ALambda: TTSNode; out ACall: TTSNode): TThrbLambdaKind;  // dl:ok too-many-exit-points@d642 -- each early return IS the classification
var
  Args, Anc: TTSNode;
  Callee   : string;
begin
  Result:= tlkNone;
  ACall:= Default(TTSNode);
  Args:= ALambda.Parent;
  if Args.IsNull or (Args.NodeType <> 'exprArgs') then Exit;
  ACall:= Args.Parent;
  if ACall.IsNull or (ACall.NodeType <> 'exprCall') then Exit(tlkNone);
  Callee:= AFile.Canon(ACall.ChildByField('entity'));
  if Callee = 'tparallel.for' then Exit(tlkParallelFor);
  if InList(Callee, MAIN_CALLS) then Exit(tlkMainThread);
  if not InList(Callee, TASK_CALLS) then Exit(tlkNone);
  Result:= tlkTask;
  Anc:= ACall.Parent;
  while (not Anc.IsNull) and (Anc.NodeType <> 'defProc') and (Anc.NodeType <> 'lambda') do
  begin
    if IsLoop(Anc) then Exit(tlkTaskInLoop);
    Anc:= Anc.Parent;
  end;
end;

{ A call site: an exprCall, or a statement that is a bare name / dotted name (a call without parentheses). }
function CallName(const AFile: TThrbFile; const ANode: TTSNode): string;
var
  Par: TTSNode;
begin
  Result:= '';
  if ANode.NodeType = 'exprCall' then Exit(AFile.Canon(ANode.ChildByField('entity')));
  if (ANode.NodeType = 'exprDot') or (ANode.NodeType = 'identifier') then
  begin
    Par:= ANode.Parent;
    if (not Par.IsNull) and (Par.NodeType = 'statement') then Result:= AFile.Canon(ANode);
  end;
end;

function ThrbTakesLock(const AFile: TThrbFile; const ANode: TTSNode): Boolean;
var
  Name: string;
begin
  Result:= False;
  if ANode.IsNull or (ANode.NodeType = 'defProc') then Exit;
  Name:= CallName(AFile, ANode);
  if (Name <> '') and (InList(ThrbLeaf(Name), LOCK_LEAVES)) then Exit(True);
  for var I: Integer:= 0 to ANode.NamedChildCount - 1 do
    if ThrbTakesLock(AFile, ANode.NamedChild(I)) then Exit(True);
end;

function HasExcept(const ATry: TTSNode): Boolean;
begin
  Result:= False;
  for var I: Integer:= 0 to ATry.ChildCount - 1 do
    if ATry.Child(I).NodeType = 'kExcept' then Exit(True);
end;

function ContainsTryExcept(const ANode: TTSNode): Boolean;
begin
  Result:= False;
  if ANode.IsNull or (ANode.NodeType = 'lambda') or (ANode.NodeType = 'defProc') then Exit;
  if (ANode.NodeType = 'try') and HasExcept(ANode) then Exit(True);
  for var I: Integer:= 0 to ANode.NamedChildCount - 1 do
    if ContainsTryExcept(ANode.NamedChild(I)) then Exit(True);
end;

function ThrbGuarded(const ABody: TTSNode): Boolean;
begin
  Result:= False;
  if ABody.IsNull then Exit;
  for var I: Integer:= 0 to ABody.NamedChildCount - 1 do
  begin
    var Kid: TTSNode:= ABody.NamedChild(I);
    if (Kid.NodeType = 'try') and HasExcept(Kid) then Exit(True);
    if Kid.NodeType = 'block' then
    begin
      if ThrbGuarded(Kid) then Exit(True);
    end
    else if IsLoop(Kid) and ContainsTryExcept(Kid) then
      Exit(True);
  end;
end;

procedure AddIdentChildren(const AFile: TThrbFile; const ANode: TTSNode; const ANames: TList<string>);
begin
  for var I: Integer:= 0 to ANode.NamedChildCount - 1 do
    if ANode.NamedChild(I).NodeType = 'identifier' then ANames.Add(AFile.Canon(ANode.NamedChild(I)));
end;

procedure CollectDecls(const AFile: TThrbFile; const ANode: TTSNode; const ANames: TList<string>; ATop: Boolean);
var
  T: string;
begin
  if ANode.IsNull then Exit;
  T:= ANode.NodeType;
  if (not ATop) and ((T = 'lambda') or (T = 'defProc')) then Exit;
  if (T = 'declArg') or (T = 'declVar') or (T = 'varDef') or (T = 'varAssignDef') or (T = 'declConst') then
    AddIdentChildren(AFile, ANode, ANames);
  for var I: Integer:= 0 to ANode.NamedChildCount - 1 do
    CollectDecls(AFile, ANode.NamedChild(I), ANames, False);
end;

procedure ThrbDeclaredNames(const AFile: TThrbFile; const AScope: TTSNode; const ANames: TList<string>);
begin
  CollectDecls(AFile, AScope, ANames, True);
end;

function ThrbWrittenName(const AFile: TThrbFile; const ANode: TTSNode; out AIsIncrement: Boolean): TTSNode;  // dl:ok too-many-exit-points@ce43 -- guard clauses per statement shape; a nested if would hide the shapes
var
  Lhs, Rhs, Args, First: TTSNode;
  Name, Op, Callee     : string;
begin
  Result:= Default(TTSNode);
  AIsIncrement:= False;
  if ANode.NodeType = 'assignment' then
  begin
    Lhs:= ANode.ChildByField('lhs');
    if Lhs.IsNull or (Lhs.NodeType <> 'identifier') then Exit;
    Result:= Lhs;
    Rhs:= ANode.ChildByField('rhs');
    if (not Rhs.IsNull) and (Rhs.NodeType = 'exprBinary') then
    begin
      Name:= AFile.Canon(Lhs);
      Op  := AFile.Canon(Rhs.ChildByField('operator'));
      AIsIncrement:= ((Op = '+') or (Op = '-')) and (AFile.Canon(Rhs.ChildByField('lhs')) = Name)
        or ((Op = '+') and (AFile.Canon(Rhs.ChildByField('rhs')) = Name));
    end;
    Exit;
  end;
  if ANode.NodeType <> 'exprCall' then Exit;
  Callee:= AFile.Canon(ANode.ChildByField('entity'));
  if not InList(Callee, WRITE_CALLS) then Exit;
  Args:= ANode.ChildByField('args');
  if Args.IsNull or (Args.NamedChildCount = 0) then Exit;
  First:= Args.NamedChild(0);
  if First.NodeType <> 'identifier' then Exit;
  Result:= First;
  AIsIncrement:= (Callee = 'inc') or (Callee = 'dec');
end;

end.
