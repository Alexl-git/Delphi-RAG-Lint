unit DRagLint.Index.LibraryOracle;

{ Item 4 (untypable receivers), spec 2026-10-28-untypable-receivers s.5 item 4.
  Binds a call or member access whose receiver the PROJECT index typed only BY
  NAME (the type lives in the platform library) to the qualified NAME of the
  member in one of the extra (library) stores. The answer lands on
  refs.external_target; it is a name, never an id, because call_edges can only
  point into the project's own symbols table.

  The rules are deliberately narrow -- a wrong external name is a wrong FACT:
    * exactly ONE type of the leaf name across the stores (forward declarations
      and the body share one qualified name and count once; a nested type never
      counts; a `type X = Y` alias counts only when its ordinal-0 ancestor row
      lands on a class / record / interface), else the candidates whose
      declaring unit the referencing file uses, else decline ambiguous-type;
    * the member is looked up on that type, then its library ancestors in
      breadth-first order; the FIRST type declaring the name decides, and when
      what it declares is not of an acceptable kind the answer is no-member --
      a nearer declaration hides a farther one in Delphi, so the oracle never
      skips past it;
    * same-named overloads on the deciding type are ONE qualified name.
  No reference to the resolver: readers (find-callees, context) can use it. }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces;

type
  /// <summary>A set of symbol kinds the oracle accepts at one step.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.Cached (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.Collect (DRagLint.Index.LibraryOracle.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TOracleKindSet = set of TSymbolKind;

  /// <summary>Kind of site being bound.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.CallResolver.TCallResolver.BindExternally (DRagLint.Index.CallResolver.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.Bind (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.MemberOf (DRagLint.Index.LibraryOracle.pas) (+1 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TExternalKind = (ekCall, ekMemberAccess, ekBareCall);

  /// <summary>Counters of the oracle's outcomes, printed on the resolve: summary line.</summary>
  /// <remarks>
  /// Every Bind / BindHead / BindBare call increments exactly one counter.
  /// Intrinsic and LateBound (E-RECV-UNDECIDABLE D08 / D10, owner ruling 2026-11-08) count the
  /// binds that are not a routine: a dynamic-array constructor (`TBytes.Create`, bound to the
  /// synthetic INTRINSIC_DYNARRAY_CREATE) and a call through an event property or procedural
  /// field (`V.OnColumnSizeChanged(V, nil)`, bound to the property). They are not in Bound;
  /// LastKind tells the caller which kind the last answer was.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Index.CallResolver.pas), declaration (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.CallResolver.TCallResolver.OracleStats (DRagLint.Index.CallResolver.pas)</para>
  /// <para>Used in units: DRagLint.Index.CallResolver, DRagLint.Index.LibraryOracle</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TOracleStats = record
    Bound, AmbiguousType, NoMember, NoStore, NoType, Intrinsic, LateBound: Integer;
  end;


  /// <summary>Binds a receiver typed BY NAME to a qualified symbol name in one of the extra
  /// (library) stores. Pure reader: owns no store, writes nothing, caches per type.</summary>
  /// <remarks>
  /// Not thread-safe. One instance per resolve pass or reader; the caches assume the
  /// stores do not change while it lives.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoContext (DRagLint.CLI.pas), DRagLint.CLI.DoFindCallees (DRagLint.CLI.pas), DRagLint.CLI.EmitExternalCallees (DRagLint.CLI.pas) ?, DRagLint.Index.CallResolver.TCallResolver.Create (DRagLint.Index.CallResolver.pas), DRagLint.Lint.OpaqueToAnalysis.TOpaqueScan.Create (DRagLint.Lint.OpaqueToAnalysis.pas) (+6 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Context.Bundler, DRagLint.Index.CallResolver, DRagLint.Lint.OpaqueToAnalysis</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TLibraryOracle = class
  strict private type
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Used by: declaration (DRagLint.Index.LibraryOracle.pas) ?, DRagLint.Index.LibraryOracle.TLibraryOracle.Collect.Add (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.HelperCands (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.Pick (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.PickType (DRagLint.Index.LibraryOracle.pas) (+19 more)</para>
    /// <para>Used in units: DRagLint.Index.LibraryOracle</para>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Bind"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.BindBare"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.BindHead"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    TLibCand = record
      Store   : Integer;        // index into FStores
      Ids     : TArray<Int64>;  // every row of ONE qualified name (forward declaration + body)
      QName   : string;
      Name    : string;
      UnitStem: string;         // lower-cased declaring unit (file stem)
      FileId  : Int64;
      Kind    : TSymbolKind;
      Sig     : string;
    end;
  strict private
    FStores   : TArray<ISymbolStore>;
    FStats    : TOracleStats;
    FTypes    : TDictionary<string, TArray<TLibCand>>;
    FValues   : TDictionary<string, TArray<TLibCand>>;
    FRoutines : TDictionary<string, TArray<TLibCand>>;
    FKids     : TDictionary<string, TArray<TSymbol>>;
    FAncestors: TDictionary<string, TArray<TTypeAncestor>>;
    FStems    : TDictionary<string, string>;
    FFileUses : TDictionary<string, TArray<string>>;
    FHelperMembers: TDictionary<string, string>;
    FHelperTypes  : TDictionary<string, TArray<TLibCand>>;
    FAliases      : TDictionary<string, TArray<TLibCand>>;
    FOwnUses      : TArray<string>;
    FLastKind     : string;
    /// <param name="ATypeText"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AUses"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
    /// <param name="ADepth"><!-- drag-lint:auto type -->Integer</param>
    /// <returns><!-- drag-lint:auto type -->Boolean</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.LibraryOracle.TLibraryOracle.BindHead (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.BindIntrinsic (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.IsDynArrayType (DRagLint.Index.LibraryOracle.pas)</para>
    /// <para>Calls: DRagLint.Index.LibraryOracle.NormalizeTypeLeaf, DRagLint.Index.LibraryOracle.TLibraryOracle.Cached, DRagLint.Index.LibraryOracle.TLibraryOracle.InQualifier, DRagLint.Index.LibraryOracle.TLibraryOracle.IsDynArrayType, DRagLint.Index.LibraryOracle.TLibraryOracle.LibraryUses, DRagLint.Index.LibraryOracle.TLibraryOracle.NamesVisibleType, DRagLint.Index.LibraryOracle.TLibraryOracle.VisibleOf, Trim</para>
    /// <para>Reads: FAliases</para>
    /// <para>Recursive</para>
    /// <seealso cref="DRagLint.Index.LibraryOracle.NormalizeTypeLeaf"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Cached"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.InQualifier"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.LibraryUses"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.NamesVisibleType"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsDynArrayType(const ATypeText: string; const AUses: TArray<string>; ADepth: Integer): Boolean;
    /// <summary><!-- drag-lint:auto sum -->E-RECV-UNDECIDABLE D08: True when ATypeText
    /// names a dynamic array type: `TArray&lt;X&gt;` (the generic arguments do not
    /// matter) or a library alias whose every visible declaration is `array of ..`,
    /// directly or through at most MAX_ALIAS_HOPS further aliases (`TBytes =
    /// TArray&lt;Byte&gt;`). A name that is also a visible class / record / interface, or
    /// that no visible alias declares, is not one. A visible class / record / interface
    /// the type text can name: a text WITH generic arguments (`TArray&lt;Integer&gt;`)
    /// names only a generic declaration, so System.Generics.Collections' plain `TArray`
    /// class does not hide System's `TArray&lt;T&gt; = array of T`.</summary>
    /// <param name="AText"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ALeaf"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AUses"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.LibraryOracle.TLibraryOracle.IsDynArrayType (DRagLint.Index.LibraryOracle.pas)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById, DRagLint.Index.LibraryOracle.TLibraryOracle.Cached, DRagLint.Index.LibraryOracle.TLibraryOracle.VisibleOf</para>
    /// <para>Reads: FTypes, FStores</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Cached"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.VisibleOf"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function NamesVisibleType(const AText, ALeaf: string; const AUses: TArray<string>): Boolean;
    /// <summary><!-- drag-lint:auto sum -->The candidates a UNIT-QUALIFIED text can mean
    /// (`SysUtils.TBytes` -&gt; System.SysUtils's, as Spring writes it): declared in a
    /// unit whose name is the qualifier or ends with `.qualifier`. An unqualified text
    /// keeps every candidate.</summary>
    /// <param name="AText"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ACands"><!-- drag-lint:auto type -->const TArray&lt;TLibCand&gt;</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TLibCand&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.LibraryOracle.TLibraryOracle.IsDynArrayType (DRagLint.Index.LibraryOracle.pas)</para>
    /// <para>Calls: Copy, LowerCase, Pos, Trim</para>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Bind"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.BindBare"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.BindHead"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function InQualifier(const AText: string; const ACands: TArray<TLibCand>): TArray<TLibCand>;
    /// <summary><!-- drag-lint:auto sum -->E-RECV-UNDECIDABLE D05: every library helper
    /// whose target is named ALeaf (`record helper for string` -&gt; TStringHelper), one
    /// candidate per helper.</summary>
    /// <param name="ALeaf"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TLibCand&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.LibraryOracle.TLibraryOracle.PickTypeOrHelper (DRagLint.Index.LibraryOracle.pas)</para>
    /// <para>Calls: Default, DRagLint.Core.Interfaces.ISymbolStore.FindHelpersOfType, DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById, DRagLint.Index.LibraryOracle.TLibraryOracle.UnitStemOf, LowerCase</para>
    /// <para>Reads: FHelperTypes, FStores</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindHelpersOfType"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.UnitStemOf"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function HelperCands(const ALeaf: string): TArray<TLibCand>;
    /// <param name="ATypeText"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ATypeUses"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
    /// <param name="AHelperUses"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
    /// <param name="ACand"><!-- drag-lint:auto type -->out TLibCand</param>
    /// <param name="AReason"><!-- drag-lint:auto type -->out string</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: PickType(ATypeText,
    /// ATypeUses, ACand, AReason); True.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto -->A type name no library type answers may still have members: a
    /// built-in type's helper (`S.Split`, `B.ToString`). Only one helper per type is active in
    /// Delphi, so exactly one visible helper answers; two decline. The helper's scope is the
    /// CALLING file's (AHelperUses), whatever unit named the type.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.LibraryOracle.TLibraryOracle.Bind (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.StepPending (DRagLint.Index.LibraryOracle.pas)</para>
    /// <para>Calls: DRagLint.Index.LibraryOracle.NormalizeTypeLeaf, DRagLint.Index.LibraryOracle.TLibraryOracle.HelperCands, DRagLint.Index.LibraryOracle.TLibraryOracle.PickType, DRagLint.Index.LibraryOracle.TLibraryOracle.VisibleOf</para>
    /// <para>Mutates: ACand (out), AReason (out)</para>
    /// <seealso cref="DRagLint.Index.LibraryOracle.NormalizeTypeLeaf"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.HelperCands"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.PickType"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.VisibleOf"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function PickTypeOrHelper(const ATypeText: string; const ATypeUses, AHelperUses: TArray<string>;
      out ACand: TLibCand; out AReason: string): Boolean;
    /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
    /// <param name="AStoreTag"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ATypeName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AMember"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: Names.Contains(';' +
    /// LowerCase(AMember) + ';').</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.LibraryOracle.TLibraryOracle.CandProvesAbsent (DRagLint.Index.LibraryOracle.pas)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindAllChildSymbols, DRagLint.Core.Interfaces.ISymbolStore.FindHelpersOfType, LowerCase</para>
    /// <para>Reads: FHelperMembers</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindAllChildSymbols"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindHelpersOfType"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Bind"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function HelpersDeclare(const AStore: ISymbolStore; const AStoreTag, ATypeName, AMember: string): Boolean;
    /// <param name="ACand"><!-- drag-lint:auto type -->const TLibCand</param>
    /// <param name="AMember"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AProjectStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: True.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.LibraryOracle.TLibraryOracle.MemberProvablyAbsent (DRagLint.Index.LibraryOracle.pas)</para>
    /// <para>Calls: DRagLint.Index.LibraryOracle.IsRootAncestorName, DRagLint.Index.LibraryOracle.NormalizeTypeLeaf, DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors, DRagLint.Index.LibraryOracle.TLibraryOracle.DeclaringMember, DRagLint.Index.LibraryOracle.TLibraryOracle.HelpersDeclare, IntToStr</para>
    /// <para>Complexity: 10 (cyclomatic, outer body), 19 lines (full implementation)</para>
    /// <para>Reads: FStores</para>
    /// <seealso cref="DRagLint.Index.LibraryOracle.IsRootAncestorName"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.NormalizeTypeLeaf"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.DeclaringMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.HelpersDeclare"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function CandProvesAbsent(const ACand: TLibCand; const AMember: string; const AProjectStore: ISymbolStore): Boolean;
    /// <param name="AStore"><!-- drag-lint:auto type -->Integer</param>
    /// <param name="AId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto -->string -- Observed: IntToStr(AStore) + '#' +
    /// IntToStr(AId).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.Kids (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.LibraryUses (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.UnitStemOf (DRagLint.Index.LibraryOracle.pas)</para>
    /// <para>Calls: IntToStr</para>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Bind"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.BindBare"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.BindHead"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Key(AStore: Integer; AId: Int64): string;
    /// <param name="AStore"><!-- drag-lint:auto type -->Integer</param>
    /// <param name="AFileId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto -->string -- Observed:
    /// LowerCase(ChangeFileExt(ExtractFileName(FStores[AStore].GetFilePath(AFileId)),
    /// '')).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.LibraryOracle.TLibraryOracle.Collect (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.Collect.Add (DRagLint.Index.LibraryOracle.pas) ?, DRagLint.Index.LibraryOracle.TLibraryOracle.HelperCands (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.LibraryUses (DRagLint.Index.LibraryOracle.pas)</para>
    /// <para>Calls: ChangeFileExt, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Index.LibraryOracle.TLibraryOracle.Key, ExtractFileName, LowerCase</para>
    /// <para>Reads: FStems, FStores</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Key"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Bind"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function UnitStemOf(AStore: Integer; AFileId: Int64): string;
    /// <param name="AStore"><!-- drag-lint:auto type -->Integer</param>
    /// <param name="AFileId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;string&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.LibraryOracle.TLibraryOracle.BindHead (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.IsDynArrayType (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.StepPending (DRagLint.Index.LibraryOracle.pas)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.GetUnitUsesForFile, DRagLint.Index.LibraryOracle.TLibraryOracle.Key, DRagLint.Index.LibraryOracle.TLibraryOracle.UnitStemOf, LowerCase</para>
    /// <para>Reads: FFileUses, FStores</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetUnitUsesForFile"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Key"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.UnitStemOf"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function LibraryUses(AStore: Integer; AFileId: Int64): TArray<string>;
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AKinds"><!-- drag-lint:auto type -->TOracleKindSet</param>
    /// <param name="AFollowAlias"><!-- drag-lint:auto type -->Boolean</param>
    /// <returns><!-- drag-lint:auto -->TArray&lt;TLibCand&gt; -- Observed: [].</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.LibraryOracle.TLibraryOracle.Cached (DRagLint.Index.LibraryOracle.pas)</para>
    /// <para>Calls: Default, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName, DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById, DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors, DRagLint.Index.LibraryOracle.TLibraryOracle.Collect.Add, DRagLint.Index.LibraryOracle.TLibraryOracle.UnitStemOf, LowerCase, SameText</para>
    /// <para>Complexity: 12 (cyclomatic, outer body), 57 lines (full implementation)</para>
    /// <para>Reads: FStores</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Collect.Add"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.UnitStemOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Collect(const AName: string; AKinds: TOracleKindSet; AFollowAlias: Boolean): TArray<TLibCand>;
    /// <param name="ACache"><!-- drag-lint:auto type -->TDictionary&lt;string, TArray&lt;TLibCand&gt;&gt;</param>
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AKinds"><!-- drag-lint:auto type -->TOracleKindSet</param>
    /// <param name="AFollowAlias"><!-- drag-lint:auto type -->Boolean</param>
    /// <returns><!-- drag-lint:auto -->TArray&lt;TLibCand&gt; -- Observed: Collect(AName,
    /// AKinds, AFollowAlias).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.BindBare (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.BindHead (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.ImplicitRootMember (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.IsDynArrayType (DRagLint.Index.LibraryOracle.pas) (+4 more)</para>
    /// <para>Calls: DRagLint.Index.LibraryOracle.TLibraryOracle.Collect, LowerCase</para>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Collect"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Bind"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.BindBare"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Cached(ACache: TDictionary<string, TArray<TLibCand>>; const AName: string;
      AKinds: TOracleKindSet; AFollowAlias: Boolean): TArray<TLibCand>;
    /// <param name="ACands"><!-- drag-lint:auto type -->const TArray&lt;TLibCand&gt;</param>
    /// <param name="AUses"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
    /// <param name="ACand"><!-- drag-lint:auto type -->out TLibCand</param>
    /// <param name="AReason"><!-- drag-lint:auto type -->out string</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False; True; Hits = 1.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.LibraryOracle.TLibraryOracle.BindHead (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.PickType (DRagLint.Index.LibraryOracle.pas)</para>
    /// <para>Calls: Default, DRagLint.Index.LibraryOracle.InUses</para>
    /// <para>Mutates: AReason (out), ACand (out)</para>
    /// <seealso cref="DRagLint.Index.LibraryOracle.InUses"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Bind"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.BindBare"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Pick(const ACands: TArray<TLibCand>; const AUses: TArray<string>; out ACand: TLibCand;
      out AReason: string): Boolean;
    /// <param name="ATypeText"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AUses"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
    /// <param name="ACand"><!-- drag-lint:auto type -->out TLibCand</param>
    /// <param name="AReason"><!-- drag-lint:auto type -->out string</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False; Pick(Cached(FTypes,
    /// Leaf, TYPE_KINDS, True), AUses, ACand, AReason).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.LibraryOracle.TLibraryOracle.BindBare (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.BindHead (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.PickTypeOrHelper (DRagLint.Index.LibraryOracle.pas)</para>
    /// <para>Calls: Default, DRagLint.Index.LibraryOracle.NormalizeTypeLeaf, DRagLint.Index.LibraryOracle.TLibraryOracle.Cached, DRagLint.Index.LibraryOracle.TLibraryOracle.Pick</para>
    /// <para>Reads: FTypes</para>
    /// <para>Mutates: ACand (out), AReason (out)</para>
    /// <seealso cref="DRagLint.Index.LibraryOracle.NormalizeTypeLeaf"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Cached"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Pick"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function PickType(const ATypeText: string; const AUses: TArray<string>; out ACand: TLibCand;
      out AReason: string): Boolean;
    /// <param name="AStore"><!-- drag-lint:auto type -->Integer</param>
    /// <param name="AId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto -->TArray&lt;TSymbol&gt; -- Observed:
    /// FStores[AStore].FindAllChildSymbols(AId).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.LibraryOracle.TLibraryOracle.DeclaringMember (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.ImplicitRootMember (DRagLint.Index.LibraryOracle.pas)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindAllChildSymbols, DRagLint.Index.LibraryOracle.TLibraryOracle.Key</para>
    /// <para>Reads: FKids, FStores</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindAllChildSymbols"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Key"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Bind"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Kids(AStore: Integer; AId: Int64): TArray<TSymbol>;
    /// <param name="AStore"><!-- drag-lint:auto type -->Integer</param>
    /// <param name="AId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto -->TArray&lt;TTypeAncestor&gt; -- Observed:
    /// FStores[AStore].GetTransitiveAncestors(AId).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.LibraryOracle.TLibraryOracle.CandProvesAbsent (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.Collect (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.DeclaringMember (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.ImplicitRootMember (DRagLint.Index.LibraryOracle.pas)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.GetTransitiveAncestors, DRagLint.Index.LibraryOracle.TLibraryOracle.Key</para>
    /// <para>Reads: FAncestors, FStores</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetTransitiveAncestors"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Key"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Bind"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.BindBare"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Ancestors(AStore: Integer; AId: Int64): TArray<TTypeAncestor>;
    /// <param name="ACand"><!-- drag-lint:auto type -->const TLibCand</param>
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AHit"><!-- drag-lint:auto type -->out TSymbol</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: True;
    /// ImplicitRootMember(ACand, AName, AHit).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.BindBare (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.BindHead (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.CandProvesAbsent (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.MemberOf (DRagLint.Index.LibraryOracle.pas) (+1 more)</para>
    /// <para>Calls: Default, DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors, DRagLint.Index.LibraryOracle.TLibraryOracle.ImplicitRootMember, DRagLint.Index.LibraryOracle.TLibraryOracle.Kids, SameText</para>
    /// <para>Mutates: AHit (out)</para>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.ImplicitRootMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Kids"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Bind"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function DeclaringMember(const ACand: TLibCand; const AName: string; out AHit: TSymbol): Boolean;
    /// <summary><!-- drag-lint:auto sum -->The last step of a class's chain, which no
    /// ancestor row records when the class has no written parent: TObject. Only for a
    /// class (an interface or record has no such root) and only when every written
    /// ancestor resolved: an unknown parent may redeclare the member.</summary>
    /// <param name="ACand"><!-- drag-lint:auto type -->const TLibCand</param>
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AHit"><!-- drag-lint:auto type -->out TSymbol</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False; True.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.LibraryOracle.TLibraryOracle.DeclaringMember (DRagLint.Index.LibraryOracle.pas)</para>
    /// <para>Calls: Default, DRagLint.Index.LibraryOracle.IsRootAncestorName, DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors, DRagLint.Index.LibraryOracle.TLibraryOracle.Cached, DRagLint.Index.LibraryOracle.TLibraryOracle.Kids, SameText</para>
    /// <para>Reads: FTypes</para>
    /// <para>Mutates: AHit (out)</para>
    /// <seealso cref="DRagLint.Index.LibraryOracle.IsRootAncestorName"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Cached"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Kids"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ImplicitRootMember(const ACand: TLibCand; const AName: string; out AHit: TSymbol): Boolean;
    /// <summary><!-- drag-lint:auto sum -->One target whichever candidate the type name
    /// means: every candidate is a class and each declares the member under the same
    /// qualified name. Only the candidates AUses can see are asked when any is visible (a
    /// unit the file does not use cannot be what the name means -- wave-146 b7 leftover,
    /// `List.Free` on TList&lt;T&gt; beside Spring's unseen TList); with none visible,
    /// every candidate is asked as before.</summary>
    /// <param name="ATypeText"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AMember"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AKind"><!-- drag-lint:auto type -->TExternalKind</param>
    /// <param name="AUses"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
    /// <returns><!-- drag-lint:auto -->string -- Observed: ''; Hit.QualifiedName.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.LibraryOracle.TLibraryOracle.Bind (DRagLint.Index.LibraryOracle.pas)</para>
    /// <para>Calls: DRagLint.Index.LibraryOracle.NormalizeTypeLeaf, DRagLint.Index.LibraryOracle.TLibraryOracle.Cached, DRagLint.Index.LibraryOracle.TLibraryOracle.DeclaringMember, DRagLint.Index.LibraryOracle.TLibraryOracle.VisibleOf, SameText</para>
    /// <para>Reads: FTypes</para>
    /// <seealso cref="DRagLint.Index.LibraryOracle.NormalizeTypeLeaf"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Cached"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.DeclaringMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.VisibleOf"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function AgreedMember(const ATypeText, AMember: string; AKind: TExternalKind; const AUses: TArray<string>): string;
    /// <param name="ACands"><!-- drag-lint:auto type -->const TArray&lt;TLibCand&gt;</param>
    /// <param name="AUses"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TLibCand&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.BindHead (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.IsDynArrayType (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.NamesVisibleType (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.PickTypeOrHelper (DRagLint.Index.LibraryOracle.pas) (+1 more)</para>
    /// <para>Calls: DRagLint.Index.LibraryOracle.InUses</para>
    /// <seealso cref="DRagLint.Index.LibraryOracle.InUses"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Bind"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.BindBare"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function VisibleOf(const ACands: TArray<TLibCand>; const AUses: TArray<string>): TArray<TLibCand>;
    /// <summary><!-- drag-lint:auto sum -->How many qualified routines named AMember live
    /// in a unit the file uses whose name is AChain, written whole (`System.SysUtils`) or
    /// as the suffix InUses accepts (`SysUtils`).</summary>
    /// <param name="AChain"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AMember"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AUses"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
    /// <param name="AQName"><!-- drag-lint:auto type -->out string</param>
    /// <returns><!-- drag-lint:auto type -->Integer</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.LibraryOracle.TLibraryOracle.BindHead (DRagLint.Index.LibraryOracle.pas)</para>
    /// <para>Calls: DRagLint.Index.LibraryOracle.TLibraryOracle.Cached, DRagLint.Index.LibraryOracle.TLibraryOracle.VisibleOf, LowerCase</para>
    /// <para>Reads: FRoutines</para>
    /// <para>Mutates: AQName (out)</para>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Cached"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.VisibleOf"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Bind"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function UnitRoutine(const AChain, AMember: string; const AUses: TArray<string>; out AQName: string): Integer;
    /// <param name="ACand"><!-- drag-lint:auto type -->var TLibCand</param>
    /// <param name="APending"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AHelperUses"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
    /// <param name="AReason"><!-- drag-lint:auto type -->out string</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False; True.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.LibraryOracle.TLibraryOracle.Bind (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.BindHead.Finish (DRagLint.Index.LibraryOracle.pas) ?</para>
    /// <para>Calls: DRagLint.Index.LibraryOracle.MemberTypeText, DRagLint.Index.LibraryOracle.TLibraryOracle.DeclaringMember, DRagLint.Index.LibraryOracle.TLibraryOracle.LibraryUses, DRagLint.Index.LibraryOracle.TLibraryOracle.PickTypeOrHelper, Trim</para>
    /// <para>Mutates: AReason (out), ACand (var)</para>
    /// <seealso cref="DRagLint.Index.LibraryOracle.MemberTypeText"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.DeclaringMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.LibraryUses"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.PickTypeOrHelper"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function StepPending(var ACand: TLibCand; const APending: string; const AHelperUses: TArray<string>;
      out AReason: string): Boolean;
    /// <param name="ACand"><!-- drag-lint:auto type -->const TLibCand</param>
    /// <param name="AMember"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AKind"><!-- drag-lint:auto type -->TExternalKind</param>
    /// <param name="AReason"><!-- drag-lint:auto type -->out string</param>
    /// <returns><!-- drag-lint:auto -->string -- Observed: Hit.QualifiedName; ''.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.LibraryOracle.TLibraryOracle.Bind (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.BindHead.Finish (DRagLint.Index.LibraryOracle.pas) ?</para>
    /// <para>Calls: DRagLint.Index.LibraryOracle.TLibraryOracle.DeclaringMember</para>
    /// <para>Mutates: AReason (out)</para>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.DeclaringMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Bind"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.BindBare"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function MemberOf(const ACand: TLibCand; const AMember: string; AKind: TExternalKind;
      out AReason: string): string;
    /// <param name="AResult"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AReason"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->string -- Observed: AResult.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.LibraryOracle.TLibraryOracle.Bind (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.BindBare (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.BindHead (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.BindIntrinsic (DRagLint.Index.LibraryOracle.pas)</para>
    /// <para>Reads: FStats   Writes: FLastKind</para>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Bind"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.BindBare"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.BindHead"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Count(const AResult, AReason: string): string;
  public
    /// <param name="AStores">The open extra stores; the oracle does not own them.</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoContext (DRagLint.CLI.pas), DRagLint.CLI.DoFindCallees (DRagLint.CLI.pas), DRagLint.Index.CallResolver.TCallResolver.Create (DRagLint.Index.CallResolver.pas), DRagLint.Lint.OpaqueToAnalysis.TOpaqueScan.Create (DRagLint.Lint.OpaqueToAnalysis.pas)</para>
    /// <para>constructor</para>
    /// <para>Writes: FStores, FTypes, FValues, FRoutines, FKids, FAncestors, FStems, FFileUses (+3 more)</para>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Bind"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.BindBare"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.BindHead"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create(const AStores: TArray<ISymbolStore>);
    /// <summary>Frees the caches; the stores are the caller's.</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: FAliases, FHelperTypes, FHelperMembers, FFileUses, FStems, FAncestors, FKids, FRoutines (+2 more)</para>
    /// <para>Directives: override</para>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Bind"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.BindBare"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.BindHead"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    destructor Destroy; override;
    /// <summary>Binds AMember on the type named ATypeText, after stepping the pending segments.</summary>
    /// <param name="ATypeText">spec s.4.1 value without the pending segments; '' for a bare call.</param>
    /// <param name="APending">Dot-joined pending segments or ''.</param>
    /// <param name="AMember">The called member name.</param>
    /// <param name="AKind">Site kind; ekBareCall delegates to BindBare with no scope type.</param>
    /// <param name="AUsesUnits">Lower-cased unit names the referencing file uses (both sections + the .dpr).</param>
    /// <param name="AReason">ambiguous-type|no-member|no-store|no-type when the result is ''.</param>
    /// <returns>The qualified name, or '' with AReason set.</returns>
    /// <remarks>
    /// A type name Pick cannot choose still answers when every candidate is a class
    /// and all of them give the SAME member (`Acc.Free` on TList): the choice cannot matter.
    /// A name no library type answers (a built-in such as string or Boolean, at the head or
    /// as a pending segment's type) is answered by its one library helper visible from the
    /// calling file (`S.Split` -> TStringHelper.Split); two visible helpers decline.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.EmitExternalCallees (DRagLint.CLI.pas), DRagLint.Context.Bundler.OracleTarget (DRagLint.Context.Bundler.pas), DRagLint.Index.CallResolver.TCallResolver.BindExternally (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Calls: DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember, DRagLint.Index.LibraryOracle.TLibraryOracle.BindBare, DRagLint.Index.LibraryOracle.TLibraryOracle.Count, DRagLint.Index.LibraryOracle.TLibraryOracle.MemberOf, DRagLint.Index.LibraryOracle.TLibraryOracle.PickTypeOrHelper, DRagLint.Index.LibraryOracle.TLibraryOracle.StepPending</para>
    /// <para>Reads: FStores</para>
    /// <para>Mutates: AReason (out)</para>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.BindBare"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Count"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.MemberOf"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.PickTypeOrHelper"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Bind(const ATypeText, APending, AMember: string; AKind: TExternalKind;
      const AUsesUnits: TArray<string>; out AReason: string): string;
    /// <summary>E-RECV-UNDECIDABLE D08: binds a dynamic-array constructor call whose receiver
    /// is a generic type text no head rung reads (`TArray&lt;Integer&gt;.Create(1)`) to the
    /// synthetic INTRINSIC_DYNARRAY_CREATE.</summary>
    /// <param name="AReceiver">The call's receiver text as written.</param>
    /// <param name="AMember">The called member; only `Create` binds.</param>
    /// <param name="AUsesUnits">The calling file's used units.</param>
    /// <returns>INTRINSIC_DYNARRAY_CREATE, or '' (and no counter moves) when it is not one.</returns>
    /// <remarks>
    /// A hit counts as Stats.Intrinsic and sets LastKind to EXTERNAL_KIND_INTRINSIC.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.BindExternally (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Calls: Copy, DRagLint.Index.LibraryOracle.IsIdent, DRagLint.Index.LibraryOracle.TLibraryOracle.Count, DRagLint.Index.LibraryOracle.TLibraryOracle.IsDynArrayType, Pos, SameText</para>
    /// <para>Returns: ''; Count(INTRINSIC_DYNARRAY_CREATE, R_INTRINSIC)</para>
    /// <para>Reads: FStores   Writes: FLastKind</para>
    /// <seealso cref="DRagLint.Index.LibraryOracle.IsIdent"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Count"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.IsDynArrayType"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function BindIntrinsic(const AReceiver, AMember: string; const AUsesUnits: TArray<string>): string;
    /// <summary>The kind of the last non-empty answer of Bind / BindHead / BindBare /
    /// BindIntrinsic: '' (a routine), EXTERNAL_KIND_INDIRECT or EXTERNAL_KIND_INTRINSIC.</summary>
    /// <remarks>Read it right after the call whose answer it describes; the next call resets it.</remarks>
    property LastKind: string read FLastKind;
    /// <summary>Binds a receiver whose HEAD identifier no project rung typed: in Delphi's
    /// order, a member inherited by the enclosing class from AScopeType, a routine of a used
    /// unit the whole chain names (`System.SysUtils.DeleteFile`), a library type, a library
    /// unit-level var / const, then `Unit.Name.TType` as a unit-qualified type.</summary>
    /// <param name="AChain">The receiver, a dot-joined identifier chain (`CodeSite`, `TEncoding.UTF8`).</param>
    /// <param name="AMember">The called member name.</param>
    /// <param name="AKind">ekCall or ekMemberAccess.</param>
    /// <param name="AUsesUnits">As for Bind.</param>
    /// <param name="AScopeType">The enclosing class's first library ancestor name, or ''.</param>
    /// <param name="AReason">As for Bind.</param>
    /// <param name="ATypeText">The receiver's type text as the head typed it, leaf-normalised,
    /// with the pending segments appended -- the value to persist; '' when the head was not typed.</param>
    /// <returns>The qualified name, or '' with AReason set.</returns>
    /// <remarks>
    /// A type in a unit the file does not use cannot be what the head names: when a
    /// library var / const of the name IS visible, the value rung answers, and only a visible
    /// value (`Application` beside typelib interfaces of that name). Without a visible value
    /// the type rung behaves as it always did. Several visible values decline.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.BindExternally (DRagLint.Index.CallResolver.pas), DRagLint.Lint.OpaqueToAnalysis.TOpaqueScan.JudgeHead (DRagLint.Lint.OpaqueToAnalysis.pas)</para>
    /// <para>Calls: DRagLint.Index.LibraryOracle.MemberTypeText, DRagLint.Index.LibraryOracle.TLibraryOracle.BindHead.Finish, DRagLint.Index.LibraryOracle.TLibraryOracle.Cached, DRagLint.Index.LibraryOracle.TLibraryOracle.Count, DRagLint.Index.LibraryOracle.TLibraryOracle.DeclaringMember, DRagLint.Index.LibraryOracle.TLibraryOracle.IsDynArrayType, DRagLint.Index.LibraryOracle.TLibraryOracle.LibraryUses, DRagLint.Index.LibraryOracle.TLibraryOracle.Pick, DRagLint.Index.LibraryOracle.TLibraryOracle.PickType, DRagLint.Index.LibraryOracle.TLibraryOracle.UnitRoutine (+6 more)</para>
    /// <para>Returns: ''; Count('', R_NO_MEMBER); Count(Finish(C.Name), AReason); Count('', Why); Count(INTRINSIC_DYNARRAY_CREATE, R_INTRINSIC); Count('', R_NO_TYPE)</para>
    /// <para>Complexity: 24 (cyclomatic, outer body), 86 lines (full implementation)</para>
    /// <para>Reads: FStores, FValues, FTypes</para>
    /// <para>Mutates: AReason (out), ATypeText (out)</para>
    /// <seealso cref="DRagLint.Index.LibraryOracle.MemberTypeText"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.BindHead.Finish"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Cached"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Count"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.DeclaringMember"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function BindHead(const AChain, AMember: string; AKind: TExternalKind; const AUsesUnits: TArray<string>;
      const AScopeType: string; out AReason: string; out ATypeText: string): string;
    /// <summary>Binds a BARE call: a method the enclosing class inherits from AScopeType, else
    /// exactly one library unit-level routine of the name whose unit the file uses.</summary>
    /// <param name="AName">The called name.</param>
    /// <param name="AUsesUnits">As for Bind; the System unit is always visible.</param>
    /// <param name="AScopeType">The enclosing class's first library ancestor name, or ''.</param>
    /// <param name="AReason">As for Bind.</param>
    /// <param name="AOwnUses">The calling file's OWN uses (both sections, lower-cased), or nil.
    /// When given, the free-routine rung is decided on AOwnUses + System / SysInit first: a unit
    /// sees what its uses clauses name, not what the program file uses (149 RB2: the ORM3 .dpr's
    /// EurekaLog units declare IntToStr / FreeAndNil / UpperCase and made every unit's call
    /// ambiguous). Only when that set holds NO routine of the name does AUsesUnits decide, as
    /// before (a uses list the parser read short still binds).</param>
    /// <returns>The qualified name, or '' with AReason set.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.BindExternally (DRagLint.Index.CallResolver.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.Bind (DRagLint.Index.LibraryOracle.pas), DRagLint.Lint.OpaqueToAnalysis.TOpaqueScan.JudgeBare (DRagLint.Lint.OpaqueToAnalysis.pas)</para>
    /// <para>Calls: DRagLint.Index.LibraryOracle.InUses, DRagLint.Index.LibraryOracle.TLibraryOracle.Cached, DRagLint.Index.LibraryOracle.TLibraryOracle.Count, DRagLint.Index.LibraryOracle.TLibraryOracle.DeclaringMember, DRagLint.Index.LibraryOracle.TLibraryOracle.PickType</para>
    /// <para>Reads: FStores, FRoutines</para>
    /// <para>Mutates: AReason (out)</para>
    /// <seealso cref="DRagLint.Index.LibraryOracle.InUses"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Cached"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Count"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.DeclaringMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.PickType"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function BindBare(const AName: string; const AUsesUnits: TArray<string>; const AScopeType: string;
      out AReason: string; const AOwnUses: TArray<string> = nil): string;
    /// <summary>True only when the library PROVES that a type named ATypeText cannot supply
    /// AMember, so a `with` target descending from it does not hide an outer AMember.</summary>
    /// <param name="ATypeText">The ancestor's name as the project wrote it; generics and unit
    /// qualifier are ignored.</param>
    /// <param name="AMember">The bare name being looked up.</param>
    /// <param name="AProjectStore">The project's store: a helper the project declares on a
    /// library type counts as a member. May be nil.</param>
    /// <returns>True when at least one library type has that leaf name and EVERY one of them
    /// has a chain wholly inside its store (TObject / IInterface / IUnknown excepted) that
    /// declares no AMember and carries no helper declaring it. False for anything else: no
    /// store, no such type, a chain leaving the library, a declaration, a helper.</returns>
    /// <remarks>
    /// Every same-leaf candidate must agree, instead of Pick's uses-based choice,
    /// because the ancestor's name was written in the DECLARING unit of a type possibly far
    /// from the site. Helper targets match by exact name (type_helpers.target_name). Does not
    /// touch the outcome counters: it binds nothing.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.LibraryProvesAbsent (DRagLint.Index.CallResolver.pas)</para>
    /// <para>Calls: DRagLint.Index.LibraryOracle.NormalizeTypeLeaf, DRagLint.Index.LibraryOracle.TLibraryOracle.Cached, DRagLint.Index.LibraryOracle.TLibraryOracle.CandProvesAbsent</para>
    /// <para>Reads: FStores, FTypes</para>
    /// <seealso cref="DRagLint.Index.LibraryOracle.NormalizeTypeLeaf"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Cached"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.CandProvesAbsent"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.AgreedMember"/>
    /// <seealso cref="DRagLint.Index.LibraryOracle.TLibraryOracle.Ancestors"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function MemberProvablyAbsent(const ATypeText, AMember: string; const AProjectStore: ISymbolStore): Boolean;
    /// <summary>Outcome counters since Create.</summary>
    property Stats: TOracleStats read FStats;
    /// <summary>149 RB2 item 3: the calling file's OWN uses (lower-cased, both sections), set by
    /// the resolver around one external binding and cleared after it; nil = not known.</summary>
    /// <remarks>When set, Pick re-decides a tie (2+ visible candidates) on these + System /
    /// SysInit: a unit sees what its own uses clauses name, not what the program file uses
    /// (the ORM3 .dpr's EurekaLog units). It never overrides a single visible answer, and an
    /// own-uses tie stays ambiguous. Not thread-safe: one resolver thread owns the oracle.</remarks>
    property OwnUses: TArray<string> read FOwnUses write FOwnUses;  end;

/// <summary>A declared type text reduced to the name the oracle and refs.receiver_type_text
/// carry: generic arguments and unit qualifier stripped, a leading '^' kept.</summary>
/// <param name="ATypeText">A declaration's type text, e.g. 'System.Classes.TStream', 'TList&lt;T&gt;'.</param>
/// <returns>The leaf (`TStream`, `TList`, `^TRec`), or '' when the text is not a plain type
/// name (`array of T`, `class of T`, a set, a procedural type).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.TargetStaticType (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.TypeOfCallChain.ChainStep (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.TypeOfFunctionResult/3 (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.TypeOfInheritedReceiver (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.TypeOfSelectorChain (DRagLint.Index.CallResolver.pas) (+8 more)</para>
/// <para>Calls: Copy, DRagLint.Index.LibraryOracle.IsIdent, Pos, Trim</para>
/// <seealso cref="DRagLint.Index.LibraryOracle.IsIdent"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function NormalizeTypeLeaf(const ATypeText: string): string;

/// <summary>True for an ancestor every class or interface has whether or not it is indexed.</summary>
/// <param name="AName">The ancestor's name as written, possibly unit-qualified.</param>
/// <returns>True for TObject, IInterface and IUnknown, whose members the caller answers from
/// its own floor list.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Index.CallResolver.TCallResolver.LibraryProvesAbsent (DRagLint.Index.CallResolver.pas), DRagLint.Index.CallResolver.TCallResolver.SurfaceComplete (DRagLint.Index.CallResolver.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.CandProvesAbsent (DRagLint.Index.LibraryOracle.pas), DRagLint.Index.LibraryOracle.TLibraryOracle.ImplicitRootMember (DRagLint.Index.LibraryOracle.pas)</para>
/// <para>Calls: Copy, LastDelimiter, LowerCase</para>
/// <para>Returns: (N = 'tobject') or (N = 'iinterface') or (N = 'iunknown')</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsRootAncestorName(const AName: string): Boolean;

const
  /// <summary>The class every class with no written parent descends from.</summary>
  IMPLICIT_ROOT_CLASS = 'TObject';

implementation

const
  IMPLICIT_ROOT_UNIT = 'system';
  OK_CALL   : TOracleKindSet = [skProcedure, skFunction, skMethod, skConstructor, skDestructor];
  OK_ACCESS : TOracleKindSet = [skProcedure, skFunction, skMethod, skConstructor, skDestructor, skProperty, skField];
  TYPE_KINDS: TOracleKindSet = [skClass, skInterface, skRecord];
  VALUE_KINDS: TOracleKindSet = [skVarDecl, skConstDecl];
  ROUTINE_KINDS: TOracleKindSet = [skProcedure, skFunction];
  { What a pending segment / an inherited head may be: a value or a parenless function. }
  STEP_KINDS: TOracleKindSet = [skField, skProperty, skMethod, skFunction];
  R_AMBIGUOUS = 'ambiguous-type';
  R_NO_MEMBER = 'no-member';
  R_NO_STORE  = 'no-store';
  R_NO_TYPE   = 'no-type';
  R_INTRINSIC = 'intrinsic';   // D08: no declaration exists (`TBytes.Create`)
  R_LATE_BOUND= 'late-bound';  // D10: the routine is chosen at run time (an event property)
  { How deep IsDynArrayType follows an alias chain (`TBytes = TArray<Byte>` -> `array of T`). }
  MAX_ALIAS_HOPS = 3;

function IsIdent(const S: string): Boolean;
begin
  Result:= S <> '';
  for var i:= 1 to Length(S) do
    if not (CharInSet(S[i], ['A'..'Z', 'a'..'z', '_']) or ((i > 1) and CharInSet(S[i], ['0'..'9']))) then Exit(False);
end;

function NormalizeTypeLeaf(const ATypeText: string): string;
var
  Ptr: string;
begin
  Result:= Trim(ATypeText);
  Ptr   := '';
  if Result.StartsWith('^') then
  begin
    Ptr   := '^';
    Result:= Trim(Copy(Result, 2, MaxInt));
  end;
  var Eq: Integer:= Pos('=', Result);
  if Eq > 0 then Result:= Trim(Copy(Result, 1, Eq - 1));
  var Lt: Integer:= Pos('<', Result);
  if Lt > 0 then Result:= Trim(Copy(Result, 1, Lt - 1));
  for var Seg: string in Result.Split(['.']) do
    if not IsIdent(Trim(Seg)) then Exit('');
  var Dot: Integer:= Result.LastDelimiter('.');
  if Dot >= 0 then Result:= Trim(Copy(Result, Dot + 2, MaxInt));
  Result:= if Result = '' then '' else Ptr + Result;
end;

{ The declared type text a member stands for: a field's type, a property's type
  (after any index parameters), a function's return type; '' for a procedure. }
function MemberTypeText(const AMember: TSymbol): string;
var
  S    : string ;
  Depth: Integer;
  K    : Integer;
begin
  S:= Trim(AMember.Signature);
  if AMember.Kind = skField then Exit(S);
  if (S <> '') and CharInSet(S[1], ['(', '[']) then
  begin
    Depth:= 0;
    for K:= 1 to Length(S) do
    begin
      if CharInSet(S[K], ['(', '[']) then Inc(Depth)
      else if CharInSet(S[K], [')', ']']) then
      begin
        Dec(Depth);
        if Depth = 0 then
        begin
          S:= TrimLeft(Copy(S, K + 1, MaxInt));
          Break;
        end;
      end;
    end;
    if Depth <> 0 then Exit('');
  end;
  if (S <> '') and (S[1] = ':') then S:= Trim(Copy(S, 2, MaxInt))
  else if AMember.Kind <> skProperty then Exit('');
  K:= Pos(';', S);
  if K > 0 then S:= Trim(Copy(S, 1, K - 1));
  K:= Pos(' ', S);
  if K > 0 then S:= Copy(S, 1, K - 1); // `TFoo read GetFoo write SetFoo`
  Result:= S;
end;

function IsRootAncestorName(const AName: string): Boolean;
begin
  var N: string:= LowerCase(AName);
  if LastDelimiter('.', N) > 0 then N:= Copy(N, LastDelimiter('.', N) + 1, MaxInt);
  Result:= (N = 'tobject') or (N = 'iinterface') or (N = 'iunknown');
end;

function InUses(const AStem: string; const AUses: TArray<string>): Boolean;
begin
  for var U: string in AUses do
    if (U = AStem) or AStem.EndsWith('.' + U) then Exit(True);
  Result:= False;
end;

constructor TLibraryOracle.Create(const AStores: TArray<ISymbolStore>);
begin
  inherited Create;
  FStores   := AStores;
  FTypes    := TDictionary<string, TArray<TLibCand>>.Create;
  FValues   := TDictionary<string, TArray<TLibCand>>.Create;
  FRoutines := TDictionary<string, TArray<TLibCand>>.Create;
  FKids     := TDictionary<string, TArray<TSymbol>>.Create;
  FAncestors:= TDictionary<string, TArray<TTypeAncestor>>.Create;
  FStems    := TDictionary<string, string>.Create;
  FFileUses := TDictionary<string, TArray<string>>.Create;
  FHelperMembers:= TDictionary<string, string>.Create;
  FHelperTypes  := TDictionary<string, TArray<TLibCand>>.Create;
  FAliases      := TDictionary<string, TArray<TLibCand>>.Create;
end;

destructor TLibraryOracle.Destroy;
begin
  FAliases.Free;
  FHelperTypes.Free;
  FHelperMembers.Free;
  FFileUses.Free;
  FStems.Free;
  FAncestors.Free;
  FKids.Free;
  FRoutines.Free;
  FValues.Free;
  FTypes.Free;
  inherited Destroy;
end;

function TLibraryOracle.Key(AStore: Integer; AId: Int64): string;
begin
  Result:= IntToStr(AStore) + '#' + IntToStr(AId);
end;

function TLibraryOracle.UnitStemOf(AStore: Integer; AFileId: Int64): string;
begin
  var K: string:= Key(AStore, AFileId);
  if FStems.TryGetValue(K, Result) then Exit;
  Result:= LowerCase(ChangeFileExt(ExtractFileName(FStores[AStore].GetFilePath(AFileId)), ''));
  FStems.Add(K, Result);
end;

function TLibraryOracle.LibraryUses(AStore: Integer; AFileId: Int64): TArray<string>;
begin
  var K: string:= Key(AStore, AFileId);
  if FFileUses.TryGetValue(K, Result) then Exit;
  Result:= [UnitStemOf(AStore, AFileId), 'system', 'sysinit'];
  for var U: TUnitUse in FStores[AStore].GetUnitUsesForFile(AFileId) do
    Result:= Result + [LowerCase(U.UnitName)];
  FFileUses.Add(K, Result);
end;

function TLibraryOracle.Collect(const AName: string; AKinds: TOracleKindSet;
  AFollowAlias: Boolean): TArray<TLibCand>;
var
  ByQName: TDictionary<string, Integer>;

  procedure Add(AStore: Integer; const S: TSymbol);
  var
    Ix: Integer;
  begin
    if ByQName.TryGetValue(LowerCase(S.QualifiedName), Ix) then
    begin
      if Result[Ix].Store = AStore then Result[Ix].Ids:= Result[Ix].Ids + [S.Id];
      Exit;
    end;
    var C: TLibCand:= Default(TLibCand);
    C.Store   := AStore;
    C.Ids     := [S.Id];
    C.QName   := S.QualifiedName;
    C.Name    := S.Name;
    C.UnitStem:= UnitStemOf(AStore, S.FileId);
    C.FileId  := S.FileId;
    C.Kind    := S.Kind;
    C.Sig     := S.Signature;
    ByQName.Add(LowerCase(S.QualifiedName), Length(Result));
    Result:= Result + [C];
  end;

begin
  Result := [];
  ByQName:= TDictionary<string, Integer>.Create;
  try
    for var Si:= 0 to High(FStores) do
    begin
      if FStores[Si] = nil then Continue;
      for var S: TSymbol in FStores[Si].FindSymbolsByExactName(AName) do
      begin
        if not SameText(S.Name, AName) then Continue;
        { Unit level only: a nested `TOuter.TDataSet` is not what `TDataSet` names. }
        if not SameText(S.QualifiedName, UnitStemOf(Si, S.FileId) + '.' + S.Name) then Continue;
        if S.Kind in AKinds then Add(Si, S)
        else if AFollowAlias and (S.Kind = skTypeAlias) then
          for var A: TTypeAncestor in Ancestors(Si, S.Id) do
          begin
            { Followed ONCE, through the alias's own ordinal-0 edge; an alias
              whose target is not a class / record / interface is ignored. }
            if (A.Ordinal = 0) and A.Resolved and (A.SymbolId > 0) then
            begin
              var T: TSymbol:= FStores[Si].GetSymbolById(A.SymbolId);
              if T.Kind in AKinds then Add(Si, T);
            end;
            Break;
          end;
      end;
    end;
  finally
    ByQName.Free;
  end;
end;

function TLibraryOracle.Cached(ACache: TDictionary<string, TArray<TLibCand>>; const AName: string;
  AKinds: TOracleKindSet; AFollowAlias: Boolean): TArray<TLibCand>;
begin
  var K: string:= LowerCase(AName);
  if ACache.TryGetValue(K, Result) then Exit;
  Result:= Collect(AName, AKinds, AFollowAlias);
  ACache.Add(K, Result);
end;

function TLibraryOracle.Pick(const ACands: TArray<TLibCand>; const AUses: TArray<string>;
  out ACand: TLibCand; out AReason: string): Boolean;
var
  Hits: Integer;
begin
  Result := False;
  AReason:= '';
  ACand  := Default(TLibCand);
  if Length(ACands) = 0 then
  begin
    AReason:= R_NO_TYPE;
    Exit;
  end;
  if Length(ACands) = 1 then
  begin
    ACand:= ACands[0];
    Exit(True);
  end;
  Hits:= 0;
  for var C: TLibCand in ACands do
    if InUses(C.UnitStem, AUses) then
    begin
      Inc(Hits);
      ACand:= C;
    end;
  { 149 RB2 item 3: a tie among the program-wide visible set is re-decided on the file's own uses. }
  if (Hits > 1) and (FOwnUses <> nil) then
  begin
    Hits:= 0;
    for var C: TLibCand in ACands do
      if InUses(C.UnitStem, FOwnUses + ['system', 'sysinit']) then
      begin
        Inc(Hits);
        ACand:= C;
      end;
    if Hits = 0 then Hits:= 2; // none of the tie is in the own uses: stays ambiguous
  end;
  Result:= Hits = 1;
  if not Result then
  begin
    AReason:= R_AMBIGUOUS;
    ACand  := Default(TLibCand);
  end;
end;

function TLibraryOracle.PickType(const ATypeText: string; const AUses: TArray<string>;
  out ACand: TLibCand; out AReason: string): Boolean;
begin
  var Leaf: string:= NormalizeTypeLeaf(ATypeText);
  if (Leaf = '') or Leaf.StartsWith('^') then
  begin
    ACand  := Default(TLibCand);
    AReason:= R_NO_TYPE;
    Exit(False);
  end;
  Result:= Pick(Cached(FTypes, Leaf, TYPE_KINDS, True), AUses, ACand, AReason);
end;

{ E-RECV-UNDECIDABLE D08: True when ATypeText names a dynamic array type: `TArray<X>` (the
  generic arguments do not matter) or a library alias whose every visible declaration is
  `array of ..`, directly or through at most MAX_ALIAS_HOPS further aliases
  (`TBytes = TArray<Byte>`). A name that is also a visible class / record / interface, or that
  no visible alias declares, is not one. }
{ A visible class / record / interface the type text can name: a text WITH generic arguments
  (`TArray<Integer>`) names only a generic declaration, so System.Generics.Collections' plain
  `TArray` class does not hide System's `TArray<T> = array of T`. }
function TLibraryOracle.NamesVisibleType(const AText, ALeaf: string; const AUses: TArray<string>): Boolean;
begin
  Result:= False;
  var Generic: Boolean:= AText.Contains('<');
  for var C: TLibCand in VisibleOf(Cached(FTypes, ALeaf, TYPE_KINDS, True), AUses) do
    if not Generic or (FStores[C.Store].GetSymbolById(C.Ids[0]).GenericParams <> '') then Exit(True);
end;

{ The candidates a UNIT-QUALIFIED text can mean (`SysUtils.TBytes` -> System.SysUtils's, as
  Spring writes it): declared in a unit whose name is the qualifier or ends with `.qualifier`.
  An unqualified text keeps every candidate. }
function TLibraryOracle.InQualifier(const AText: string; const ACands: TArray<TLibCand>): TArray<TLibCand>;
begin
  var Plain: string:= AText;
  var Lt: Integer:= Pos('<', Plain);
  if Lt > 0 then Plain:= Copy(Plain, 1, Lt - 1);
  var Dot: Integer:= Plain.LastIndexOf('.');
  if Dot < 0 then Exit(ACands);
  var Q: string:= LowerCase(Trim(Copy(Plain, 1, Dot)));
  Result:= [];
  for var C: TLibCand in ACands do
    if (C.UnitStem = Q) or C.UnitStem.EndsWith('.' + Q) then Result:= Result + [C];
end;

function TLibraryOracle.IsDynArrayType(const ATypeText: string; const AUses: TArray<string>;
  ADepth: Integer): Boolean;
begin
  var Text: string:= Trim(ATypeText);
  if Text.ToLower.StartsWith('array of') then Exit(True);
  var Leaf: string:= NormalizeTypeLeaf(Text);
  { Too deep, not a plain name, or a visible class / record / interface the text can name. }
  if (ADepth > MAX_ALIAS_HOPS) or (Leaf = '') or Leaf.StartsWith('^') or NamesVisibleType(Text, Leaf, AUses) then
    Exit(False);
  var Seen: TArray<TLibCand>:= InQualifier(Text, VisibleOf(Cached(FAliases, Leaf, [skTypeAlias], False), AUses));
  Result:= Length(Seen) > 0;
  for var C: TLibCand in Seen do
    Result:= Result and IsDynArrayType(C.Sig, LibraryUses(C.Store, C.FileId) + [IMPLICIT_ROOT_UNIT], ADepth + 1);
end;

function TLibraryOracle.BindIntrinsic(const AReceiver, AMember: string; const AUsesUnits: TArray<string>): string;
begin
  var Lt: Integer:= Pos('<', AReceiver);
  var GenericHead: Boolean:= (Lt > 1) and AReceiver.EndsWith('>') and IsIdent(Copy(AReceiver, 1, Lt - 1));
  Result   := '';
  FLastKind:= '';
  if (Length(FStores) > 0) and SameText(AMember, 'Create') and GenericHead
     and IsDynArrayType(AReceiver, AUsesUnits + [IMPLICIT_ROOT_UNIT, 'sysinit'], 0) then
    Result:= Count(INTRINSIC_DYNARRAY_CREATE, R_INTRINSIC);
end;

{ E-RECV-UNDECIDABLE D05: every library helper whose target is named ALeaf
  (`record helper for string` -> TStringHelper), one candidate per helper. }
function TLibraryOracle.HelperCands(const ALeaf: string): TArray<TLibCand>;
begin
  var K: string:= LowerCase(ALeaf);
  if FHelperTypes.TryGetValue(K, Result) then Exit;
  Result:= [];
  for var Si:= 0 to High(FStores) do
  begin
    if FStores[Si] = nil then Continue;
    for var H: THelperEdge in FStores[Si].FindHelpersOfType(ALeaf) do
    begin
      var S: TSymbol:= FStores[Si].GetSymbolById(H.HelperSymbolId);
      if S.Id <= 0 then Continue;
      var C: TLibCand:= Default(TLibCand);
      C.Store   := Si;
      C.Ids     := [S.Id];
      C.QName   := S.QualifiedName;
      C.Name    := S.Name;
      C.UnitStem:= UnitStemOf(Si, S.FileId);
      C.FileId  := S.FileId;
      C.Kind    := S.Kind;
      C.Sig     := S.Signature;
      Result:= Result + [C];
    end;
  end;
  FHelperTypes.Add(K, Result);
end;

{ A type name no library type answers may still have members: a built-in type's
  helper (`S.Split`, `B.ToString`). Only one helper per type is active in Delphi,
  so exactly one visible helper answers; two decline. The helper's scope is the
  CALLING file's (AHelperUses), whatever unit named the type. }
function TLibraryOracle.PickTypeOrHelper(const ATypeText: string; const ATypeUses, AHelperUses: TArray<string>;
  out ACand: TLibCand; out AReason: string): Boolean;
begin
  Result:= PickType(ATypeText, ATypeUses, ACand, AReason);
  if Result or (AReason <> R_NO_TYPE) then Exit;
  var Leaf: string:= NormalizeTypeLeaf(ATypeText);
  if (Leaf = '') or Leaf.StartsWith('^') then Exit;
  var Seen: TArray<TLibCand>:= VisibleOf(HelperCands(Leaf), AHelperUses);
  if Length(Seen) = 1 then
  begin
    ACand  := Seen[0];
    AReason:= '';
    Exit(True);
  end;
  if Length(Seen) > 1 then AReason:= R_AMBIGUOUS;
end;

function TLibraryOracle.Kids(AStore: Integer; AId: Int64): TArray<TSymbol>;
begin
  var K: string:= Key(AStore, AId);
  if FKids.TryGetValue(K, Result) then Exit;
  Result:= FStores[AStore].FindAllChildSymbols(AId);
  FKids.Add(K, Result);
end;

function TLibraryOracle.Ancestors(AStore: Integer; AId: Int64): TArray<TTypeAncestor>;
begin
  var K: string:= Key(AStore, AId);
  if FAncestors.TryGetValue(K, Result) then Exit;
  Result:= FStores[AStore].GetTransitiveAncestors(AId);
  FAncestors.Add(K, Result);
end;

function TLibraryOracle.DeclaringMember(const ACand: TLibCand; const AName: string; out AHit: TSymbol): Boolean;
var
  Visit: TArray<Int64>;
begin
  AHit := Default(TSymbol);
  Visit:= ACand.Ids;
  for var Id: Int64 in ACand.Ids do
    for var A: TTypeAncestor in Ancestors(ACand.Store, Id) do
      if A.Resolved and (A.SymbolId > 0) then Visit:= Visit + [A.SymbolId];
  for var Id: Int64 in Visit do
    for var S: TSymbol in Kids(ACand.Store, Id) do
      if SameText(S.Name, AName) and (S.Kind <> skParam) then
      begin
        AHit:= S;
        Exit(True);
      end;
  Result:= ImplicitRootMember(ACand, AName, AHit);
end;

{ The last step of a class's chain, which no ancestor row records when the class has no
  written parent: TObject. Only for a class (an interface or record has no such root) and
  only when every written ancestor resolved: an unknown parent may redeclare the member. }
function TLibraryOracle.ImplicitRootMember(const ACand: TLibCand; const AName: string; out AHit: TSymbol): Boolean;
begin
  Result:= False;
  AHit  := Default(TSymbol);
  if ACand.Kind <> skClass then Exit;
  for var Id: Int64 in ACand.Ids do
    for var A: TTypeAncestor in Ancestors(ACand.Store, Id) do
      if not A.Resolved and not IsRootAncestorName(A.Name) then Exit;
  for var T: TLibCand in Cached(FTypes, IMPLICIT_ROOT_CLASS, TYPE_KINDS, True) do
    if T.UnitStem = IMPLICIT_ROOT_UNIT then
      for var Id: Int64 in T.Ids do
        for var S: TSymbol in Kids(T.Store, Id) do
          if SameText(S.Name, AName) and (S.Kind <> skParam) then
          begin
            AHit:= S;
            Exit(True);
          end;
end;

{ One target whichever candidate the type name means: every candidate is a class and each
  declares the member under the same qualified name. Only the candidates AUses can see are
  asked when any is visible (a unit the file does not use cannot be what the name means --
  wave-146 b7 leftover, `List.Free` on TList<T> beside Spring's unseen TList); with none
  visible, every candidate is asked as before. }
function TLibraryOracle.AgreedMember(const ATypeText, AMember: string; AKind: TExternalKind;
  const AUses: TArray<string>): string;
var
  Hit: TSymbol;
begin
  Result:= '';
  var Cands: TArray<TLibCand>:= Cached(FTypes, NormalizeTypeLeaf(ATypeText), TYPE_KINDS, True);
  var Seen: TArray<TLibCand>:= VisibleOf(Cands, AUses);
  if Length(Seen) > 0 then Cands:= Seen;
  for var C: TLibCand in Cands do
  begin
    if (C.Kind <> skClass) or not DeclaringMember(C, AMember, Hit)
       or (Hit.Kind not in (if AKind = ekMemberAccess then OK_ACCESS else OK_CALL)) then Exit('');
    if (Result <> '') and not SameText(Result, Hit.QualifiedName) then Exit('');
    Result:= Hit.QualifiedName;
  end;
end;

function TLibraryOracle.VisibleOf(const ACands: TArray<TLibCand>; const AUses: TArray<string>): TArray<TLibCand>;
begin
  Result:= [];
  for var C: TLibCand in ACands do
    if InUses(C.UnitStem, AUses) then Result:= Result + [C];
end;

{ How many qualified routines named AMember live in a unit the file uses whose name is AChain,
  written whole (`System.SysUtils`) or as the suffix InUses accepts (`SysUtils`). }
function TLibraryOracle.UnitRoutine(const AChain, AMember: string; const AUses: TArray<string>;
  out AQName: string): Integer;
begin
  Result:= 0;
  AQName:= '';
  var Lc: string:= LowerCase(AChain);
  for var R: TLibCand in VisibleOf(Cached(FRoutines, AMember, ROUTINE_KINDS, False), AUses) do
    if (R.UnitStem = Lc) or R.UnitStem.EndsWith('.' + Lc) then
    begin
      Inc(Result);
      AQName:= R.QName;
    end;
end;

function TLibraryOracle.HelpersDeclare(const AStore: ISymbolStore; const AStoreTag, ATypeName, AMember: string): Boolean;
var
  CacheKey: string;
  Names   : string;
begin
  { One `;name;name;` list per store and type: a with target is asked about many names. }
  CacheKey:= AStoreTag + '#' + LowerCase(ATypeName);
  if not FHelperMembers.TryGetValue(CacheKey, Names) then
  begin
    Names:= ';';
    for var H: THelperEdge in AStore.FindHelpersOfType(ATypeName) do
      for var S: TSymbol in AStore.FindAllChildSymbols(H.HelperSymbolId) do
        Names:= Names + LowerCase(S.Name) + ';';
    FHelperMembers.Add(CacheKey, Names);
  end;
  Result:= Names.Contains(';' + LowerCase(AMember) + ';');
end;

function TLibraryOracle.CandProvesAbsent(const ACand: TLibCand; const AMember: string;
  const AProjectStore: ISymbolStore): Boolean;
var
  Hit  : TSymbol;
  Chain: TArray<string>;
begin
  if DeclaringMember(ACand, AMember, Hit) then Exit(False);
  Chain:= [ACand.Name, 'TObject'];
  for var Id: Int64 in ACand.Ids do
    for var A: TTypeAncestor in Ancestors(ACand.Store, Id) do
      if A.Resolved and (A.SymbolId > 0) then Chain:= Chain + [NormalizeTypeLeaf(A.Name)]
      else if not IsRootAncestorName(A.Name) then Exit(False);
  for var TypeName: string in Chain do
  begin
    if (AProjectStore <> nil) and HelpersDeclare(AProjectStore, 'project', TypeName, AMember) then Exit(False);
    for var Si:= 0 to High(FStores) do
      if (FStores[Si] <> nil) and HelpersDeclare(FStores[Si], IntToStr(Si), TypeName, AMember) then Exit(False);
  end;
  Result:= True;
end;

function TLibraryOracle.MemberProvablyAbsent(const ATypeText, AMember: string;
  const AProjectStore: ISymbolStore): Boolean;
begin
  var Leaf: string:= NormalizeTypeLeaf(ATypeText);
  if (Length(FStores) = 0) or (Leaf = '') or Leaf.StartsWith('^') then Exit(False);
  var Cands: TArray<TLibCand>:= Cached(FTypes, Leaf, TYPE_KINDS, True);
  Result:= Length(Cands) > 0;
  for var C: TLibCand in Cands do
    Result:= Result and CandProvesAbsent(C, AMember, AProjectStore);
end;

function TLibraryOracle.StepPending(var ACand: TLibCand; const APending: string;
  const AHelperUses: TArray<string>; out AReason: string): Boolean;
var
  Hit : TSymbol ;
  Next: TLibCand;
begin
  AReason:= '';
  if APending = '' then Exit(True);
  for var Seg: string in APending.Split(['.']) do
  begin
    if not DeclaringMember(ACand, Trim(Seg), Hit)
       or (Hit.Kind not in STEP_KINDS) then
    begin
      AReason:= R_NO_MEMBER;
      Exit(False);
    end;
    { The member's type is named in ITS declaring unit: prefer that unit, then
      what that unit uses -- never the project file's uses. }
    if not PickTypeOrHelper(MemberTypeText(Hit), LibraryUses(ACand.Store, Hit.FileId), AHelperUses, Next, AReason) then
    begin
      if AReason = R_NO_TYPE then AReason:= R_NO_MEMBER;
      Exit(False);
    end;
    ACand:= Next;
  end;
  Result:= True;
end;

function TLibraryOracle.MemberOf(const ACand: TLibCand; const AMember: string; AKind: TExternalKind;
  out AReason: string): string;
var
  Hit: TSymbol;
begin
  AReason:= '';
  if DeclaringMember(ACand, AMember, Hit) then
  begin
    if Hit.Kind in (if AKind = ekMemberAccess then OK_ACCESS else OK_CALL) then Exit(Hit.QualifiedName);
    { D10: a call through a property or field -- an event; what runs is decided at run time,
      so the answer is the PROPERTY, marked late-bound (never a routine). }
    if (AKind = ekCall) and (Hit.Kind in [skProperty, skField]) then
    begin
      AReason:= R_LATE_BOUND;
      Exit(Hit.QualifiedName);
    end;
  end;
  AReason:= R_NO_MEMBER;
  Result := '';
end;

function TLibraryOracle.Count(const AResult, AReason: string): string;
begin
  Result   := AResult;
  FLastKind:= '';
  if (AResult <> '') and (AReason = R_LATE_BOUND) then
  begin
    Inc(FStats.LateBound);
    FLastKind:= EXTERNAL_KIND_INDIRECT;
  end
  else if (AResult <> '') and (AReason = R_INTRINSIC) then
  begin
    Inc(FStats.Intrinsic);
    FLastKind:= EXTERNAL_KIND_INTRINSIC;
  end
  else if AResult <> '' then Inc(FStats.Bound)
  else if AReason = R_AMBIGUOUS then Inc(FStats.AmbiguousType)
  else if AReason = R_NO_STORE then Inc(FStats.NoStore)
  else if AReason = R_NO_TYPE then Inc(FStats.NoType)
  else Inc(FStats.NoMember);
end;

function TLibraryOracle.Bind(const ATypeText, APending, AMember: string; AKind: TExternalKind;
  const AUsesUnits: TArray<string>; out AReason: string): string;
var
  C: TLibCand;
begin
  if AKind = ekBareCall then Exit(BindBare(AMember, AUsesUnits, '', AReason));
  Result := '';
  AReason:= '';
  if Length(FStores) = 0 then AReason:= R_NO_STORE
  else if PickTypeOrHelper(ATypeText, AUsesUnits + ['system', 'sysinit'], AUsesUnits + ['system', 'sysinit'], C, AReason)
          and StepPending(C, APending, AUsesUnits + ['system', 'sysinit'], AReason) then
    Result:= MemberOf(C, AMember, AKind, AReason)
  else if (AReason = R_AMBIGUOUS) and (APending = '') then
  begin
    Result:= AgreedMember(ATypeText, AMember, AKind, AUsesUnits + ['system', 'sysinit']);
    if Result <> '' then AReason:= '';
  end;
  Result:= Count(Result, AReason);
end;

function TLibraryOracle.BindHead(const AChain, AMember: string; AKind: TExternalKind;  // dl:ok too-many-exit-points@18cf -- REVIEWED 2026-10-28 (item 4, lane R4R): the exits are Delphi's name-lookup ORDER for an untyped head -- inherited member, library type, library global, unit-qualified type -- each answering and leaving, plus the three declines inside the first rung that must stop the walk (a nearer member hides a farther meaning). One exit would thread a found flag through four rungs whose order is the contract.
  const AUsesUnits: TArray<string>; const AScopeType: string; out AReason: string;
  out ATypeText: string): string;
var
  Segs   : TArray<string>;
  Head   : string;
  Pending: string;
  Visible   : TArray<string>;
  C      : TLibCand;
  Hit    : TSymbol;
  Why    : string;

  function Finish(const AText: string): string;
  begin
    ATypeText:= AText + (if Pending <> '' then '.' + Pending else '');
    Result   := if StepPending(C, Pending, Visible, AReason) then MemberOf(C, AMember, AKind, AReason) else '';
  end;

begin
  Result   := '';
  AReason  := '';
  ATypeText:= '';
  if Length(FStores) = 0 then Exit(Count('', R_NO_STORE));
  Segs   := AChain.Split(['.']);
  Head   := Trim(Segs[0]);
  Pending:= string.Join('.', Segs, 1, Length(Segs) - 1);
  Visible   := AUsesUnits + ['system', 'sysinit'];
  { 1. Self-less: a member the enclosing class inherits from the library is
       nearer than any type or global of the name. An undecidable scope type
       (absent / ambiguous) is passed over -- a project class's library parent
       that no store holds cannot be asked. }
  if (AScopeType <> '') and PickType(AScopeType, Visible, C, Why) and DeclaringMember(C, Head, Hit) then
  begin
    if Hit.Kind not in STEP_KINDS then Exit(Count('', R_NO_MEMBER));
    var Step: TLibCand;
    if not PickType(MemberTypeText(Hit), LibraryUses(C.Store, Hit.FileId), Step, Why) then
      Exit(Count('', R_NO_MEMBER));
    C:= Step;
    Exit(Count(Finish(C.Name), AReason));
  end;
  var Values: TArray<TLibCand>:= Cached(FValues, Head, VALUE_KINDS, False);
  var SeenValues: TArray<TLibCand>:= VisibleOf(Values, Visible);
  var SeenType: Boolean:= Length(VisibleOf(Cached(FTypes, Head, TYPE_KINDS, True), Visible)) > 0;
  { 1b. `System.SysUtils.DeleteFile`: nothing visible is named Head, so the chain is a unit. }
  if not SeenType and (Length(SeenValues) = 0) then
  begin
    var Routine: string;
    var Routines: Integer:= UnitRoutine(AChain, AMember, Visible, Routine);
    if Routines > 1 then Exit(Count('', R_AMBIGUOUS));
    if Routines = 1 then Exit(Count(Routine, ''));
  end;
  if SeenType or (Length(SeenValues) = 0) then
  begin
    { 2. The head IS a library type: `TEncoding.UTF8`, `TStringList.Create`. }
    if PickType(Head, Visible, C, Why) then Exit(Count(Finish(C.Name), AReason));
    if Why = R_AMBIGUOUS then Exit(Count('', R_AMBIGUOUS));
  end
  else
    Values:= SeenValues; // a type in an unused unit does not hide what the file can see
  { 3. A library unit-level var / const: `Application`, `CodeSite`. }
  if Length(Values) > 0 then
  begin
    var V: TLibCand;
    if not Pick(Values, Visible, V, Why) then Exit(Count('', R_AMBIGUOUS));
    if not PickType(Trim(V.Sig), LibraryUses(V.Store, V.FileId), C, Why) then
      Exit(Count('', Why));
    Exit(Count(Finish(C.Name), AReason));
  end;
  { 4. `Unit.Name.TType`: the trailing segment a type declared in exactly that unit. }
  if Length(Segs) >= 2 then
  begin
    var Leaf: string:= Trim(Segs[High(Segs)]);
    var Prefix: string:= LowerCase(string.Join('.', Segs, 0, High(Segs)));
    for var T: TLibCand in Cached(FTypes, Leaf, TYPE_KINDS, True) do
      if T.UnitStem = Prefix then
      begin
        C      := T;
        Pending:= '';
        Exit(Count(Finish(C.Name), AReason));
      end;
  end;
  { D08: `TBytes.Create(1, 2)`, `TArray<Integer>.Create(1)` -- a dynamic array's constructor
    is a compiler intrinsic with no declaration: bind it to the synthetic built-in name. }
  if (AKind = ekCall) and (Pending = '') and SameText(AMember, 'Create') and IsDynArrayType(Head, Visible, 0) then
    Exit(Count(INTRINSIC_DYNARRAY_CREATE, R_INTRINSIC));
  Result:= Count('', R_NO_TYPE);
end;

function TLibraryOracle.BindBare(const AName: string; const AUsesUnits: TArray<string>;
  const AScopeType: string; out AReason: string; const AOwnUses: TArray<string>): string;
var
  C   : TLibCand;
  Hit : TSymbol ;
  Why : string  ;
  Hits: Integer ;

  function CountVisible(const AVisible: TArray<string>; out AQName: string): Integer;
  begin
    Result:= 0;
    AQName:= '';
    for var R: TLibCand in Cached(FRoutines, AName, ROUTINE_KINDS, False) do
      if InUses(R.UnitStem, AVisible) then
      begin
        Inc(Result);
        AQName:= R.QName;
      end;
  end;

begin
  Result := '';
  AReason:= '';
  if Length(FStores) = 0 then Exit(Count('', R_NO_STORE));
  var Visible: TArray<string>:= AUsesUnits + ['system', 'sysinit'];
  if (AScopeType <> '') and PickType(AScopeType, Visible, C, Why) and DeclaringMember(C, AName, Hit) then
  begin
    if Hit.Kind in OK_CALL then Exit(Count(Hit.QualifiedName, ''));
    Exit(Count('', R_NO_MEMBER));
  end;
  { A free routine: its unit must be one the file uses (System always is);
    exactly one such qualified name, or nothing. The file's own uses decide first
    (AOwnUses); the program-wide set only when they name no such routine. }
  Hits:= 0;
  if AOwnUses <> nil then Hits:= CountVisible(AOwnUses + ['system', 'sysinit'], Result);
  if Hits = 0 then Hits:= CountVisible(Visible, Result);
  if Hits > 1 then
  begin
    Result := '';
    AReason:= R_AMBIGUOUS;
  end
  else if Hits = 0 then AReason:= R_NO_MEMBER;
  Result:= Count(Result, AReason);
end;

end.
