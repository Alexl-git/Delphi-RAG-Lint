unit DRagLint.V151.DFMA.Support;

{ Wave v151 lane DFMA -- helpers of DRagLint.V151.DFMA (private to the lane).
  Two small models the form rules share:
  * TDfmDoc  -- a text .dfm as a flat node list (object / inherited / inline /
    collection item) with EVERY property of each node, not only the navigation
    subset DRagLint.Parser.DfmNav keeps;
  * TPasUnit -- the parts of a .pas / .dpr the form rules read, taken from the
    shared tree-sitter parse (TAstParseCache): classes with their fields and
    method names, unit-level variables, uses clauses and routine bodies.
  Plus the lookups across files: the unit file of a unit name, the .dpr a unit
  belongs to and its Application.CreateForm order, and the ancestor chain of a
  class (this unit first, then the project index, then the library index). }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , TreeSitter
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.V151.Dfm.Common
  ;

type

  /// <summary>A text .dfm as a node list in file order; node 0 is the root.</summary>
  /// <remarks>
  /// Empty (no nodes) for a binary .dfm, an unreadable file or text that does not
  /// start with a node header -- every rule is silent then.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.DFMA.Support.pas) ?, DRagLint.V151.DFMA.CheckFieldsWithoutObject (DRagLint.V151.DFMA.pas) ?, DRagLint.V151.DFMA.RootClassIndex (DRagLint.V151.DFMA.pas) ?, DRagLint.V151.DFMA.Support.LoadDfm (DRagLint.V151.DFMA.Support.pas), DRagLint.V151.DFMA.Support.LoadDfmHead (DRagLint.V151.DFMA.Support.pas) ? (+9 more)</para>
  /// <para>Used in units: DRagLint.V151.DFMA, DRagLint.V151.DFMA.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDfmDoc = record
    Path : string;
    Nodes: TArray<TDfmNode>;
    /// <summary>True when the file gave no node.</summary>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: Length(Nodes) = 0.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.DFMA.CheckAccessBeforeCreate (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.RootClassIndex (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.Support.LoadDfmHead (DRagLint.V151.DFMA.Support.pas), DRagLint.V151.DFMA.Support.TDfmDoc.RootHasProp (DRagLint.V151.DFMA.Support.pas), DRagLint.V151.DFMA.Support.TDfmDoc.RootProp (DRagLint.V151.DFMA.Support.pas) (+1 more)</para>
    /// <para>Reads: Nodes</para>
    /// <para>Effect-free (proven)</para>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDfmDoc.HandlerNames"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDfmDoc.IndexOfName"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDfmDoc.RootHasProp"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDfmDoc.RootProp"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsEmpty: Boolean;
    /// <summary>Index of the first non-item node named AName (any case), -1 when none.</summary>
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Integer -- Observed: -1.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.DFMA.CheckDfmReferenceUnits (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.CheckFieldsWithoutObject (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.CheckFieldTypes (DRagLint.V151.DFMA.pas)</para>
    /// <para>Calls: SameText</para>
    /// <para>Reads: Nodes</para>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDfmDoc.HandlerNames"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDfmDoc.IsEmpty"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDfmDoc.RootHasProp"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDfmDoc.RootProp"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IndexOfName(const AName: string): Integer;
    /// <summary>Raw value of the root node's property AName, '' when absent.</summary>
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->string -- Observed: ''.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.DFMA.CheckAccessBeforeCreate (DRagLint.V151.DFMA.pas)</para>
    /// <para>Calls: DRagLint.V151.DFMA.Support.TDfmDoc.IsEmpty, SameText</para>
    /// <para>Reads: Nodes</para>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDfmDoc.IsEmpty"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDfmDoc.HandlerNames"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDfmDoc.IndexOfName"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDfmDoc.RootHasProp"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function RootProp(const AName: string): string;
    /// <summary>True when the root node sets AName.</summary>
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.DFMA.IsFormClass (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.Support.LoadDfmHead (DRagLint.V151.DFMA.Support.pas)</para>
    /// <para>Calls: DRagLint.V151.DFMA.Support.TDfmDoc.IsEmpty, SameText</para>
    /// <para>Reads: Nodes</para>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDfmDoc.IsEmpty"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDfmDoc.HandlerNames"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDfmDoc.IndexOfName"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDfmDoc.RootProp"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function RootHasProp(const AName: string): Boolean;
    /// <summary>Every handler name an `OnX = Name` line assigns, lower-cased, any node.</summary>
    /// <returns><!-- drag-lint:auto -->TArray&lt;string&gt; -- Observed: L.ToArray.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.DFMA.CheckSelfFree (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.Support.LoadDfmHead (DRagLint.V151.DFMA.Support.pas)</para>
    /// <para>Calls: DRagLint.V151.DFMA.Support.IsPascalIdent, DRagLint.V151.DFMA.Support.LastSegment, LowerCase, StartsText</para>
    /// <para>Reads: Nodes</para>
    /// <seealso cref="DRagLint.V151.DFMA.Support.IsPascalIdent"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.LastSegment"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDfmDoc.IndexOfName"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDfmDoc.IsEmpty"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDfmDoc.RootHasProp"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function HandlerNames: TArray<string>;
  end;

  /// <summary>One field of a class declaration.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.DFMA.Support.pas) ?, DRagLint.V151.DFMA.Support.TPasBuilder.AddClass (DRagLint.V151.DFMA.Support.pas) ?, DRagLint.V151.DFMA.Support.TPasBuilder.AddClass.AddMember (DRagLint.V151.DFMA.Support.pas)</para>
  /// <para>Used in units: DRagLint.V151.DFMA.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TPasField = record
    Name       : string;
    TypeName   : string;   // last dotted segment of the type reference
    IsPublished: Boolean;  // default section of the class or an explicit published section
    Line       : Integer;
    Col        : Integer;
  end;

  /// <summary>One class declaration (forward declarations are skipped).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.DFMA.Support.pas) ?, DRagLint.V151.DFMA.CheckObjectsWithoutField (DRagLint.V151.DFMA.pas) ?, DRagLint.V151.DFMA.CheckResourceMissing (DRagLint.V151.DFMA.pas) ?, DRagLint.V151.DFMA.Support.BuildPas (DRagLint.V151.DFMA.Support.pas) ?, DRagLint.V151.DFMA.Support.TPasBuilder.AddClass (DRagLint.V151.DFMA.Support.pas) (+4 more)</para>
  /// <para>Used in units: DRagLint.V151.DFMA, DRagLint.V151.DFMA.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TPasClass = record
    Name      : string;
    ParentName: string;   // first heritage entry, last dotted segment; '' = none
    Line      : Integer;
    Col       : Integer;
    Fields    : TArray<TPasField>;
    Methods   : TArray<string>;   // lower-case names of declared methods
    /// <summary><!-- drag-lint:auto sum -->---- TPasClass / TPasRoutine / TPasUnit ----</summary>
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Integer -- Observed: -1.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.DFMA.OwnClassHasField (DRagLint.V151.DFMA.pas)</para>
    /// <para>Calls: SameText</para>
    /// <para>Reads: Fields</para>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TPasClass.HasMethod"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FieldIndex(const AName: string): Integer;
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: ListHasName(Methods, AName).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.DFMA.CheckHandlerWithoutInherited (DRagLint.V151.DFMA.pas)</para>
    /// <para>Calls: DRagLint.V151.DFMA.Support.ListHasName</para>
    /// <para>Reads: Methods</para>
    /// <seealso cref="DRagLint.V151.DFMA.Support.ListHasName"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TPasClass.FieldIndex"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function HasMethod(const AName: string): Boolean;
  end;

  /// <summary>One unit-level variable.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.DFMA.Support.pas) ?, DRagLint.V151.DFMA.Support.BuildPas (DRagLint.V151.DFMA.Support.pas) ?, DRagLint.V151.DFMA.Support.TPasBuilder.AddVars (DRagLint.V151.DFMA.Support.pas)</para>
  /// <para>Used in units: DRagLint.V151.DFMA.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TPasVar = record
    Name       : string;
    TypeName   : string;
    InInterface: Boolean;
    Line       : Integer;
  end;

  /// <summary>One routine implementation (defProc).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.DFMA.Support.pas) ?, DRagLint.V151.DFMA.OwnClassHasField (DRagLint.V151.DFMA.pas) ?, DRagLint.V151.DFMA.RoutineGuards (DRagLint.V151.DFMA.pas) ?, DRagLint.V151.DFMA.Support.BuildPas (DRagLint.V151.DFMA.Support.pas) ?, DRagLint.V151.DFMA.Support.TPasBuilder.AddRoutine (DRagLint.V151.DFMA.Support.pas) (+3 more)</para>
  /// <para>Used in units: DRagLint.V151.DFMA, DRagLint.V151.DFMA.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TPasRoutine = record
    OwnerClass: string;   // 'TForm1' of TForm1.Foo; '' for a plain routine
    Name      : string;
    IsCtor    : Boolean;
    Line      : Integer;
    Col       : Integer;
    Body      : TTSNode;  // the block; IsNull for a forward / external declaration
    SenderObj : Boolean;  // has a parameter `Sender: TObject`
    Locals    : TArray<string>;  // lower-case parameter and local variable names
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: ListHasName(Locals, AName).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.DFMA.CheckAccessBeforeCreate (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.CheckAutocreateAndManual (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.CheckForeignFormAccess (DRagLint.V151.DFMA.pas)</para>
    /// <para>Calls: DRagLint.V151.DFMA.Support.ListHasName</para>
    /// <para>Reads: Locals</para>
    /// <seealso cref="DRagLint.V151.DFMA.Support.ListHasName"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function HasLocal(const AName: string): Boolean;
  end;

  /// <summary>What the form rules read from one parsed .pas or .dpr.</summary>
  /// <remarks>
  /// The nodes point into the shared TAstParseCache tree and are valid until
  /// that cache is cleared; use a TPasUnit within one check only.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.DFMA.Support.pas) ?, DRagLint.V151.DFMA.Support.BuildPas (DRagLint.V151.DFMA.Support.pas), DRagLint.V151.DFMA.Support.DeclNames (DRagLint.V151.DFMA.Support.pas) ?, DRagLint.V151.DFMA.Support.LoadPas (DRagLint.V151.DFMA.Support.pas), DRagLint.V151.DFMA.Support.LoadPasSummary (DRagLint.V151.DFMA.Support.pas) (+26 more)</para>
  /// <para>Used in units: DRagLint.V151.DFMA, DRagLint.V151.DFMA.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TPasUnit = record
    Ok       : Boolean;
    Path     : string;
    UnitName : string;
    Src      : TBytes;
    RawSrc   : TBytes;
    Classes  : TArray<TPasClass>;
    Vars     : TArray<TPasVar>;
    Routines : TArray<TPasRoutine>;
    IntfUses : TArray<string>;
    ImplUses : TArray<string>;
    ImplLine : Integer;
    /// <summary>Text of a node of this unit's parse.</summary>
    /// <param name="N"><!-- drag-lint:auto type -->const TTSNode</param>
    /// <returns><!-- drag-lint:auto -->string -- Observed: '';
    /// TEncoding.UTF8.GetString(Src, S, L).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.DFMA.AssignedNames (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.CheckAccessBeforeCreate (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.CheckAutocreateAndManual (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.CheckForeignFormAccess (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.CreateCallClass (DRagLint.V151.DFMA.pas) (+9 more)</para>
    /// <para>Calls: Integer, TreeSitter.TTSNodeHelper.EndByte, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.StartByte</para>
    /// <para>Reads: Src</para>
    /// <seealso cref="TreeSitter.TTSNodeHelper.EndByte"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.IsNull"/>
    /// <seealso cref="TreeSitter.TTSNodeHelper.StartByte"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TPasUnit.ClassIndex"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TPasUnit.UsesUnit"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Text(const N: TTSNode): string;
    /// <summary>Index of the class named AName (any case), -1 when none.</summary>
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Integer -- Observed: -1.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.DFMA.AncestorHandlers (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.CheckAccessBeforeCreate (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.CheckObjectsWithoutField (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.ForeignFormsOf (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.OwnClassHasField (DRagLint.V151.DFMA.pas) (+3 more)</para>
    /// <para>Calls: SameText</para>
    /// <para>Reads: Classes</para>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TPasUnit.Text"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TPasUnit.UsesUnit"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TPasUnit.VarIndex"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ClassIndex(const AName: string): Integer;
    /// <summary>Index of the unit-level variable named AName, -1 when none.</summary>
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Integer -- Observed: -1.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.DFMA.CheckForeignFormAccess (DRagLint.V151.DFMA.pas)</para>
    /// <para>Calls: SameText</para>
    /// <para>Reads: Vars</para>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TPasUnit.ClassIndex"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TPasUnit.Text"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TPasUnit.UsesUnit"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function VarIndex(const AName: string): Integer;
    /// <summary>True when AUnit is in the interface or implementation uses clause.</summary>
    /// <param name="AUnit"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.DFMA.CheckDfmReferenceUnits (DRagLint.V151.DFMA.pas)</para>
    /// <para>Calls: DRagLint.V151.DFMA.Support.LastSegment, SameText</para>
    /// <para>Reads: IntfUses, ImplUses</para>
    /// <seealso cref="DRagLint.V151.DFMA.Support.LastSegment"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TPasUnit.ClassIndex"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TPasUnit.Text"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TPasUnit.VarIndex"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function UsesUnit(const AUnit: string): Boolean;
  end;

  /// <summary>One `Application.CreateForm(TClass, Var)` call of a .dpr, in call order.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.DFMA.Support.pas), DRagLint.V151.DFMA.Support.DprScan (DRagLint.V151.DFMA.Support.pas)</para>
  /// <para>Used in units: DRagLint.V151.DFMA.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDprCreate = record
    ClassName: string;
    VarName  : string;
  end;

  /// <summary>What the form rules read from a .dpr.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.DFMA.Support.pas) ?, DRagLint.V151.DFMA.Support.DprScan (DRagLint.V151.DFMA.Support.pas), DRagLint.V151.DFMA.Support.FindDprFor (DRagLint.V151.DFMA.Support.pas), DRagLint.V151.DFMA.Support.initialization (DRagLint.V151.DFMA.Support.pas) ?, DRagLint.V151.DFMA.Support.LoadDpr (DRagLint.V151.DFMA.Support.pas) (+5 more)</para>
  /// <para>Used in units: DRagLint.V151.DFMA, DRagLint.V151.DFMA.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDprInfo = record
    Path    : string;
    Units   : TArray<string>;      // lower-case unit names of the uses clause
    Modules : TArray<string>;      // lower-case 'module=unit' pairs from `U in 'U.pas' {Module}`
    Creates : TArray<TDprCreate>;  // in call order
    /// <param name="AUnit"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: ListHasName(Units, AUnit) or
    /// ListHasName(Units, LastSegment(AUnit)).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.DFMA.Support.FindDprFor (DRagLint.V151.DFMA.Support.pas)</para>
    /// <para>Calls: DRagLint.V151.DFMA.Support.LastSegment, DRagLint.V151.DFMA.Support.ListHasName</para>
    /// <para>Reads: Units</para>
    /// <seealso cref="DRagLint.V151.DFMA.Support.LastSegment"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.ListHasName"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDprInfo.CreateIndexOfClass"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDprInfo.CreateIndexOfVar"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDprInfo.UnitOfModule"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function HasUnit(const AUnit: string): Boolean;
    /// <param name="AClass"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Integer -- Observed: -1.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Calls: SameText</para>
    /// <para>Reads: Creates</para>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDprInfo.CreateIndexOfVar"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDprInfo.HasUnit"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDprInfo.UnitOfModule"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function CreateIndexOfClass(const AClass: string): Integer;
    /// <param name="AVar"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Integer -- Observed: -1.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.DFMA.CheckAccessBeforeCreate (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.CheckAutocreateAndManual (DRagLint.V151.DFMA.pas)</para>
    /// <para>Calls: SameText</para>
    /// <para>Reads: Creates</para>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDprInfo.CreateIndexOfClass"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDprInfo.HasUnit"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDprInfo.UnitOfModule"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function CreateIndexOfVar(const AVar: string): Integer;
    /// <param name="AModule"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->string -- Observed: ''.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.DFMA.UnitOfModule (DRagLint.V151.DFMA.pas)</para>
    /// <para>Calls: Copy, LowerCase, StartsText</para>
    /// <para>Reads: Modules</para>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDprInfo.CreateIndexOfClass"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDprInfo.CreateIndexOfVar"/>
    /// <seealso cref="DRagLint.V151.DFMA.Support.TDprInfo.HasUnit"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function UnitOfModule(const AModule: string): string;
  end;

/// <summary>Reads a text .dfm into a node list.</summary>
/// <param name="APath">The .dfm; '' or a missing file gives an empty doc.</param>
/// <returns>The doc; empty for a binary or unreadable form file.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.DFMA.CheckAccessBeforeCreate (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.Support.LoadDfmHead (DRagLint.V151.DFMA.Support.pas), DRagLint.V151.DFMA.TV151DFMARules.CheckDfm (DRagLint.V151.DFMA.pas)</para>
/// <para>Calls: CharInSet, CompareMem, Copy, Default, DRagLint.Parser.DfmNav.DfmNavLinesFromBytes, FileExists, LowerCase, Pos, SameText, StartsText, Trim</para>
/// <para>Returns: Default(TDfmDoc)</para>
/// <para>Complexity: 41 (cyclomatic, outer body), 126 lines (full implementation)</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Parser.DfmNav.DfmNavLinesFromBytes"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function LoadDfm(const APath: string): TDfmDoc;

/// <summary>Builds the TPasUnit of a .pas / .dpr from the shared parse cache.</summary>
/// <param name="APath">The source file.</param>
/// <returns>Ok = False when the file cannot be parsed.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.DFMA.TV151DFMARules.CheckDfm (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.TV151DFMARules.CheckFile (DRagLint.V151.DFMA.pas)</para>
/// <para>Calls: Default, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, DRagLint.V151.DFMA.Support.BuildPas, FileExists</para>
/// <para>Returns: Default(TPasUnit); BuildPas(APath, PF.Src, PF.RawSrc, PF.Tree)</para>
/// <para>Catches: Exception (swallowed)</para>
/// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
/// <seealso cref="DRagLint.V151.DFMA.Support.BuildPas"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function LoadPas(const APath: string): TPasUnit;

/// <summary>The declarations (classes, unit-level variables, uses clauses) of ANOTHER unit:
/// parsed with a private parser whose tree is freed at once, and cached per path for the
/// process, so a lint-all over thousands of units does not keep thousands of trees.</summary>
/// <param name="APath">The source file.</param>
/// <returns>Ok = False when unreadable; Routines, Src and RawSrc are always empty.</returns>
/// <exception cref="ETreeSitterException"><!-- drag-lint:auto exc -->via TreeSitter.TTSParser.SetLanguage: Failed to set parser language to 0x%p</exception>
/// <remarks>
/// Thread-safe (one lock). The text is not preprocessed: the parser keeps the first
/// branch of a conditional, as the grammar does.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.DFMA.AncestorHandlers (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.ForeignFormsOf (DRagLint.V151.DFMA.pas)</para>
/// <para>Calls: Copy, Default, DRagLint.Core.Encoding.EnsureUtf8Bytes, DRagLint.Parser.Delphi13.tree_sitter_delphi13, DRagLint.V151.DFMA.Support.BuildPas, FileExists, Integer, LowerCase, TreeSitter.TTSParser.Create, TreeSitter.TTSParser.Parse, TreeSitter.TTSParser.SetLanguage</para>
/// <para>Returns: Default(TPasUnit); nil; Copy(Src, AByteIndex, Remaining); BuildPas(APath, Src, Src, Tree)</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Core.Encoding.EnsureUtf8Bytes"/>
/// <seealso cref="DRagLint.Parser.Delphi13.tree_sitter_delphi13"/>
/// <seealso cref="DRagLint.V151.DFMA.Support.BuildPas"/>
/// <seealso cref="TreeSitter.TTSParser.Create"/>
/// <seealso cref="TreeSitter.TTSParser.Parse"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function LoadPasSummary(const APath: string): TPasUnit;

type
  /// <summary>What the rules read from ANOTHER unit's form file: its root and its handler names.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.DFMA.Support.pas) ?, DRagLint.V151.DFMA.AncestorHandlers (DRagLint.V151.DFMA.pas) ?, DRagLint.V151.DFMA.ForeignFormsOf (DRagLint.V151.DFMA.pas) ?, DRagLint.V151.DFMA.Support.initialization (DRagLint.V151.DFMA.Support.pas) ?, DRagLint.V151.DFMA.Support.LoadDfmHead (DRagLint.V151.DFMA.Support.pas)</para>
  /// <para>Used in units: DRagLint.V151.DFMA, DRagLint.V151.DFMA.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDfmHead = record
    Ok         : Boolean;
    RootName   : string;
    RootClass  : string;
    RootKind   : TDfmNodeKind;
    Handlers   : TArray<string>;   // lower-case
    ClientSized: Boolean;          // the root sets ClientWidth / ClientHeight (a form)
  end;

/// <summary>The root and handler names of a form file, cached per path for the process.</summary>
/// <param name="APath">The .dfm.</param>
/// <returns>Ok = False for a missing, binary or unreadable form file.</returns>
/// <remarks>
/// Thread-safe (one lock).
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.DFMA.AncestorHandlers (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.ForeignFormsOf (DRagLint.V151.DFMA.pas)</para>
/// <para>Calls: Default, DRagLint.V151.DFMA.Support.LoadDfm, DRagLint.V151.DFMA.Support.TDfmDoc.HandlerNames, DRagLint.V151.DFMA.Support.TDfmDoc.IsEmpty, DRagLint.V151.DFMA.Support.TDfmDoc.RootHasProp, LowerCase</para>
/// <para>Returns: Default(TDfmHead)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.V151.DFMA.Support.LoadDfm"/>
/// <seealso cref="DRagLint.V151.DFMA.Support.TDfmDoc.HandlerNames"/>
/// <seealso cref="DRagLint.V151.DFMA.Support.TDfmDoc.IsEmpty"/>
/// <seealso cref="DRagLint.V151.DFMA.Support.TDfmDoc.RootHasProp"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function LoadDfmHead(const APath: string): TDfmHead;

/// <summary>Line (1-based) of a node.</summary>
/// <param name="N"><!-- drag-lint:auto type -->const TTSNode</param>
/// <returns><!-- drag-lint:auto -->Integer -- Observed: Integer(N.StartPoint.row) + 1.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.DFMA.CheckAccessBeforeCreate (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.CheckAutocreateAndManual (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.CheckForeignFormAccess (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.CheckSelfFree (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.Support.TPasBuilder.AddClass (DRagLint.V151.DFMA.Support.pas) (+4 more)</para>
/// <para>Calls: Integer, TreeSitter.TTSNodeHelper.StartPoint</para>
/// <seealso cref="TreeSitter.TTSNodeHelper.StartPoint"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function NodeLine(const N: TTSNode): Integer;

/// <summary>Column (1-based CHARACTER column, 1.52 BK-COLS2) of a node of APath's tree.</summary>
/// <param name="APath">The file N's tree was parsed from (TAstParseCache key).</param>
/// <param name="N"><!-- drag-lint:auto type -->const TTSNode</param>
/// <returns>Integer -- the 1-based character column of N's start, from TAstParseCache.CharCol (not the tree-sitter byte column).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.DFMA.CheckAccessBeforeCreate (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.CheckAutocreateAndManual (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.CheckForeignFormAccess (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.CheckSelfFree (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.Support.TPasBuilder.AddClass (DRagLint.V151.DFMA.Support.pas) (+2 more)</para>
/// <para>Calls: DRagLint.Diagnostics.ParseCache.TAstParseCache.CharCol, TreeSitter.TTSNodeHelper.StartPoint</para>
/// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.CharCol"/>
/// <seealso cref="TreeSitter.TTSNodeHelper.StartPoint"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function NodeCol(const APath: string; const N: TTSNode): Integer;

/// <summary>The source file of unit AUnitName: the project index first, then
/// `&lt;dir of AFromPath&gt;\&lt;AUnitName&gt;.pas`.</summary>
/// <param name="AUnitName"><!-- drag-lint:auto type -->const string</param>
/// <param name="AFromPath"><!-- drag-lint:auto type -->const string</param>
/// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
/// <returns>The path, '' when neither knows it.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.DFMA.AncestorHandlers (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.ForeignForms (DRagLint.V151.DFMA.pas)</para>
/// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, FileExists</para>
/// <para>Returns: ''; AStore.GetFilePath(S.FileId); Cand</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FindUnitFile(const AUnitName, AFromPath: string; const AStore: ISymbolStore): string;

/// <summary>The .dpr whose uses clause names AUnitName: every .dpr of the project index,
/// then every .dpr in the unit's folder.</summary>
/// <param name="APath"><!-- drag-lint:auto type -->const string</param>
/// <param name="AUnitName"><!-- drag-lint:auto type -->const string</param>
/// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
/// <param name="AInfo">Out: the parsed .dpr when found.</param>
/// <returns>True when one was found.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.DFMA.CheckDfmReferenceUnits (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.TV151DFMARules.CheckFile (DRagLint.V151.DFMA.pas)</para>
/// <para>Calls: Default, DRagLint.V151.DFMA.Support.LoadDpr, DRagLint.V151.DFMA.Support.StoreDprPaths, DRagLint.V151.DFMA.Support.TDprInfo.HasUnit</para>
/// <para>Returns: False; True</para>
/// <para>Catches: Exception (empty)</para>
/// <para>Mutates: AInfo (out)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.V151.DFMA.Support.LoadDpr"/>
/// <seealso cref="DRagLint.V151.DFMA.Support.StoreDprPaths"/>
/// <seealso cref="DRagLint.V151.DFMA.Support.TDprInfo.HasUnit"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FindDprFor(const APath, AUnitName: string; const AStore: ISymbolStore; out AInfo: TDprInfo): Boolean;

/// <summary>The ancestor names of AClass, nearest first, walked through ALocal, then the
/// project index, then the library index.</summary>
/// <param name="AClass"><!-- drag-lint:auto type -->const string</param>
/// <param name="ALocal"><!-- drag-lint:auto type -->const TPasUnit</param>
/// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
/// <param name="ALib"><!-- drag-lint:auto type -->const ISymbolStore</param>
/// <param name="AComplete">Out: True when the walk reached a class without ancestor
/// (TObject / TInterfacedObject roots) and no step was unknown.</param>
/// <param name="ALeftProject">Out: True when a step was answered by the library index or
/// left both the unit and the project index (a library class never descends from a
/// project class).</param>
/// <returns>The chain without AClass itself; lower-case.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.DFMA.CheckFieldTypes (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.CheckObjectsWithoutField (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.ForeignFormsOf (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.IsFormClass (DRagLint.V151.DFMA.pas)</para>
/// <para>Calls: DRagLint.V151.DFMA.Support.ClassChain.FromStore, DRagLint.V151.DFMA.Support.TPasUnit.ClassIndex, LastSegment, LowerCase, UniqueClass</para>
/// <para>Returns: nil; Names.ToArray</para>
/// <para>Complexity: 11 (cyclomatic, outer body), 66 lines (full implementation)</para>
/// <para>Mutates: AComplete (out), ALeftProject (out)</para>
/// <seealso cref="DRagLint.V151.DFMA.Support.ClassChain.FromStore"/>
/// <seealso cref="DRagLint.V151.DFMA.Support.TPasUnit.ClassIndex"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ClassChain(const AClass: string; const ALocal: TPasUnit; const AStore, ALib: ISymbolStore;
  out AComplete, ALeftProject: Boolean): TArray<string>;

/// <summary>True when AClass is declared as a class in ALocal or the project index.</summary>
/// <param name="AClass"><!-- drag-lint:auto type -->const string</param>
/// <param name="ALocal"><!-- drag-lint:auto type -->const TPasUnit</param>
/// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
/// <returns><!-- drag-lint:auto -->Boolean -- Observed: (ALocal.ClassIndex(AClass) &gt;=
/// 0) or UniqueClass(AStore, AClass, S).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.DFMA.CheckFieldTypes (DRagLint.V151.DFMA.pas)</para>
/// <para>Calls: DRagLint.V151.DFMA.Support.TPasUnit.ClassIndex, DRagLint.V151.DFMA.Support.UniqueClass</para>
/// <seealso cref="DRagLint.V151.DFMA.Support.TPasUnit.ClassIndex"/>
/// <seealso cref="DRagLint.V151.DFMA.Support.UniqueClass"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsProjectClass(const AClass: string; const ALocal: TPasUnit; const AStore: ISymbolStore): Boolean;

/// <summary>True for a plain Pascal identifier (letters, digits, underscore; no dot).</summary>
/// <param name="S"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->Boolean -- Observed: S &lt;&gt; ''.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.DFMA.CheckDfmReferenceUnits (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.Support.TDfmDoc.HandlerNames (DRagLint.V151.DFMA.Support.pas)</para>
/// <para>Calls: CharInSet</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsPascalIdent(const S: string): Boolean;

/// <summary>Last dotted segment of a qualified name.</summary>
/// <param name="AName"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto type -->string</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.DFMA.CheckDfmReferenceUnits (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.CheckFieldTypes (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.Support.ClassChain.FromStore (DRagLint.V151.DFMA.Support.pas), DRagLint.V151.DFMA.Support.DprScan (DRagLint.V151.DFMA.Support.pas), DRagLint.V151.DFMA.Support.TDfmDoc.HandlerNames (DRagLint.V151.DFMA.Support.pas) (+7 more)</para>
/// <para>Calls: Copy, LastDelimiter, Pos, Trim</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function LastSegment(const AName: string): string;

/// <summary>Makes one finding.</summary>
/// <param name="ARule"><!-- drag-lint:auto type -->const string</param>
/// <param name="APath"><!-- drag-lint:auto type -->const string</param>
/// <param name="ALine"><!-- drag-lint:auto type -->Integer</param>
/// <param name="ACol"><!-- drag-lint:auto type -->Integer</param>
/// <param name="ASeverity"><!-- drag-lint:auto type -->const string</param>
/// <param name="AMessage"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->TLintFinding -- Observed: Default(TLintFinding).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.DFMA.CheckAccessBeforeCreate (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.CheckAutocreateAndManual (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.CheckDfmReferenceUnits (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.CheckFieldsWithoutObject (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.CheckFieldTypes (DRagLint.V151.DFMA.pas) (+5 more)</para>
/// <para>Calls: Default</para>
/// <para>Effect-free (proven)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function MakeFinding(const ARule, APath: string; ALine, ACol: Integer; const ASeverity, AMessage: string): TLintFinding;

implementation

uses
  System.Classes
  , System.IOUtils
  , System.StrUtils
  , System.RegularExpressions
  , DRagLint.Parser.DfmNav
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Core.Encoding
  , DRagLint.Parser.Delphi13
  ;

const
  MAX_CHAIN = 32;

var
  GLock    : TObject;
  GDprCache: TDictionary<string, TDprInfo>;   // lower-case .dpr path -> parsed
  GStoreDpr: TDictionary<Pointer, TArray<string>>;  // store -> its .dpr paths
  GPasSummary: TDictionary<string, TPasUnit>;       // lower-case full path -> declarations
  GDfmHeads  : TDictionary<string, TDfmHead>;       // lower-case full path -> root + handlers

{ ---- small helpers ---- }

function LastSegment(const AName: string): string;
var
  P: Integer;
begin
  P:= LastDelimiter('.', AName);
  Result:= Trim(Copy(AName, P + 1, MaxInt));
  P:= Pos('<', Result);
  if P > 0 then Result:= Copy(Result, 1, P - 1);
end;

function NodeLine(const N: TTSNode): Integer;
begin
  Result:= Integer(N.StartPoint.row) + 1;
end;

function NodeCol(const APath: string; const N: TTSNode): Integer;
begin
  Result:= TAstParseCache.CharCol(APath, N.StartPoint); { 1.52 BK-COLS2: character column }
end;

function MakeFinding(const ARule, APath: string; ALine, ACol: Integer; const ASeverity, AMessage: string): TLintFinding;
begin
  Result:= Default(TLintFinding);
  Result.RuleId   := ARule;
  Result.FilePath := APath;
  Result.StartLine:= ALine;
  Result.StartCol := ACol;
  Result.EndLine  := ALine;
  Result.EndCol   := ACol;
  Result.Severity := ASeverity;
  Result.Message  := AMessage;
end;

function ListHasName(const AList: TArray<string>; const AName: string): Boolean;
begin
  Result:= False;
  for var S in AList do
    if SameText(S, AName) then Exit(True);
end;

{ ---- TDfmDoc ---- }

function TDfmDoc.IsEmpty: Boolean;
begin
  Result:= Length(Nodes) = 0;
end;

function TDfmDoc.IndexOfName(const AName: string): Integer;
begin
  for var I:= 0 to High(Nodes) do
    if (Nodes[I].Kind <> dnkItem) and SameText(Nodes[I].Name, AName) then Exit(I);
  Result:= -1;
end;

function TDfmDoc.RootProp(const AName: string): string;
begin
  Result:= '';
  if IsEmpty then Exit;
  for var P in Nodes[0].Props do
    if SameText(P.Name, AName) then Exit(P.Value);
end;

function TDfmDoc.RootHasProp(const AName: string): Boolean;
begin
  Result:= False;
  if IsEmpty then Exit;
  for var P in Nodes[0].Props do
    if SameText(P.Name, AName) then Exit(True);
end;

function IsPascalIdent(const S: string): Boolean;
begin
  Result:= S <> '';
  if not Result then Exit;
  if not CharInSet(S[1], ['A'..'Z', 'a'..'z', '_']) then Exit(False);
  for var I:= 2 to Length(S) do
    if not CharInSet(S[I], ['A'..'Z', 'a'..'z', '_', '0'..'9']) then Exit(False);
end;

function TDfmDoc.HandlerNames: TArray<string>;
var
  L: TList<string>;
begin
  L:= TList<string>.Create;
  try
    for var N in Nodes do
      for var P in N.Props do
        if StartsText('On', LastSegment(P.Name)) and IsPascalIdent(P.Value) and not L.Contains(LowerCase(P.Value)) then
          L.Add(LowerCase(P.Value));
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

{ ---- .dfm scanner ---- }

const
  { Filer signature that starts a binary form file. }
  BINARY_DFM_SIG: array[0..3] of Byte = (Ord('T'), Ord('P'), Ord('F'), Ord('0'));
  { First byte of a resource-wrapped binary form file. }
  RES_HEADER_FIRST_BYTE = $FF;

function LoadDfm(const APath: string): TDfmDoc;  // dl:ok deep-nesting@90b5, cyclomatic-complexity@ced4, cognitive-complexity@6926 -- REVIEWED 2026-11-14 v151 DFM-A: single-pass scanner / node-kind walker; a split would thread its state through every helper
var
  Raw    : TBytes;
  Lines  : TArray<string>;
  Nodes  : TList<TDfmNode>;
  Props  : TObjectList<TList<TDfmProp>>;
  Stack  : TStack<Integer>;
  I      : Integer;
  T      : string;
  Line   : string;
  N      : TDfmNode;
  P      : Integer;
  PName  : string;
  PVal   : string;
  Top    : Integer;
  Pr     : TDfmProp;
  Kw     : string;
begin
  Result:= Default(TDfmDoc);
  Result.Path:= APath;
  if (APath = '') or not FileExists(APath) then Exit;
  try
    Raw:= TFile.ReadAllBytes(APath);
  except  // dl:ok bare-except@8f3b, try-except-swallowed@8f3b -- REVIEWED 2026-11-14 v151 DFM-A: unreadable or unparseable file means the rule stays silent: no finding beats a false finding
    Exit;
  end;
  { A binary form file starts with the filer signature TPF0 (or a resource header). }
  if (Length(Raw) >= Length(BINARY_DFM_SIG)) and CompareMem(@Raw[0], @BINARY_DFM_SIG[0], Length(BINARY_DFM_SIG)) then Exit;
  if (Length(Raw) > 0) and (Raw[0] = RES_HEADER_FIRST_BYTE) then Exit;
  Lines:= DfmNavLinesFromBytes(Raw);
  Nodes:= TList<TDfmNode>.Create;
  Props:= TObjectList<TList<TDfmProp>>.Create(True);
  Stack:= TStack<Integer>.Create;
  try
    I:= 0;
    while I < Length(Lines) do
    begin
      Line:= Lines[I];
      T:= Trim(Line);
      Inc(I);
      Top:= if Stack.Count > 0 then Stack.Peek else -1;
      if (Nodes.Count = 0) and (T <> '') and not (StartsText('object ', T) or StartsText('inherited ', T) or StartsText('inline ', T)) then
        Exit;  { not a text form file }
      if StartsText('object ', T) or StartsText('inherited ', T) or StartsText('inline ', T) then
      begin
        N:= Default(TDfmNode);
        Kw:= LowerCase(Copy(T, 1, Pos(' ', T) - 1));
        N.Kind:= if Kw = 'object' then dnkObject else if Kw = 'inherited' then dnkInherited else dnkInline;
        N.Parent:= Top;
        N.Line:= I;
        N.Col:= Pos(Kw, LowerCase(Line)) + Length(Kw) + 1;
        if Top >= 0 then N.InInline:= Nodes[Top].InInline or (Nodes[Top].Kind = dnkInline);
        T:= Trim(Copy(T, Pos(' ', T) + 1, MaxInt));
        P:= Pos(':', T);
        if P > 0 then
        begin
          N.Name:= Trim(Copy(T, 1, P - 1));
          N.CompClass:= Trim(Copy(T, P + 1, MaxInt)).Split([' '])[0];
        end
        else
          N.CompClass:= T.Split([' '])[0];
        Nodes.Add(N);
        Props.Add(TList<TDfmProp>.Create);
        Stack.Push(Nodes.Count - 1);
      end
      else if SameText(T, 'item') then
      begin
        N:= Default(TDfmNode);
        N.Kind:= dnkItem;
        N.Parent:= Top;
        N.Line:= I;
        N.Col:= 1;
        if Top >= 0 then N.InInline:= Nodes[Top].InInline or (Nodes[Top].Kind = dnkInline);
        Nodes.Add(N);
        Props.Add(TList<TDfmProp>.Create);
        Stack.Push(Nodes.Count - 1);
      end
      else if SameText(T, 'end') or StartsText('end>', T) then
      begin
        if Stack.Count > 0 then Stack.Pop;
      end
      else
      begin
        P:= Pos('=', T);
        if P = 0 then Continue;
        PName:= Trim(Copy(T, 1, P - 1));
        PVal := Trim(Copy(T, P + 1, MaxInt));
        Pr:= Default(TDfmProp);
        Pr.Name:= PName;
        Pr.Line:= I;
        if (PVal <> '') and CharInSet(PVal[1], ['(', '{']) then
        begin
          { a list or a binary blob: skip to its closing bracket }
          var Close: Char:= if PVal[1] = '(' then ')' else '}';
          var C: string:= PVal;
          while not C.EndsWith(Close) and (I < Length(Lines)) do
          begin
            C:= Trim(Lines[I]);
            Inc(I);
          end;
        end
        else if (PVal = '') or CharInSet(PVal[1], ['''', '#']) then
        begin
          { a string, possibly continued on the next lines }
          var C: string:= PVal;
          while ((C = '') or C.EndsWith('+')) and (I < Length(Lines)) do
          begin
            C:= Trim(Lines[I]);
            if (C = '') or not CharInSet(C[1], ['''', '#']) then Break;
            Inc(I);
          end;
        end
        else if PVal = '<' then
          { a collection: its items follow as `item` nodes }
        else if PVal <> '<>' then
          Pr.Value:= PVal;
        if Top >= 0 then Props[Top].Add(Pr);
      end;
    end;
    Result.Nodes:= Nodes.ToArray;
    for var K:= 0 to High(Result.Nodes) do Result.Nodes[K].Props:= Props[K].ToArray;
  finally
    Stack.Free;
    Props.Free;
    Nodes.Free;
  end;
end;

{ ---- TPasClass / TPasRoutine / TPasUnit ---- }

function TPasClass.FieldIndex(const AName: string): Integer;
begin
  for var I:= 0 to High(Fields) do
    if SameText(Fields[I].Name, AName) then Exit(I);
  Result:= -1;
end;

function TPasClass.HasMethod(const AName: string): Boolean;
begin
  Result:= ListHasName(Methods, AName);
end;

function TPasRoutine.HasLocal(const AName: string): Boolean;
begin
  Result:= ListHasName(Locals, AName);
end;

function TPasUnit.Text(const N: TTSNode): string;  // dl:ok duplicate-code@136e -- REVIEWED 2026-11-14 v151 INT: same shape over different fields; a helper would need more parameters than it saves
var
  S, L: Integer;
begin
  Result:= '';
  if N.IsNull then Exit;
  S:= Integer(N.StartByte);
  L:= Integer(N.EndByte) - S;
  if (L <= 0) or (S < 0) or (S + L > Length(Src)) then Exit;
  Result:= TEncoding.UTF8.GetString(Src, S, L);
end;

function TPasUnit.ClassIndex(const AName: string): Integer;
begin
  for var I:= 0 to High(Classes) do
    if SameText(Classes[I].Name, AName) then Exit(I);
  Result:= -1;
end;

function TPasUnit.VarIndex(const AName: string): Integer;
begin
  for var I:= 0 to High(Vars) do
    if SameText(Vars[I].Name, AName) then Exit(I);
  Result:= -1;
end;

function TPasUnit.UsesUnit(const AUnit: string): Boolean;
begin
  Result:= False;
  for var U in IntfUses + ImplUses do
    if SameText(U, AUnit) or SameText(LastSegment(U), LastSegment(AUnit)) then Exit(True);
end;

type
  TPasBuilder = record
    U       : TPasUnit;
    Classes : TList<TPasClass>;
    Vars    : TList<TPasVar>;
    Routines: TList<TPasRoutine>;
    IUses   : TList<string>;
    MUses   : TList<string>;
    procedure Walk(const N: TTSNode; AInInterface, AInImpl: Boolean);
    procedure AddClass(const ATypeDecl, AClassNode: TTSNode);
    procedure AddVars(const ADeclVars: TTSNode; AInInterface: Boolean);
    procedure AddRoutine(const ADefProc: TTSNode);
  end;

{ Names of a declField / declVar / declArg: its direct identifier children. }
function DeclNames(const AU: TPasUnit; const N: TTSNode): TArray<string>;
begin
  Result:= nil;
  for var I:= 0 to N.NamedChildCount - 1 do
    if N.NamedChild(I).NodeType = 'identifier' then Result:= Result + [AU.Text(N.NamedChild(I))];
end;

function TypeNameOf(const AU: TPasUnit; const N: TTSNode): string;
var
  T: TTSNode;
begin
  T:= N.ChildByField('type');
  Result:= if T.IsNull then '' else LastSegment(Trim(AU.Text(T)));
end;

procedure TPasBuilder.AddClass(const ATypeDecl, AClassNode: TTSNode);
var
  C      : TPasClass;
  Fields : TList<TPasField>;
  Methods: TList<string>;
  HasEnd : Boolean;

  procedure AddMember(const M: TTSNode; APublished: Boolean);
  begin
    if M.NodeType = 'declField' then
    begin
      var TN: string:= TypeNameOf(U, M);
      for var I:= 0 to M.NamedChildCount - 1 do
        if M.NamedChild(I).NodeType = 'identifier' then
        begin
          var F: TPasField:= Default(TPasField);
          F.Name:= U.Text(M.NamedChild(I));
          F.TypeName:= TN;
          F.IsPublished:= APublished;
          F.Line:= NodeLine(M.NamedChild(I));
          F.Col:= TAstParseCache.CharCol(U.Path, M.NamedChild(I).StartPoint); { 1.52 BK-COLS2: character column }
          Fields.Add(F);
        end;
    end
    else if M.NodeType = 'declProc' then
    begin
      var Nm: TTSNode:= M.ChildByField('name');
      if not Nm.IsNull then Methods.Add(LowerCase(LastSegment(U.Text(Nm))));
    end;
  end;

begin
  C:= Default(TPasClass);
  C.Name:= LastSegment(U.Text(ATypeDecl.ChildByField('name')));
  C.Line:= NodeLine(ATypeDecl);
  C.Col:= TAstParseCache.CharCol(U.Path, ATypeDecl.StartPoint); { 1.52 BK-COLS2: character column }
  { The first typeref child is the parent class: the 'parent' field can name the '(' token. }
  for var I:= 0 to AClassNode.NamedChildCount - 1 do
    if AClassNode.NamedChild(I).NodeType = 'typeref' then
    begin
      C.ParentName:= LastSegment(U.Text(AClassNode.NamedChild(I)));
      Break;
    end;
  Fields:= TList<TPasField>.Create;
  Methods:= TList<string>.Create;
  try
    HasEnd:= False;
    for var I:= 0 to AClassNode.ChildCount - 1 do
    begin
      var Ch: TTSNode:= AClassNode.Child(I);
      if Ch.NodeType = 'kEnd' then HasEnd:= True
      else if Ch.NodeType = 'declSection' then
      begin
        var Pub: Boolean:= False;
        if Ch.ChildCount > 0 then Pub:= Ch.Child(0).NodeType = 'kPublished';
        for var J:= 0 to Ch.NamedChildCount - 1 do AddMember(Ch.NamedChild(J), Pub);
      end
      else AddMember(Ch, True);
    end;
    if not HasEnd then Exit;   { forward declaration }
    C.Fields:= Fields.ToArray;
    C.Methods:= Methods.ToArray;
    Classes.Add(C);
  finally
    Methods.Free;
    Fields.Free;
  end;
end;

procedure TPasBuilder.AddVars(const ADeclVars: TTSNode; AInInterface: Boolean);
begin
  for var I:= 0 to ADeclVars.NamedChildCount - 1 do
  begin
    var D: TTSNode:= ADeclVars.NamedChild(I);
    if D.NodeType <> 'declVar' then Continue;
    var TN: string:= TypeNameOf(U, D);
    for var Nm in DeclNames(U, D) do
    begin
      var V: TPasVar:= Default(TPasVar);
      V.Name:= Nm;
      V.TypeName:= TN;
      V.InInterface:= AInInterface;
      V.Line:= NodeLine(D);
      Vars.Add(V);
    end;
  end;
end;

procedure TPasBuilder.AddRoutine(const ADefProc: TTSNode);
var
  R     : TPasRoutine;
  Hdr   : TTSNode;
  Nm    : TTSNode;
  Locals: TList<string>;
begin
  R:= Default(TPasRoutine);
  Hdr:= ADefProc.ChildByField('header');
  if Hdr.IsNull then Exit;
  Nm:= Hdr.ChildByField('name');
  if Nm.IsNull then Exit;
  if Nm.NodeType = 'genericDot' then
  begin
    R.OwnerClass:= LastSegment(U.Text(Nm.ChildByField('lhs')));
    R.Name:= LastSegment(U.Text(Nm.ChildByField('rhs')));
  end
  else
    R.Name:= LastSegment(U.Text(Nm));
  for var I:= 0 to Hdr.ChildCount - 1 do
    if Hdr.Child(I).NodeType = 'kConstructor' then R.IsCtor:= True;
  R.Line:= NodeLine(ADefProc);
  R.Col:= TAstParseCache.CharCol(U.Path, ADefProc.StartPoint); { 1.52 BK-COLS2: character column }
  R.Body:= ADefProc.ChildByField('body');
  Locals:= TList<string>.Create;
  try
    var Args: TTSNode:= Hdr.ChildByField('args');
    if not Args.IsNull then
      for var I:= 0 to Args.NamedChildCount - 1 do
      begin
        var A: TTSNode:= Args.NamedChild(I);
        if A.NodeType <> 'declArg' then Continue;
        var TN: string:= TypeNameOf(U, A);
        for var S in DeclNames(U, A) do
        begin
          Locals.Add(LowerCase(S));
          if SameText(S, 'Sender') and SameText(TN, 'TObject') then R.SenderObj:= True;
        end;
      end;
    for var I:= 0 to ADefProc.NamedChildCount - 1 do
    begin
      var D: TTSNode:= ADefProc.NamedChild(I);
      if D.NodeType = 'declVars' then
        for var J:= 0 to D.NamedChildCount - 1 do
          if D.NamedChild(J).NodeType = 'declVar' then
            for var S in DeclNames(U, D.NamedChild(J)) do Locals.Add(LowerCase(S));
    end;
    R.Locals:= Locals.ToArray;
  finally
    Locals.Free;
  end;
  Routines.Add(R);
end;

procedure TPasBuilder.Walk(const N: TTSNode; AInInterface, AInImpl: Boolean);  // dl:ok deep-nesting@dd0f -- REVIEWED 2026-11-14 v151 DFM-A: single-pass scanner / node-kind walker; a split would thread its state through every helper
var
  T: string;
begin
  if N.IsNull then Exit;
  T:= N.NodeType;
  if T = 'interface' then AInInterface:= True
  else if T = 'implementation' then
  begin
    AInInterface:= False;
    AInImpl:= True;
    U.ImplLine:= NodeLine(N);
  end;
  if T = 'declUses' then
  begin
    for var I:= 0 to N.NamedChildCount - 1 do
      if N.NamedChild(I).NodeType = 'declUsesUnit' then
      begin
        var M: TTSNode:= N.NamedChild(I).ChildByField('name');
        if M.IsNull then
          for var J:= 0 to N.NamedChild(I).NamedChildCount - 1 do
            if N.NamedChild(I).NamedChild(J).NodeType = 'moduleName' then
            begin
              M:= N.NamedChild(I).NamedChild(J);
              Break;
            end;
        if M.IsNull then Continue;
        var S: string:= StringReplace(U.Text(M), ' ', '', [rfReplaceAll]);
        if AInImpl then MUses.Add(S) else IUses.Add(S);
      end;
    Exit;
  end;
  if T = 'declType' then
  begin
    var Ty: TTSNode:= N.ChildByField('type');
    if not Ty.IsNull then
      for var I:= 0 to Ty.NamedChildCount - 1 do
        if Ty.NamedChild(I).NodeType = 'declClass' then AddClass(N, Ty.NamedChild(I));
    Exit;   { nested types of a class are not form classes }
  end;
  if (T = 'declVars') and ((N.Parent.NodeType = 'interface') or (N.Parent.NodeType = 'implementation')
    or (N.Parent.NodeType = 'program') or (N.Parent.NodeType = 'unit')) then
  begin
    AddVars(N, AInInterface);
    Exit;
  end;
  if T = 'defProc' then
  begin
    AddRoutine(N);
    { nested routines are routines too }
    for var I:= 0 to N.NamedChildCount - 1 do
      if N.NamedChild(I).NodeType = 'defProc' then Walk(N.NamedChild(I), AInInterface, AInImpl);
    Exit;
  end;
  for var I:= 0 to N.NamedChildCount - 1 do Walk(N.NamedChild(I), AInInterface, AInImpl);
end;

function BuildPas(const APath: string; const ASrc, ARawSrc: TBytes; const ATree: TTSTree): TPasUnit; forward;

function LoadPas(const APath: string): TPasUnit;
var
  PF: TParsedFile;
begin
  Result:= Default(TPasUnit);
  Result.Path:= APath;
  if (APath = '') or not FileExists(APath) then Exit;
  try
    PF:= TAstParseCache.Get(APath);
  except  // dl:ok bare-except@8f3b, try-except-swallowed@8f3b -- REVIEWED 2026-11-14 v151 DFM-A: unreadable or unparseable file means the rule stays silent: no finding beats a false finding
    Exit;
  end;
  if PF.Tree = nil then Exit;
  Result:= BuildPas(APath, PF.Src, PF.RawSrc, PF.Tree);
end;

function LoadPasSummary(const APath: string): TPasUnit;
var
  Key   : string;
  Src   : TBytes;
  Parser: TTSParser;
  Tree  : TTSTree;
begin
  Result:= Default(TPasUnit);
  Result.Path:= APath;
  if (APath = '') or not FileExists(APath) then Exit;
  Key:= LowerCase(TPath.GetFullPath(APath));
  TMonitor.Enter(GLock);
  try
    if GPasSummary.TryGetValue(Key, Result) then Exit;
    try
      Src:= EnsureUtf8Bytes(TFile.ReadAllBytes(APath));
    except  // dl:ok bare-except@e880 -- REVIEWED 2026-11-14 v151 DFM-A: unreadable or unparseable file means the rule stays silent: no finding beats a false finding
      Src:= nil;
    end;
    Tree:= nil;
    if Length(Src) > 0 then
    begin
      Parser:= TTSParser.Create;
      try
        Parser.Language:= tree_sitter_delphi13;
        Tree:= Parser.Parse(
          function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
          var
            Remaining: Integer;
          begin
            Remaining:= Length(Src) - Integer(AByteIndex);
            if Remaining <= 0 then
            begin
              ABytesRead:= 0;
              Exit(nil);
            end;
            Result:= Copy(Src, AByteIndex, Remaining);
            ABytesRead:= Remaining;
          end, TTSInputEncoding.TSInputEncodingUTF8);
      finally
        Parser.Free;
      end;
    end;
    if Tree <> nil then
      try
        Result:= BuildPas(APath, Src, Src, Tree);
      finally
        Tree.Free;
      end;
    { the nodes died with the tree; keep only the declarations }
    Result.Routines:= nil;
    Result.Src:= nil;
    Result.RawSrc:= nil;
    GPasSummary.AddOrSetValue(Key, Result);
  finally
    TMonitor.Exit(GLock);
  end;
end;

function LoadDfmHead(const APath: string): TDfmHead;
var
  Key: string;
begin
  Result:= Default(TDfmHead);
  if APath = '' then Exit;
  Key:= LowerCase(TPath.GetFullPath(APath));
  TMonitor.Enter(GLock);
  try
    if GDfmHeads.TryGetValue(Key, Result) then Exit;
    var D: TDfmDoc:= LoadDfm(APath);
    if not D.IsEmpty then
    begin
      Result.Ok:= True;
      Result.RootName:= D.Nodes[0].Name;
      Result.RootClass:= D.Nodes[0].CompClass;
      Result.RootKind:= D.Nodes[0].Kind;
      Result.Handlers:= D.HandlerNames;
      Result.ClientSized:= D.RootHasProp('ClientWidth') or D.RootHasProp('ClientHeight');
    end;
    GDfmHeads.AddOrSetValue(Key, Result);
  finally
    TMonitor.Exit(GLock);
  end;
end;

function BuildPas(const APath: string; const ASrc, ARawSrc: TBytes; const ATree: TTSTree): TPasUnit;
var
  B : TPasBuilder;
begin
  Result:= Default(TPasUnit);
  B:= Default(TPasBuilder);
  B.U.Path:= APath;
  B.U.Src:= ASrc;
  B.U.RawSrc:= ARawSrc;
  B.U.UnitName:= TPath.GetFileNameWithoutExtension(APath);
  B.Classes:= TList<TPasClass>.Create;
  B.Vars:= TList<TPasVar>.Create;
  B.Routines:= TList<TPasRoutine>.Create;
  B.IUses:= TList<string>.Create;
  B.MUses:= TList<string>.Create;
  try
    B.Walk(ATree.RootNode, False, False);
    B.U.Classes:= B.Classes.ToArray;
    B.U.Vars:= B.Vars.ToArray;
    B.U.Routines:= B.Routines.ToArray;
    B.U.IntfUses:= B.IUses.ToArray;
    B.U.ImplUses:= B.MUses.ToArray;
    B.U.Ok:= True;
    Result:= B.U;
  finally
    B.MUses.Free;
    B.IUses.Free;
    B.Routines.Free;
    B.Vars.Free;
    B.Classes.Free;
  end;
end;

{ ---- cross-file lookups ---- }

function FindUnitFile(const AUnitName, AFromPath: string; const AStore: ISymbolStore): string;
begin
  Result:= '';
  if AUnitName = '' then Exit;
  if AStore <> nil then
    for var S in AStore.FindSymbolsByExactName(AUnitName) do
      if S.Kind = skUnit then
      begin
        Result:= AStore.GetFilePath(S.FileId);
        if (Result <> '') and FileExists(Result) then Exit;
        Result:= '';
      end;
  if AFromPath <> '' then
  begin
    var Cand: string:= TPath.Combine(TPath.GetDirectoryName(AFromPath), AUnitName + '.pas');
    if FileExists(Cand) then Result:= Cand;
  end;
end;

function TDprInfo.HasUnit(const AUnit: string): Boolean;
begin
  Result:= ListHasName(Units, AUnit) or ListHasName(Units, LastSegment(AUnit));
end;

function TDprInfo.CreateIndexOfClass(const AClass: string): Integer;
begin
  for var I:= 0 to High(Creates) do
    if SameText(Creates[I].ClassName, AClass) then Exit(I);
  Result:= -1;
end;

function TDprInfo.CreateIndexOfVar(const AVar: string): Integer;
begin
  for var I:= 0 to High(Creates) do
    if SameText(Creates[I].VarName, AVar) then Exit(I);
  Result:= -1;
end;

function TDprInfo.UnitOfModule(const AModule: string): string;
begin
  Result:= '';
  for var M in Modules do
    if StartsText(LowerCase(AModule) + '=', M) then Exit(Copy(M, Length(AModule) + 2, MaxInt));
end;

{ Reads the uses clause (unit names and the module name comment after in '<file>') and the
  Application.CreateForm calls of cleaned .dpr text (see DprCleanText). }
function DprScan(const AText: string): TDprInfo;
var
  Units  : TList<string>;
  Mods   : TList<string>;
  Creates: TList<TDprCreate>;
  M      : TMatch;
  C      : TDprCreate;
begin
  Result:= Default(TDprInfo);
  Units:= TList<string>.Create;
  Mods:= TList<string>.Create;
  Creates:= TList<TDprCreate>.Create;
  try
    // Unit1 in 'Unit1.pas' {Form1}  /  Unit1 in 'Unit1.pas'  /  Unit1
    var UsesM: TMatch:= TRegEx.Match(AText, '\buses\b(.*?);', [roIgnoreCase, roSingleLine]);
    if UsesM.Success then
      for M in TRegEx.Matches(UsesM.Groups[1].Value,
        '([A-Za-z_][\w.]*)\s*(?:\bin\s*''[^'']*''\s*)?(?:\{\s*([A-Za-z_]\w*)\s*(?::\s*[A-Za-z_]\w*\s*)?\})?\s*(?:,|$)',
        [roIgnoreCase]) do
      begin
        Units.Add(LowerCase(M.Groups[1].Value));
        if (M.Groups.Count > 2) and (M.Groups[2].Value <> '') then
          Mods.Add(LowerCase(M.Groups[2].Value) + '=' + M.Groups[1].Value);
      end;
    for M in TRegEx.Matches(AText, '\bApplication\s*\.\s*CreateForm\s*\(\s*([A-Za-z_][\w.]*)\s*,\s*([A-Za-z_]\w*)\s*\)',
      [roIgnoreCase]) do
    begin
      C.ClassName:= LastSegment(M.Groups[1].Value);
      C.VarName:= M.Groups[2].Value;
      Creates.Add(C);
    end;
    Result.Units:= Units.ToArray;
    Result.Modules:= Mods.ToArray;
    Result.Creates:= Creates.ToArray;
  finally
    Creates.Free;
    Mods.Free;
    Units.Free;
  end;
end;

{ The .dpr text with `//` and `(* *)` comments and every brace comment that is not a bare
  module name blanked, so a commented-out CreateForm does not count. }
function DprCleanText(const AText: string): string;
var
  Sb: TStringBuilder;
  I : Integer;
  L : Integer;
begin
  Sb:= TStringBuilder.Create;
  try
    I:= 1;
    L:= Length(AText);
    while I <= L do
    begin
      if (AText[I] = '/') and (I < L) and (AText[I + 1] = '/') then
      begin
        while (I <= L) and not CharInSet(AText[I], [#10, #13]) do Inc(I);
      end
      else if (AText[I] = '(') and (I < L) and (AText[I + 1] = '*') then
      begin
        Inc(I, 2);
        while (I < L) and not ((AText[I] = '*') and (AText[I + 1] = ')')) do Inc(I);
        Inc(I, 2);
      end
      else if AText[I] = '{' then
      begin
        var J: Integer:= I;
        while (J <= L) and (AText[J] <> '}') do Inc(J);
        var Inner: string:= Copy(AText, I + 1, J - I - 1);
        if (Inner <> '') and (Inner[1] <> '$') and TRegEx.IsMatch(Inner, '^\s*[A-Za-z_]\w*\s*(:\s*[A-Za-z_]\w*\s*)?$') then
          Sb.Append('{' + Inner + '}');
        I:= J + 1;
      end
      else if AText[I] = '''' then
      begin
        var J: Integer:= I + 1;
        while (J <= L) and (AText[J] <> '''') do Inc(J);
        Sb.Append(Copy(AText, I, J - I + 1));
        I:= J + 1;
      end
      else
      begin
        Sb.Append(AText[I]);
        Inc(I);
      end;
    end;
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end;
end;

function LoadDpr(const APath: string; out AInfo: TDprInfo): Boolean;
begin
  AInfo:= Default(TDprInfo);
  var Key: string:= LowerCase(APath);
  if GDprCache.TryGetValue(Key, AInfo) then Exit(True);
  Result:= False;
  try
    var Raw: TBytes:= TFile.ReadAllBytes(APath);
    var Text: string:= TEncoding.UTF8.GetString(Raw);
    if (Text <> '') and (Text[1] = #$FEFF) then Delete(Text, 1, 1);
    AInfo:= DprScan(DprCleanText(Text));
    AInfo.Path:= APath;
    GDprCache.AddOrSetValue(Key, AInfo);
    Result:= True;
  except  // dl:ok bare-except@c2fd -- REVIEWED 2026-11-14 v151 DFM-A: unreadable or unparseable file means the rule stays silent: no finding beats a false finding
    AInfo:= Default(TDprInfo);
  end;
end;

function StoreDprPaths(const AStore: ISymbolStore): TArray<string>;
var
  Key: Pointer;
begin
  Result:= nil;
  if AStore = nil then Exit;
  Key:= Pointer(AStore);
  if GStoreDpr.TryGetValue(Key, Result) then Exit;
  for var Id in AStore.GetAllFileIds do
  begin
    var P: string:= AStore.GetFilePath(Id);
    if SameText(TPath.GetExtension(P), '.dpr') and FileExists(P) then Result:= Result + [P];
  end;
  GStoreDpr.AddOrSetValue(Key, Result);
end;

function FindDprFor(const APath, AUnitName: string; const AStore: ISymbolStore; out AInfo: TDprInfo): Boolean;
var
  Cands: TArray<string>;
begin
  AInfo:= Default(TDprInfo);
  Result:= False;
  TMonitor.Enter(GLock);
  try
    Cands:= StoreDprPaths(AStore);
    try
      Cands:= Cands + TDirectory.GetFiles(TPath.GetDirectoryName(APath), '*.dpr');
    except
      { an unreadable folder adds nothing }
    end;
    for var C in Cands do
    begin
      var Info: TDprInfo;
      if LoadDpr(C, Info) and Info.HasUnit(AUnitName) then
      begin
        AInfo:= Info;
        Exit(True);
      end;
    end;
  finally
    TMonitor.Exit(GLock);
  end;
end;

{ ---- class chains ---- }

function UniqueClass(const AStore: ISymbolStore; const AName: string; out ASym: TSymbol): Boolean;
var
  Hits: Integer;
begin
  ASym:= Default(TSymbol);
  Hits:= 0;
  if AStore <> nil then
    for var S in AStore.FindSymbolsByExactName(AName) do
      if S.Kind = skClass then
      begin
        Inc(Hits);
        ASym:= S;
      end;
  Result:= Hits = 1;
end;

function IsProjectClass(const AClass: string; const ALocal: TPasUnit; const AStore: ISymbolStore): Boolean;
var
  S: TSymbol;
begin
  Result:= (ALocal.ClassIndex(AClass) >= 0) or UniqueClass(AStore, AClass, S);
end;

function ClassChain(const AClass: string; const ALocal: TPasUnit; const AStore, ALib: ISymbolStore;
  out AComplete, ALeftProject: Boolean): TArray<string>;
var
  Names: TList<string>;
  Cur  : string;
  Guard: Integer;

  { Adds the store's view of ACls; returns the next name to continue from ('' = done),
    False when the store does not know ACls. }
  function FromStore(const AStore2: ISymbolStore; const ACls: string; out ANext: string): Boolean;
  var
    Sym: TSymbol;
  begin
    ANext:= '';
    Result:= UniqueClass(AStore2, ACls, Sym);
    if not Result then Exit;
    for var A in AStore2.GetTransitiveAncestors(Sym.Id) do
      if (A.Name <> '') and not Names.Contains(LowerCase(LastSegment(A.Name))) then
        Names.Add(LowerCase(LastSegment(A.Name)));
    var Holes: TArray<string>:= AStore2.UnresolvedAncestorNames(ACls, Sym.FileId);
    if Length(Holes) > 0 then ANext:= LastSegment(Holes[0]);
  end;

begin
  Result:= nil;
  AComplete:= False;
  ALeftProject:= False;
  Names:= TList<string>.Create;
  try
    Cur:= AClass;
    Guard:= 0;
    while (Cur <> '') and (Guard < MAX_CHAIN) do
    begin
      Inc(Guard);
      var Idx: Integer:= ALocal.ClassIndex(Cur);
      if Idx >= 0 then
      begin
        Cur:= ALocal.Classes[Idx].ParentName;
        if Cur = '' then
        begin
          AComplete:= True;
          Break;
        end;
        if Names.Contains(LowerCase(Cur)) then Break;
        Names.Add(LowerCase(Cur));
        Continue;
      end;
      var Next: string;
      if (not ALeftProject) and FromStore(AStore, Cur, Next) then
      begin
        Cur:= Next;
        if Cur = '' then AComplete:= True;
        Continue;
      end;
      ALeftProject:= True;
      if FromStore(ALib, Cur, Next) then
      begin
        if Next = '' then AComplete:= True;
        Break;   { a library chain with a hole stays unknown }
      end;
      Break;   { unknown class }
    end;
    Result:= Names.ToArray;
  finally
    Names.Free;
  end;
end;

initialization
  GLock:= TObject.Create;
  GDprCache:= TDictionary<string, TDprInfo>.Create;
  GStoreDpr:= TDictionary<Pointer, TArray<string>>.Create;
  GPasSummary:= TDictionary<string, TPasUnit>.Create;
  GDfmHeads:= TDictionary<string, TDfmHead>.Create;

finalization
  GDfmHeads.Free;
  GPasSummary.Free;
  GStoreDpr.Free;
  GDprCache.Free;
  GLock.Free;

end.
