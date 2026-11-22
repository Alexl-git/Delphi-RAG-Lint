unit DRagLint.V152.ATLA.Support;

{ Wave v152 lane ATLA -- helpers of DRagLint.V152.ATLA (private to the lane).
  Three tree-sitter checks over ONE file each:
    * reserved-word-identifier  -- a Delphi reserved word (dcc's list, never a
      directive) used as the name of a variable, field, parameter, constant or
      type. The grammar's directive-word scanner accepts `Inline` / `Library`
      as names; dcc stops with E2029. `&Inline` is the legal escape.
    * contract-unit-declares-class (in-place expansion) -- the units named by
      the `contractUnits` glob list of drag-lint.json. The unit-name suffix
      (`.Contract`, `.Intf` ...) stays with lane APP, which owns the rule.
    * implicit-package-import -- a unit in a package's contains clause uses a
      project unit that is neither in contains nor in a required package. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  ;

const
  RULE_RESERVED_IDENT  = 'reserved-word-identifier';
  RULE_IMPLICIT_IMPORT = 'implicit-package-import';
  CONTRACT_UNITS_KEY   = 'contractUnits';

type
  /// <summary>Tree-sitter checks of lane ATLA; stateless, class methods only.</summary>
  /// <remarks>
  /// Every check reads TAstParseCache, so trees are shared with the other
  /// AST rules of the run and freed by the caller's TAstParseCache.Clear. A file
  /// that does not parse yields no finding. Not thread-safe (the parse cache is not).
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.V152.ATLA.TV152ATLARules.CheckFile (DRagLint.V152.ATLA.pas), DRagLint.V152.ATLA.TV152ATLARules.CheckProject (DRagLint.V152.ATLA.pas)</para>
  /// <para>Used in units: DRagLint.V152.ATLA</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TAtlaChecks = class
  public
    /// <summary>Reports every declared name that is a Delphi reserved word.</summary>
    /// <param name="APath">The .pas file.</param>
    /// <param name="AOut">Receives the findings; owned by the caller.</param>
    /// <remarks>
    /// Names checked: var / threadvar, field, parameter, const and type
    /// names. A name written with the escape prefix (`&amp;Inline`) is legal and never
    /// reported. Directives (`at`, `on`, `name`, `message` ...) are not reserved
    /// words and are never reported.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V152.ATLA.TV152ATLARules.CheckFile (DRagLint.V152.ATLA.pas)</para>
    /// <para>Calls: DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, DRagLint.V152.ATLA.Support.CheckDeclNames, DRagLint.V152.ATLA.Support.Gather, TreeSitter.TTSTree.RootNode</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
    /// <seealso cref="DRagLint.V152.ATLA.Support.CheckDeclNames"/>
    /// <seealso cref="DRagLint.V152.ATLA.Support.Gather"/>
    /// <seealso cref="TreeSitter.TTSTree.RootNode"/>
    /// <seealso cref="DRagLint.V152.ATLA.Support.TAtlaChecks.ContainedFiles"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class procedure ReservedIdentifiers(const APath: string; AOut: TList<TLintFinding>); static;
    /// <summary>Reports each class declared in the interface section of a unit
    /// that the `contractUnits` glob list names.</summary>
    /// <param name="APath">The .pas file.</param>
    /// <param name="AGlobs">Unit-name masks (`*` and `?`, case-insensitive) from drag-lint.json.</param>
    /// <param name="AOut">Receives the findings; owned by the caller.</param>
    /// <remarks>
    /// A unit whose last name segment lane APP already treats as a contract
    /// (Intf, Interface(s), Contract(s), Abstraction(s)) is skipped: APP reports it,
    /// so the two lanes never report the same class twice. Exempt, like APP:
    /// `class of`, forward declarations, classes derived from Exception or E*.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V152.ATLA.TV152ATLARules.CheckFile (DRagLint.V152.ATLA.pas)</para>
    /// <para>Calls: DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, DRagLint.V152.ATLA.Support.ExemptClass, DRagLint.V152.ATLA.Support.FirstNamed, DRagLint.V152.ATLA.Support.Gather, DRagLint.V152.ATLA.Support.GlobOnlyContract, DRagLint.V152.ATLA.Support.MakeFinding, DRagLint.V152.ATLA.Support.NodeText, TreeSitter.TTSNodeHelper.ChildByField/1, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NamedChild, TreeSitter.TTSNodeHelper.NamedChildCount, TreeSitter.TTSNodeHelper.NodeType, TreeSitter.TTSTree.RootNode</para>
    /// <para>Complexity: 12 (cyclomatic, outer body), 27 lines (full implementation)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
    /// <seealso cref="DRagLint.V152.ATLA.Support.ExemptClass"/>
    /// <seealso cref="DRagLint.V152.ATLA.Support.FirstNamed"/>
    /// <seealso cref="DRagLint.V152.ATLA.Support.Gather"/>
    /// <seealso cref="DRagLint.V152.ATLA.Support.GlobOnlyContract"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class procedure ContractClasses(const APath: string; const AGlobs: TArray<string>; AOut: TList<TLintFinding>); static;
    /// <summary>The `contractUnits` list of the drag-lint.json this engine resolves.</summary>
    /// <param name="AEngineDir">The folder of the running exe.</param>
    /// <returns>The masks; empty when the file, the key or a string item is missing.</returns>
    /// <remarks>
    /// Read on every call (no cache) so an edited manifest applies to the
    /// next lint; a malformed manifest yields an empty list, never an exception.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V152.ATLA.TV152ATLARules.CheckFile (DRagLint.V152.ATLA.pas)</para>
    /// <para>Calls: DRagLint.Index.Manifest.TInstalledLayout.ManifestLocation, FileExists, TJSONArray, TJSONObject</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <para>Touches: file system</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Index.Manifest.TInstalledLayout.ManifestLocation"/>
    /// <seealso cref="DRagLint.V152.ATLA.Support.TAtlaChecks.ContainedFiles"/>
    /// <seealso cref="DRagLint.V152.ATLA.Support.TAtlaChecks.ContractClasses"/>
    /// <seealso cref="DRagLint.V152.ATLA.Support.TAtlaChecks.DpkVisibleFrom"/>
    /// <seealso cref="DRagLint.V152.ATLA.Support.TAtlaChecks.ImplicitImports"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function LoadContractGlobs(const AEngineDir: string): TArray<string>; static;
    /// <summary>Reports the uses entries of APath that a package imports implicitly.</summary>
    /// <param name="APath">A .pas file listed in the contains clause of a .dpk.</param>
    /// <param name="ADpkPath">The package; '' = search the unit's folder and its parent.</param>
    /// <param name="AOut">Receives the findings (on APath); owned by the caller.</param>
    /// <remarks>
    /// A used unit is reported when a source file `&lt;Unit&gt;.pas` exists in
    /// the package folder or in the folder of a contained unit, and the unit is
    /// neither in contains nor in the contains clause of a required package whose
    /// .dpk is found beside the package (same folder, parent, or a sibling folder).
    /// Units with no source there (RTL, VCL, third-party .dcp) are assumed to come
    /// from a required package and are never reported.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V152.ATLA.TV152ATLARules.CheckFile (DRagLint.V152.ATLA.pas), DRagLint.V152.ATLA.TV152ATLARules.CheckProject (DRagLint.V152.ATLA.pas)</para>
    /// <para>Calls: DRagLint.V152.ATLA.Support.CheckUnitAgainst, DRagLint.V152.ATLA.Support.DpkContainsFile, DRagLint.V152.ATLA.Support.ReadDpk, ExtractFileDir</para>
    /// <para>Touches: file system</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V152.ATLA.Support.CheckUnitAgainst"/>
    /// <seealso cref="DRagLint.V152.ATLA.Support.DpkContainsFile"/>
    /// <seealso cref="DRagLint.V152.ATLA.Support.ReadDpk"/>
    /// <seealso cref="DRagLint.V152.ATLA.Support.TAtlaChecks.ContainedFiles"/>
    /// <seealso cref="DRagLint.V152.ATLA.Support.TAtlaChecks.ContractClasses"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class procedure ImplicitImports(const APath, ADpkPath: string; AOut: TList<TLintFinding>); static;
    /// <summary>True when the per-file search of ImplicitImports (unit folder and its
    /// parent) would find ADpkPath for the unit APath.</summary>
    /// <param name="APath">A contained unit.</param>
    /// <param name="ADpkPath">The package.</param>
    /// <returns>True when lint already covers the pair per file.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V152.ATLA.TV152ATLARules.CheckProject (DRagLint.V152.ATLA.pas)</para>
    /// <para>Calls: ExtractFileDir, SameText</para>
    /// <para>Returns: SameText(UnitDir, DpkDir) or SameText(ExtractFileDir(UnitDir), DpkDir)</para>
    /// <para>Touches: file system</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V152.ATLA.Support.TAtlaChecks.ContainedFiles"/>
    /// <seealso cref="DRagLint.V152.ATLA.Support.TAtlaChecks.ContractClasses"/>
    /// <seealso cref="DRagLint.V152.ATLA.Support.TAtlaChecks.ImplicitImports"/>
    /// <seealso cref="DRagLint.V152.ATLA.Support.TAtlaChecks.LoadContractGlobs"/>
    /// <seealso cref="DRagLint.V152.ATLA.Support.TAtlaChecks.ReservedIdentifiers"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function DpkVisibleFrom(const APath, ADpkPath: string): Boolean; static;
    /// <summary>The source files a package's contains clause names (with an `in` path).</summary>
    /// <param name="ADpkPath">The package.</param>
    /// <returns>Full paths; units without an `in` path are resolved in the package folder.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V152.ATLA.TV152ATLARules.CheckProject (DRagLint.V152.ATLA.pas)</para>
    /// <para>Calls: DRagLint.V152.ATLA.Support.ReadDpk</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V152.ATLA.Support.ReadDpk"/>
    /// <seealso cref="DRagLint.V152.ATLA.Support.TAtlaChecks.ContractClasses"/>
    /// <seealso cref="DRagLint.V152.ATLA.Support.TAtlaChecks.DpkVisibleFrom"/>
    /// <seealso cref="DRagLint.V152.ATLA.Support.TAtlaChecks.ImplicitImports"/>
    /// <seealso cref="DRagLint.V152.ATLA.Support.TAtlaChecks.LoadContractGlobs"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function ContainedFiles(const ADpkPath: string): TArray<string>; static;
  end;

implementation

uses
  System.IOUtils
  , System.JSON
  , System.Masks
  , System.RegularExpressions
  , TreeSitter
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Index.Manifest
  , DRagLint.V151.APP.Support  // RULE_CONTRACT_CLASS: lane APP owns the rule id
  ;

const
  { dcc's reserved words (Delphi language guide, "Reserved Words"); directives excluded. }
  RESERVED_WORDS: array[0..63] of string = (
    'and', 'array', 'as', 'asm', 'begin', 'case', 'class', 'const', 'constructor',
    'destructor', 'dispinterface', 'div', 'do', 'downto', 'else', 'end', 'except',
    'exports', 'file', 'finalization', 'finally', 'for', 'function', 'goto', 'if',
    'implementation', 'in', 'inherited', 'initialization', 'inline', 'interface',
    'is', 'label', 'library', 'mod', 'nil', 'not', 'object', 'of', 'or', 'packed',
    'procedure', 'program', 'property', 'raise', 'record', 'repeat',
    'resourcestring', 'set', 'shl', 'shr', 'string', 'then', 'threadvar', 'to',
    'try', 'type', 'unit', 'until', 'uses', 'var', 'while', 'with', 'xor');
  APP_CONTRACT_SEGMENT = '^(Intf|Interfaces?|Contracts?|Abstractions?)$';

type
  TDpkUnit = record
    Name    : string;
    FilePath: string;  // '' when the entry has no `in` path and no file in the package folder
  end;

  TDpkInfo = record
    Path    : string;
    Contains: TArray<TDpkUnit>;
    Requires: TArray<string>;
  end;

function NodeText(const ASrc: TBytes; const ANode: TTSNode): string;
begin
  Result:= '';
  if ANode.IsNull then Exit;
  var S: Integer:= Integer(ANode.StartByte);
  var L: Integer:= Integer(ANode.EndByte) - S;
  if (L > 0) and (S >= 0) and (S + L <= Length(ASrc)) then Result:= TEncoding.UTF8.GetString(ASrc, S, L);
end;

function MakeFinding(const APath, ARule, ASeverity, AMsg: string; const ANode: TTSNode): TLintFinding;
begin
  Result:= Default(TLintFinding);
  Result.RuleId   := ARule;
  Result.Severity := ASeverity;
  Result.FilePath := APath;
  Result.StartLine:= Integer(ANode.StartPoint.Row) + 1;
  Result.StartCol := TAstParseCache.CharCol(Result.FilePath, ANode.StartPoint); { 1.52 BK-COLS2: character column }
  Result.EndLine  := Integer(ANode.EndPoint.Row) + 1;
  Result.EndCol   := TAstParseCache.CharCol(Result.FilePath, ANode.EndPoint); { 1.52 BK-COLS2: character column }
  Result.Message  := AMsg;
end;

procedure Gather(const ANode: TTSNode; const AKind: string; AList: TList<TTSNode>);
begin
  if ANode.IsNull then Exit;
  if ANode.NodeType = AKind then AList.Add(ANode);
  for var I: Integer:= 0 to ANode.NamedChildCount - 1 do
    Gather(ANode.NamedChild(I), AKind, AList);
end;

function FirstNamed(const ANode: TTSNode; const AKind: string): TTSNode;
begin
  Result:= Default(TTSNode);
  for var I: Integer:= 0 to ANode.NamedChildCount - 1 do
    if ANode.NamedChild(I).NodeType = AKind then Exit(ANode.NamedChild(I));
end;

function IsReservedWord(const AName: string): Boolean;
begin
  Result:= False;
  var L: string:= LowerCase(AName);
  for var W: string in RESERVED_WORDS do
    if W = L then Exit(True);
end;

function DeclKindName(const AKind: string): string;
begin
  Result:= if AKind = 'declVar' then 'variable'
    else if AKind = 'declField' then 'field'
    else if AKind = 'declArg' then 'parameter'
    else if AKind = 'declConst' then 'constant'
    else 'type';
end;

{ The names of a declaration are its identifier children before the first ':' or
  '=' token (rttiAttributes and the var/const/out modifier are skipped). }
procedure CheckDeclNames(const APath: string; const ASrc: TBytes; const ADecl: TTSNode; AOut: TList<TLintFinding>);
begin
  for var I: Integer:= 0 to ADecl.ChildCount - 1 do
  begin
    var C: TTSNode:= ADecl.Child(I);
    var K: string:= C.NodeType;
    if (K = ':') or (K = '=') or (K = 'kEq') then Break;
    if K <> 'identifier' then Continue;
    var Name: string:= NodeText(ASrc, C);
    if Name.StartsWith('&') or not IsReservedWord(Name) then Continue;
    AOut.Add(MakeFinding(APath, RULE_RESERVED_IDENT, 'warning',
      '''' + Name + ''' is a reserved word: dcc rejects it as a ' + DeclKindName(ADecl.NodeType) +
      ' name (E2029 Identifier expected); rename it or escape it as &' + Name + '.', C));
  end;
end;

class procedure TAtlaChecks.ReservedIdentifiers(const APath: string; AOut: TList<TLintFinding>);
const
  DECL_KINDS: array[0..4] of string = ('declVar', 'declField', 'declArg', 'declConst', 'declType');
begin
  var PF: TParsedFile:= TAstParseCache.Get(APath);
  if PF.Tree = nil then Exit;
  var Decls:= TList<TTSNode>.Create;
  try
    for var K: string in DECL_KINDS do
    begin
      Decls.Clear;
      Gather(PF.Tree.RootNode, K, Decls);
      for var D: TTSNode in Decls do
        CheckDeclNames(APath, PF.Src, D, AOut);
    end;
  finally
    Decls.Free;
  end;
end;

class function TAtlaChecks.LoadContractGlobs(const AEngineDir: string): TArray<string>;
begin
  Result:= nil;
  try
    var Loc: TManifestLocation:= TInstalledLayout.ManifestLocation(AEngineDir);
    if not FileExists(Loc.Path) then Exit;
    var V: TJSONValue:= TJSONObject.ParseJSONValue(TFile.ReadAllText(Loc.Path));
    try
      if V is not TJSONObject then Exit;
      var A: TJSONValue:= TJSONObject(V).GetValue(CONTRACT_UNITS_KEY);
      if A is not TJSONArray then Exit;
      for var Item: TJSONValue in TJSONArray(A) do
        if (Item is TJSONString) and (Item.Value.Trim <> '') then Result:= Result + [Item.Value.Trim];
    finally
      V.Free;
    end;
  except
    on Exception do Result:= nil;  // a broken manifest must not stop lint; the doc-comment promises an empty list
  end;
end;

function ExemptClass(const ASrc: TBytes; const AClass: TTSNode): Boolean;
begin
  var Low: string:= LowerCase(NodeText(ASrc, AClass)).Trim;
  if (Low = 'class') or (Low = 'object') then Exit(True);  // forward declaration
  var Head: string:= '';
  for var I: Integer:= 0 to AClass.ChildCount - 1 do
  begin
    var K: string:= AClass.Child(I).NodeType;
    if K = 'kOf' then Exit(True);  // class of
    if K = 'kRecord' then Exit(True);
    if K = 'typeref' then
    begin
      Head:= NodeText(ASrc, AClass.Child(I));
      Break;
    end;
    if (K = 'declSection') or (K = 'kEnd') then Break;
  end;
  Result:= SameText(Head, 'Exception') or TRegEx.IsMatch(Head, '^E[A-Z]\w*$');
end;

{ True when a contractUnits glob names AUnitName and lane APP's suffix check
  (which owns the rule) does not already cover it. }
function GlobOnlyContract(const AUnitName: string; const AGlobs: TArray<string>): Boolean;
begin
  Result:= False;
  if AUnitName = '' then Exit;
  var LastSeg: string:= Copy(AUnitName, LastDelimiter('.', AUnitName) + 1, MaxInt);
  if TRegEx.IsMatch(LastSeg, APP_CONTRACT_SEGMENT, [roIgnoreCase]) then Exit;  // lane APP reports it
  for var G: string in AGlobs do
    if MatchesMask(AUnitName, G) then Exit(True);
end;

class procedure TAtlaChecks.ContractClasses(const APath: string; const AGlobs: TArray<string>; AOut: TList<TLintFinding>);
begin
  if Length(AGlobs) = 0 then Exit;
  var PF: TParsedFile:= TAstParseCache.Get(APath);
  if PF.Tree = nil then Exit;
  var UnitNode: TTSNode:= FirstNamed(PF.Tree.RootNode, 'unit');
  var UnitName: string:= if UnitNode.IsNull then '' else NodeText(PF.Src, FirstNamed(UnitNode, 'moduleName')).Replace(' ', '');
  if not GlobOnlyContract(UnitName, AGlobs) then Exit;
  var Intf: TTSNode:= FirstNamed(UnitNode, 'interface');
  if Intf.IsNull then Exit;
  var Types:= TList<TTSNode>.Create;
  try
    Gather(Intf, 'declType', Types);
    for var T: TTSNode in Types do
    begin
      var Cls: TTSNode:= T.ChildByField('type');
      if not Cls.IsNull and (Cls.NodeType = 'type') and (Cls.NamedChildCount = 1) then Cls:= Cls.NamedChild(0);
      if Cls.IsNull or (Cls.NodeType <> 'declClass') or ExemptClass(PF.Src, Cls) then Continue;
      var NameNode: TTSNode:= T.ChildByField('name');
      AOut.Add(MakeFinding(APath, RULE_CONTRACT_CLASS, 'info',
        'The contract unit ' + UnitName + ' declares the class ' + NodeText(PF.Src, NameNode) +
        ' -- contract units should hold only interfaces and plain types; move the class to an implementation unit.',
        NameNode));
    end;
  finally
    Types.Free;
  end;
end;

function StripQuotes(const S: string): string;
begin
  Result:= S.Trim;
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
    Result:= Copy(Result, 2, Length(Result) - 2);
end;

function ReadDpk(const ADpkPath: string; out AInfo: TDpkInfo): Boolean;
begin
  AInfo:= Default(TDpkInfo);
  AInfo.Path:= TPath.GetFullPath(ADpkPath);
  var PF: TParsedFile:= TAstParseCache.Get(AInfo.Path);
  if PF.Tree = nil then Exit(False);
  var Pkg: TTSNode:= FirstNamed(PF.Tree.RootNode, 'package');
  if Pkg.IsNull then Exit(False);
  var Dir: string:= ExtractFilePath(AInfo.Path);
  var Req: TTSNode:= FirstNamed(Pkg, 'declRequires');
  if not Req.IsNull then
    for var I: Integer:= 0 to Req.NamedChildCount - 1 do
      if Req.NamedChild(I).NodeType = 'moduleName' then
        AInfo.Requires:= AInfo.Requires + [NodeText(PF.Src, Req.NamedChild(I)).Replace(' ', '')];
  var Con: TTSNode:= FirstNamed(Pkg, 'declContains');
  if not Con.IsNull then
    for var I: Integer:= 0 to Con.NamedChildCount - 1 do
    begin
      var U: TTSNode:= Con.NamedChild(I);
      if U.NodeType <> 'declUsesUnit' then Continue;
      var E: TDpkUnit;
      E.Name:= NodeText(PF.Src, FirstNamed(U, 'moduleName')).Replace(' ', '');
      var Lit: TTSNode:= FirstNamed(U, 'literalString');
      E.FilePath:= if not Lit.IsNull then TPath.GetFullPath(TPath.Combine(Dir, StripQuotes(NodeText(PF.Src, Lit))))
        else if FileExists(Dir + E.Name + '.pas') then Dir + E.Name + '.pas'
        else '';
      AInfo.Contains:= AInfo.Contains + [E];
    end;
  Result:= True;
end;

function DpkContainsFile(const AInfo: TDpkInfo; const AFullPath: string): Boolean;
begin
  Result:= False;
  for var E: TDpkUnit in AInfo.Contains do
    if SameText(E.FilePath, AFullPath) then Exit(True);
end;

function FindRequiredDpk(const ADpkDir, AName: string): string;
begin
  var File_: string:= AName + '.dpk';
  if FileExists(TPath.Combine(ADpkDir, File_)) then Exit(TPath.Combine(ADpkDir, File_));
  var Parent: string:= ExtractFileDir(ExcludeTrailingPathDelimiter(ADpkDir));
  if (Parent = '') or not TDirectory.Exists(Parent) then Exit('');
  if FileExists(TPath.Combine(Parent, File_)) then Exit(TPath.Combine(Parent, File_));
  for var Sub: string in TDirectory.GetDirectories(Parent) do
    if FileExists(TPath.Combine(Sub, File_)) then Exit(TPath.Combine(Sub, File_));
  Result:= '';
end;

function SetHas(const ASet: TArray<string>; const AName: string): Boolean;
begin
  Result:= False;
  for var S: string in ASet do
    if SameText(S, AName) then Exit(True);
end;

procedure CheckUnitAgainst(const APath, AReportPath: string; const AInfo: TDpkInfo; AOut: TList<TLintFinding>);
begin
  var Provided: TArray<string>:= nil;
  var Dirs: TArray<string>:= [ExtractFilePath(AInfo.Path)];
  for var E: TDpkUnit in AInfo.Contains do
  begin
    Provided:= Provided + [E.Name];
    if (E.FilePath <> '') and not SetHas(Dirs, ExtractFilePath(E.FilePath)) then
      Dirs:= Dirs + [ExtractFilePath(E.FilePath)];
  end;
  for var R: string in AInfo.Requires do
  begin
    var RPath: string:= FindRequiredDpk(ExtractFilePath(AInfo.Path), R);
    var RInfo: TDpkInfo;
    if (RPath <> '') and ReadDpk(RPath, RInfo) then
      for var E: TDpkUnit in RInfo.Contains do
        Provided:= Provided + [E.Name];
  end;
  var PF: TParsedFile:= TAstParseCache.Get(APath);
  if PF.Tree = nil then Exit;
  var UnitNode: TTSNode:= FirstNamed(PF.Tree.RootNode, 'unit');
  if UnitNode.IsNull then Exit;
  var Uses_:= TList<TTSNode>.Create;
  try
    Gather(UnitNode, 'declUsesUnit', Uses_);
    for var U: TTSNode in Uses_ do
    begin
      var Name: string:= NodeText(PF.Src, FirstNamed(U, 'moduleName')).Replace(' ', '');
      if (Name = '') or SetHas(Provided, Name) then Continue;
      var Found: Boolean:= False;
      for var D: string in Dirs do
        if FileExists(D + Name + '.pas') then
        begin
          Found:= True;
          Break;
        end;
      if not Found then Continue;
      AOut.Add(MakeFinding(AReportPath, RULE_IMPLICIT_IMPORT, 'warning',
        'Unit ' + Name + ' is neither in the contains clause of package ' +
        ChangeFileExt(ExtractFileName(AInfo.Path), '') + ' nor in a required package: dcc imports it ' +
        'implicitly (W1033); add it to contains or require the package that holds it.', U));
    end;
  finally
    Uses_.Free;
  end;
end;

class function TAtlaChecks.DpkVisibleFrom(const APath, ADpkPath: string): Boolean;
begin
  var UnitDir: string:= ExtractFileDir(TPath.GetFullPath(APath));
  var DpkDir: string:= ExtractFileDir(TPath.GetFullPath(ADpkPath));
  Result:= SameText(UnitDir, DpkDir) or SameText(ExtractFileDir(UnitDir), DpkDir);
end;

class function TAtlaChecks.ContainedFiles(const ADpkPath: string): TArray<string>;
begin
  Result:= nil;
  var Info: TDpkInfo;
  if not ReadDpk(ADpkPath, Info) then Exit;
  for var E: TDpkUnit in Info.Contains do
    if E.FilePath <> '' then Result:= Result + [E.FilePath];
end;

class procedure TAtlaChecks.ImplicitImports(const APath, ADpkPath: string; AOut: TList<TLintFinding>);
begin
  var Full: string:= TPath.GetFullPath(APath);
  var Candidates: TArray<string>:= nil;
  if ADpkPath <> '' then Candidates:= [ADpkPath]
  else
  begin
    var Dir: string:= ExtractFileDir(Full);
    for var D: string in [Dir, ExtractFileDir(Dir)] do
      if (D <> '') and TDirectory.Exists(D) then
        Candidates:= Candidates + TDirectory.GetFiles(D, '*.dpk');
  end;
  for var C: string in Candidates do
  begin
    var Info: TDpkInfo;
    if ReadDpk(C, Info) and DpkContainsFile(Info, Full) then
      CheckUnitAgainst(Full, APath, Info, AOut);
  end;
end;

end.
