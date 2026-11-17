unit DRagLint.V151.DFMB.Support;

{ Wave v151 lane DFMB -- helpers of DRagLint.V151.DFMB (private to the lane).
  A small text-form-file reader (object tree + properties with line numbers) and
  the six data-binding checks that run over it. Binary form files are skipped. }

interface

uses
  System.SysUtils
  , System.Classes
  , System.Generics.Collections
  , System.Generics.Defaults
  , DRagLint.Core.Model
  , DRagLint.Lint.Config
  , DRagLint.V151.Dfm.Common
  ;

type
  /// <summary>One object / inherited / inline block of a text form file.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.DFMB.Support.pas) ?, DRagLint.V151.DFMB.Support.ParseHeader (DRagLint.V151.DFMB.Support.pas), DRagLint.V151.DFMB.Support.TDfmModel.Add (DRagLint.V151.DFMB.Support.pas) ?, DRagLint.V151.DFMB.Support.TDfmModel.Create (DRagLint.V151.DFMB.Support.pas) ?, DRagLint.V151.DFMB.Support.TDfmModel.Find (DRagLint.V151.DFMB.Support.pas) ? (+13 more)</para>
  /// <para>Used in units: DRagLint.V151.DFMB.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDfmObj = class
  strict private
    FObjName: string;
    FClsName: string;
    FLine   : Integer;
    FParent : TDfmObj;
    FProps  : TList<TDfmProp>;
    FKids   : TObjectList<TDfmObj>;
  public
    /// <summary>Component name ('' never; the form file always names it).</summary>
    property ObjName: string read FObjName write FObjName;
    /// <summary>Declared class name, e.g. TDBEdit.</summary>
    property ClsName: string read FClsName write FClsName;
    /// <summary>1-based line of the object header.</summary>
    property Line: Integer read FLine write FLine;
    /// <summary>Enclosing object, or nil for the form itself.</summary>
    property Parent: TDfmObj read FParent write FParent;
    /// <summary>Properties in file order.</summary>
    property Props: TList<TDfmProp> read FProps;
    /// <summary>Nested objects (owned).</summary>
    property Kids: TObjectList<TDfmObj> read FKids;
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.DFMB.Support.ParseHeader (DRagLint.V151.DFMB.Support.pas)</para>
    /// <para>constructor</para>
    /// <para>Writes: FProps, FKids</para>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmObj.Destroy"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmObj.Has"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmObj.IndexOfProp"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmObj.Val"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create;
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: FKids, FProps</para>
    /// <para>Directives: override</para>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmObj.Create"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmObj.Has"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmObj.IndexOfProp"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmObj.Val"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    destructor Destroy; override;
    /// <summary>Index of the property AName (case-insensitive).</summary>
    /// <param name="AName">Property name; dotted for sub-properties.</param>
    /// <returns>Index into Props, or -1.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.DFMB.Support.BindFieldLine (DRagLint.V151.DFMB.Support.pas), DRagLint.V151.DFMB.Support.CheckMasterFields (DRagLint.V151.DFMB.Support.pas), DRagLint.V151.DFMB.Support.CheckRequired (DRagLint.V151.DFMB.Support.pas), DRagLint.V151.DFMB.Support.TDfmObj.Has (DRagLint.V151.DFMB.Support.pas), DRagLint.V151.DFMB.Support.TDfmObj.Val (DRagLint.V151.DFMB.Support.pas)</para>
    /// <para>Calls: SameText</para>
    /// <para>Returns: 0 to Props.Count - 1 do; -1</para>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmObj.Create"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmObj.Destroy"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmObj.Has"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmObj.Val"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IndexOfProp(const AName: string): Integer;
    /// <summary>Raw value of a property.</summary>
    /// <param name="AName">Property name.</param>
    /// <returns>The value text, '' when the property is absent.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.DFMB.Support.BindField (DRagLint.V151.DFMB.Support.pas), DRagLint.V151.DFMB.Support.BindSource (DRagLint.V151.DFMB.Support.pas), DRagLint.V151.DFMB.Support.CheckCircular.Visit (DRagLint.V151.DFMB.Support.pas), DRagLint.V151.DFMB.Support.CheckDupBinding (DRagLint.V151.DFMB.Support.pas), DRagLint.V151.DFMB.Support.CheckMasterFields (DRagLint.V151.DFMB.Support.pas) (+3 more)</para>
    /// <para>Calls: DRagLint.V151.DFMB.Support.TDfmObj.IndexOfProp</para>
    /// <para>Returns: if I &lt; 0 then ''</para>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmObj.IndexOfProp"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmObj.Create"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmObj.Destroy"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmObj.Has"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Val(const AName: string): string;
    /// <summary>True when the property is present.</summary>
    /// <param name="AName">Property name.</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: IndexOfProp(AName) &gt;= 0.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.DFMB.Support.CheckRequired (DRagLint.V151.DFMB.Support.pas), DRagLint.V151.DFMB.Support.IsPersistentField (DRagLint.V151.DFMB.Support.pas)</para>
    /// <para>Calls: DRagLint.V151.DFMB.Support.TDfmObj.IndexOfProp</para>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmObj.IndexOfProp"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmObj.Create"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmObj.Destroy"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmObj.Val"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Has(const AName: string): Boolean;
  end;

  /// <summary>The parsed text form file; owns every object.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.DFMB.Support.pas) ?, DRagLint.V151.DFMB.Support.CheckCircular (DRagLint.V151.DFMB.Support.pas) ?, DRagLint.V151.DFMB.Support.CheckDupBinding (DRagLint.V151.DFMB.Support.pas) ?, DRagLint.V151.DFMB.Support.TDfmBChecker.Run (DRagLint.V151.DFMB.Support.pas), DRagLint.V151.DFMB.Support.TDfmModel.Parse (DRagLint.V151.DFMB.Support.pas) (+4 more)</para>
  /// <para>Used in units: DRagLint.V151.DFMB.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDfmModel = class
  strict private
    FRoots: TObjectList<TDfmObj>;
    FAll  : TList<TDfmObj>;
    FByName: TDictionary<string, TDfmObj>;
  public
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.DFMB.Support.TDfmModel.Parse (DRagLint.V151.DFMB.Support.pas)</para>
    /// <para>constructor</para>
    /// <para>Writes: FRoots, FAll, FByName</para>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmModel.Add"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmModel.Destroy"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmModel.Find"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmModel.Parse"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create;
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: FByName, FAll, FRoots</para>
    /// <para>Directives: override</para>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmModel.Add"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmModel.Create"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmModel.Find"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmModel.Parse"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    destructor Destroy; override;
    /// <summary>Parses the text of a form file.</summary>
    /// <param name="AText">The file text.</param>
    /// <returns>The model; owned by the caller. Never nil; empty for a binary form.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.DFMB.Support.TDfmBChecker.Run (DRagLint.V151.DFMB.Support.pas)</para>
    /// <para>Calls: Copy, DRagLint.V151.DFMB.Support.ParseHeader, DRagLint.V151.DFMB.Support.ScanSegment, DRagLint.V151.DFMB.Support.StartsWordCI, DRagLint.V151.DFMB.Support.TDfmModel.Add, DRagLint.V151.DFMB.Support.TDfmModel.Create, Pos, SameText, StartsStr, Trim, TrimLeft</para>
    /// <para>Returns: TDfmModel.Create</para>
    /// <para>Complexity: 16 (cyclomatic, outer body), 61 lines (full implementation)</para>
    /// <para>Owns returned: new (caller owns)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.DFMB.Support.ParseHeader"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.ScanSegment"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.StartsWordCI"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmModel.Add"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmModel.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Parse(const AText: string): TDfmModel; static;
    /// <summary>Every object in file order (not owned).</summary>
    property All: TList<TDfmObj> read FAll;
    /// <summary>Looks a component up by name, anywhere in the file.</summary>
    /// <param name="AName">Component name (case-insensitive).</param>
    /// <returns>The object or nil.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.DFMB.Support.CheckCircular.Visit (DRagLint.V151.DFMB.Support.pas), DRagLint.V151.DFMB.Support.CheckRequired (DRagLint.V151.DFMB.Support.pas), DRagLint.V151.DFMB.Support.CheckTypeMismatch (DRagLint.V151.DFMB.Support.pas)</para>
    /// <para>Calls: LowerCase, Trim</para>
    /// <para>Returns: nil</para>
    /// <para>Reads: FByName</para>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmModel.Add"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmModel.Create"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmModel.Destroy"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmModel.Parse"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Find(const AName: string): TDfmObj;
    /// <summary>Adds an object under AParent (nil = root).</summary>
    /// <param name="AObj">The object; ownership passes to the model.</param>
    /// <param name="AParent">Enclosing object or nil.</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.AcquireIndexLock (DRagLint.CLI.pas) ?, DRagLint.CLI.DoQueryUnitUsageProjectWide (DRagLint.CLI.pas) ?, DRagLint.CLI.ExpandProjectScope.AddOnce (DRagLint.CLI.pas) ?, DRagLint.CLI.ProjectScopeRoots.AddDir (DRagLint.CLI.pas) ?, DRagLint.V151.DFMB.Support.TDfmModel.Parse (DRagLint.V151.DFMB.Support.pas) (+53 more)</para>
    /// <para>Calls: LowerCase</para>
    /// <para>Reads: FRoots, FAll, FByName</para>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmModel.Create"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmModel.Destroy"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmModel.Find"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.TDfmModel.Parse"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure Add(AObj, AParent: TDfmObj);
  end;

  /// <summary>Runs the lane's checks over one form file.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.V151.DFMB.TV151DFMBRules.CheckDfm (DRagLint.V151.DFMB.pas)</para>
  /// <para>Used in units: DRagLint.V151.DFMB</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDfmBChecker = class
  public
    /// <summary>Runs every wanted check.</summary>
    /// <param name="ACfg">Run configuration (severity, policy table).</param>
    /// <param name="ADfmPath">The form file; read from disk.</param>
    /// <param name="AWants">Predicate: does this run report the rule id.</param>
    /// <returns>Findings located in ADfmPath.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.Run (DRagLint.CLI.pas) ?, DRagLint.V151.DFMB.TV151DFMBRules.CheckDfm (DRagLint.V151.DFMB.pas)</para>
    /// <para>Calls: AWants, DRagLint.V151.DFMB.Support.CheckCircular, DRagLint.V151.DFMB.Support.CheckDisallowed, DRagLint.V151.DFMB.Support.CheckDupBinding, DRagLint.V151.DFMB.Support.CheckMasterFields, DRagLint.V151.DFMB.Support.CheckRequired, DRagLint.V151.DFMB.Support.CheckTypeMismatch, DRagLint.V151.DFMB.Support.TDfmModel.Parse</para>
    /// <para>Returns: nil; Found.ToArray</para>
    /// <para>Touches: file system</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.DFMB.Support.CheckCircular"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.CheckDisallowed"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.CheckDupBinding"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.CheckMasterFields"/>
    /// <seealso cref="DRagLint.V151.DFMB.Support.CheckRequired"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Run(const ACfg: TLintConfig; const ADfmPath: string;
      const AWants: TFunc<string, Boolean>): TArray<TLintFinding>; static;
  end;

const
  RULE_CIRCULAR  = 'dfm-circular-datasource';
  RULE_DUPBIND   = 'dfm-duplicate-binding';
  RULE_MASTER    = 'dfm-master-without-fields';
  RULE_TYPEMISM  = 'dfm-control-field-type-mismatch';
  RULE_REQUIRED  = 'dfm-required-field-without-control';
  RULE_DISALLOW  = 'disallowed-dfm-property';
  /// <summary>Prefix that marks a "disallowed"."names" entry as a form-file property policy.</summary>
  POLICY_PREFIX  = 'dfm:';
  /// <summary>First bytes of a binary form file; such a file is not read.</summary>
  BINARY_FORM_MAGIC = 'TPF0';

implementation

uses
  System.IOUtils
  , System.StrUtils
  , System.RegularExpressions
  ;

{ ---------------------------------------------------------------- model }

constructor TDfmObj.Create;
begin
  inherited Create;
  FProps:= TList<TDfmProp>.Create;
  FKids:= TObjectList<TDfmObj>.Create(True);
end;

destructor TDfmObj.Destroy;
begin
  FKids.Free;
  FProps.Free;
  inherited Destroy;
end;

function TDfmObj.IndexOfProp(const AName: string): Integer;
begin
  for Result:= 0 to Props.Count - 1 do
    if SameText(Props[Result].Name, AName) then Exit;
  Result:= -1;
end;

function TDfmObj.Val(const AName: string): string;
var
  I: Integer;
begin
  I:= IndexOfProp(AName);
  Result:= if I < 0 then '' else Props[I].Value;
end;

function TDfmObj.Has(const AName: string): Boolean;
begin
  Result:= IndexOfProp(AName) >= 0;
end;

constructor TDfmModel.Create;
begin
  inherited Create;
  FRoots:= TObjectList<TDfmObj>.Create(True);
  FAll:= TList<TDfmObj>.Create;
  FByName:= TDictionary<string, TDfmObj>.Create;
end;

destructor TDfmModel.Destroy;
begin
  FByName.Free;
  FAll.Free;
  FRoots.Free;
  inherited Destroy;
end;

procedure TDfmModel.Add(AObj, AParent: TDfmObj);
begin
  AObj.Parent:= AParent;
  if AParent = nil then FRoots.Add(AObj) else AParent.Kids.Add(AObj);
  FAll.Add(AObj);
  FByName.AddOrSetValue(LowerCase(AObj.ObjName), AObj);
end;

function TDfmModel.Find(const AName: string): TDfmObj;
begin
  if not FByName.TryGetValue(LowerCase(Trim(AName)), Result) then Result:= nil;
end;

{ Scans one segment of a value, updating the bracket depth and the string state;
  returns True when the segment ends with a concatenation '+' outside a string. }
function ScanSegment(const ASeg: string; var ADepth: Integer; var AInStr: Boolean): Boolean;
var
  I   : Integer;
  Last: Char;
begin
  Last:= ' ';
  for I:= 1 to Length(ASeg) do
  begin
    if ASeg[I] = '''' then AInStr:= not AInStr
    else if not AInStr then
      case ASeg[I] of
        '(', '<', '{', '[': Inc(ADepth);
        ')', '>', '}', ']': Dec(ADepth);
      end;
    if (ASeg[I] <> ' ') and (ASeg[I] <> #9) then Last:= ASeg[I];
  end;
  Result:= (not AInStr) and (Last = '+');
end;

function StartsWordCI(const ALine, AWord: string): Boolean;
begin
  Result:= (Length(ALine) > Length(AWord)) and SameText(Copy(ALine, 1, Length(AWord)), AWord)
    and CharInSet(ALine[Length(AWord) + 1], [' ', #9]);
end;

{ Parses 'object Name: TClass [n]' (also inherited / inline) into AObj. }
function ParseHeader(const ALine: string; ALineNo: Integer; out AObj: TDfmObj): Boolean;
var
  Rest, NamePart, ClsPart: string;
  P: Integer;
begin
  Result:= False;
  AObj:= nil;
  P:= Pos(' ', ALine);
  if P = 0 then Exit;
  Rest:= Trim(Copy(ALine, P + 1, MaxInt));
  P:= Pos(':', Rest);
  if P = 0 then
  begin
    NamePart:= Rest;
    ClsPart:= '';
  end
  else
  begin
    NamePart:= Trim(Copy(Rest, 1, P - 1));
    ClsPart:= Trim(Copy(Rest, P + 1, MaxInt));
    P:= Pos(' ', ClsPart);
    if P > 0 then ClsPart:= Copy(ClsPart, 1, P - 1);
  end;
  AObj:= TDfmObj.Create;
  AObj.ObjName:= NamePart;
  AObj.ClsName:= ClsPart;
  AObj.Line:= ALineNo;
  Result:= True;
end;

class function TDfmModel.Parse(const AText: string): TDfmModel;
var
  Lines  : TStringList;
  I, EqP : Integer;
  Raw, T : string;
  Stack  : TList<TDfmObj>;
  Obj    : TDfmObj;
  Prop   : TDfmProp;
  Depth  : Integer;
  InStr  : Boolean;
  More   : Boolean;
begin
  Result:= TDfmModel.Create;
  if StartsStr(BINARY_FORM_MAGIC, AText) then Exit;
  Lines:= TStringList.Create;
  Stack:= TList<TDfmObj>.Create;
  try
    Lines.Text:= AText;
    I:= 0;
    while I < Lines.Count do
    begin
      Raw:= Lines[I];
      T:= Trim(Raw);
      Inc(I);
      if T = '' then Continue;
      if StartsWordCI(T, 'object') or StartsWordCI(T, 'inherited') or StartsWordCI(T, 'inline') then
      begin
        if ParseHeader(T, I, Obj) then
        begin
          if Stack.Count > 0 then Result.Add(Obj, Stack[Stack.Count - 1]) else Result.Add(Obj, nil);
          Stack.Add(Obj);
        end;
        Continue;
      end;
      if SameText(T, 'end') then
      begin
        if Stack.Count > 0 then Stack.Delete(Stack.Count - 1);
        Continue;
      end;
      EqP:= Pos('=', T);
      if (EqP = 0) or (Stack.Count = 0) then Continue;
      Prop.Name:= Trim(Copy(T, 1, EqP - 1));
      Prop.Value:= Trim(Copy(T, EqP + 1, MaxInt));
      Prop.Line:= I;
      Prop.Col:= Length(Raw) - Length(TrimLeft(Raw)) + 1;
      Depth:= 0;
      InStr:= False;
      More:= ScanSegment(Prop.Value, Depth, InStr);
      while ((Depth > 0) or More) and (I < Lines.Count) do
      begin
        T:= Trim(Lines[I]);
        Inc(I);
        Prop.Value:= Prop.Value + #10 + T;
        More:= ScanSegment(T, Depth, InStr);
      end;
      Stack[Stack.Count - 1].Props.Add(Prop);
    end;
  finally
    Stack.Free;
    Lines.Free;
  end;
end;

{ ---------------------------------------------------------------- helpers }

{ 'abc' -> abc (single simple literal); other values unchanged. }
function Unq(const AValue: string): string;
begin
  Result:= Trim(AValue);
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
    Result:= StringReplace(Copy(Result, 2, Length(Result) - 2), '''''', '''', [rfReplaceAll]);
end;

function IsFalse(const AValue: string): Boolean;
begin
  Result:= SameText(Trim(AValue), 'False');
end;

function IsTrue(const AValue: string): Boolean;
begin
  Result:= SameText(Trim(AValue), 'True');
end;

function HasPart(const AClass: string; const AParts: array of string): Boolean;
var
  S: string;
begin
  for S in AParts do
    if ContainsText(AClass, S) then Exit(True);
  Result:= False;
end;

{ The data source / field a data-aware control names; both flat and DataBinding.* spellings. }
function BindSource(const AObj: TDfmObj): string;
begin
  Result:= Unq(AObj.Val('DataSource'));
  if Result = '' then Result:= Unq(AObj.Val('DataBinding.DataSource'));
end;

function BindField(const AObj: TDfmObj): string;
begin
  Result:= Unq(AObj.Val('DataField'));
  if Result = '' then Result:= Unq(AObj.Val('DataBinding.DataField'));
end;

function BindFieldLine(const AObj: TDfmObj): Integer;
var
  I: Integer;
begin
  I:= AObj.IndexOfProp('DataField');
  if I < 0 then I:= AObj.IndexOfProp('DataBinding.DataField');
  Result:= if I < 0 then AObj.Line else AObj.Props[I].Line;
end;

function NewFinding(const ACfg: TLintConfig; const ARule, AFile, ADefaultSev, AMsg: string;
  ALine, ACol: Integer): TLintFinding;
begin
  Result:= Default(TLintFinding);
  Result.RuleId   := ARule;
  Result.FilePath := AFile;
  Result.StartLine:= ALine;
  Result.StartCol := ACol;
  Result.EndLine  := ALine;
  Result.EndCol   := ACol + 1;
  Result.Severity := ACfg.ApplySeverity(ARule, ADefaultSev);
  Result.Message  := AMsg;
end;

function VisibleChain(const AObj: TDfmObj): Boolean;
var
  O: TDfmObj;
begin
  O:= AObj;
  while O <> nil do
  begin
    if IsFalse(O.Val('Visible')) then Exit(False);
    O:= O.Parent;
  end;
  Result:= True;
end;

{ ------------------------------------------------- control / field kinds }

type
  TCtlKind = (ckNone, ckEdit, ckNumeric, ckDate, ckImage, ckCheck, ckMemo, ckCombo);
  TFldKind = (fkOther, fkBool, fkNum, fkDate, fkString, fkMemo, fkBlob, fkGraphic);

function CtlKindOf(const AClass: string): TCtlKind;
begin
  if not HasPart(AClass, ['DB'])
    or HasPart(AClass, ['Navigator', 'Grid', 'Lookup', 'Chart', 'Radio', 'Column', 'StaticText'])
    or EndsText('DBText', AClass) or EndsText('DBLabel', AClass) then Result:= ckNone
  else if HasPart(AClass, ['Image']) then Result:= ckImage
  else if HasPart(AClass, ['CheckBox']) then Result:= ckCheck
  else if HasPart(AClass, ['Memo', 'RichEdit']) then Result:= ckMemo
  else if HasPart(AClass, ['ComboBox']) then Result:= ckCombo
  else if HasPart(AClass, ['DateEdit', 'DateTime', 'TimeEdit', 'Calendar']) then Result:= ckDate
  else if HasPart(AClass, ['SpinEdit', 'CurrencyEdit', 'CalcEdit']) then Result:= ckNumeric
  else if HasPart(AClass, ['TextEdit', 'MaskEdit', 'ButtonEdit', 'DBEdit']) then Result:= ckEdit  // dl:ok ifthen-to-if-expression@4ec8 -- REVIEWED 2026-11-14 v151 INT: classic if/else kept in a lane unit written before the ternary sweep
  else Result:= ckNone;
end;

function FldKindOf(const AClass: string): TFldKind;
begin
  if HasPart(AClass, ['Boolean']) then Result:= fkBool
  else if HasPart(AClass, ['Graphic']) then Result:= fkGraphic
  else if HasPart(AClass, ['Memo']) then Result:= fkMemo
  else if SameText(AClass, 'TBlobField') or HasPart(AClass, ['VarBytes', 'BytesField', 'BinaryField']) then Result:= fkBlob
  else if HasPart(AClass, ['StringField', 'WideStringField', 'AnsiStringField', 'GuidField']) then Result:= fkString
  else if HasPart(AClass, ['DateTime', 'DateField', 'TimeField', 'TimeStamp']) then Result:= fkDate
  else if HasPart(AClass, ['IntegerField', 'SmallintField', 'LargeintField', 'WordField', 'AutoInc', 'FloatField',  // dl:ok ifthen-to-if-expression@117a -- REVIEWED 2026-11-14 v151 INT: classic if/else kept in a lane unit written before the ternary sweep
    'CurrencyField', 'BCDField', 'FMTBCD', 'SingleField', 'ExtendedField', 'ShortintField', 'ByteField',
    'LongWordField', 'UInt32Field', 'Int64Field']) then Result:= fkNum
  else Result:= fkOther;
end;

function KindMismatch(AField: TFldKind; ACtl: TCtlKind): Boolean;
begin
  case AField of
    fkBlob, fkGraphic: Result:= ACtl <> ckImage;
    fkBool:            Result:= ACtl in [ckEdit, ckNumeric, ckDate, ckImage, ckMemo];
    fkNum:             Result:= ACtl in [ckImage, ckDate];
    fkDate:            Result:= ACtl in [ckImage, ckNumeric];
    fkString:          Result:= ACtl = ckImage;
    fkMemo:            Result:= ACtl in [ckImage, ckNumeric, ckDate, ckCheck];
  else
    Result:= False;
  end;
end;

function FldKindName(AKind: TFldKind): string;
begin
  case AKind of
    fkBool:    Result:= 'boolean';
    fkNum:     Result:= 'numeric';
    fkDate:    Result:= 'date/time';
    fkString:  Result:= 'string';
    fkMemo:    Result:= 'memo';
    fkBlob:    Result:= 'binary (blob)';
    fkGraphic: Result:= 'graphic';
  else
    Result:= 'other';
  end;
end;

function IsPersistentField(const AObj: TDfmObj): Boolean;
begin
  Result:= AObj.Has('FieldName') and AObj.Has('DataSet') and ContainsText(AObj.ClsName, 'Field');
end;

{ ------------------------------------------------------------ the rules }

type
  TFindingList = TList<TLintFinding>;

procedure CheckCircular(const AModel: TDfmModel; const ACfg: TLintConfig; const AFile: string; AOut: TFindingList);
const
  EDGE_PROPS: array[0..3] of string = ('DataSet', 'MasterSource', 'DataSource', 'DataSetField');
var
  Color : TDictionary<TDfmObj, Integer>;
  Path  : TList<TDfmObj>;
  Seen  : TDictionary<string, Boolean>;

  procedure Visit(AObj: TDfmObj);
  var
    P    : string;
    Next : TDfmObj;
    St   : Integer;
    K, S : Integer;
    Names: TStringList;
    Key, Msg: string;
    Anchor: TDfmObj;
    O    : TDfmObj;
  begin
    Color.AddOrSetValue(AObj, 1);
    Path.Add(AObj);
    for P in EDGE_PROPS do
    begin
      Next:= AModel.Find(Unq(AObj.Val(P)));
      if Next = nil then Continue;
      if not Color.TryGetValue(Next, St) then St:= 0;
      if St = 0 then Visit(Next)
      else if St = 1 then
      begin
        S:= Path.IndexOf(Next);
        Names:= TStringList.Create;
        try
          Anchor:= Next;
          Msg:= '';
          for K:= S to Path.Count - 1 do
          begin
            O:= Path[K];
            Names.Add(LowerCase(O.ObjName));
            Msg:= Msg + O.ObjName + ' -> ';
            if O.Line < Anchor.Line then Anchor:= O;
          end;
          Msg:= Msg + Next.ObjName;
          Names.Sort;
          Key:= Names.CommaText;
          if not Seen.ContainsKey(Key) then
          begin
            Seen.Add(Key, True);
            AOut.Add(NewFinding(ACfg, RULE_CIRCULAR, AFile, 'warning',
              'Master/detail data source links form a cycle (' + Msg + '); opening the datasets never settles',
              Anchor.Line, 1));
          end;
        finally
          Names.Free;
        end;
      end;
    end;
    Path.Delete(Path.Count - 1);
    Color.AddOrSetValue(AObj, 2);
  end;

var
  O: TDfmObj;
  St: Integer;
begin
  Color:= TDictionary<TDfmObj, Integer>.Create;
  Path:= TList<TDfmObj>.Create;
  Seen:= TDictionary<string, Boolean>.Create;
  try
    for O in AModel.All do
      if not Color.TryGetValue(O, St) then Visit(O);
  finally
    Seen.Free;
    Path.Free;
    Color.Free;
  end;
end;

/// <summary>Blanks comments and string literals of Pascal source (same length, newlines kept).</summary>
/// <param name="ASrc">Pascal unit text.</param>
/// <returns>The text with every comment and string body replaced by spaces.</returns>
function BlankPasNoise(const ASrc: string): string;
var
  I, N: Integer;
  C   : Char;
begin
  Result:= ASrc;
  N:= Length(Result);
  I:= 1;
  while I <= N do
  begin
    C:= Result[I];
    if C = '''' then
    begin
      Result[I]:= ' ';
      Inc(I);
      while (I <= N) and (Result[I] <> '''') and (Result[I] <> #10) do
      begin
        Result[I]:= ' ';
        Inc(I);
      end;
      if (I <= N) and (Result[I] = '''') then
      begin
        Result[I]:= ' ';
        Inc(I);
      end;
    end
    else if (C = '/') and (I < N) and (Result[I + 1] = '/') then
      while (I <= N) and (Result[I] <> #10) do
      begin
        Result[I]:= ' ';
        Inc(I);
      end
    else if C = '{' then
    begin
      while (I <= N) and (Result[I] <> '}') do
      begin
        if Result[I] <> #10 then Result[I]:= ' ';
        Inc(I);
      end;
      if I <= N then Result[I]:= ' ';
      Inc(I);
    end
    else if (C = '(') and (I < N) and (Result[I + 1] = '*') then
    begin
      while (I < N) and not ((Result[I] = '*') and (Result[I + 1] = ')')) do
      begin
        if Result[I] <> #10 then Result[I]:= ' ';
        Inc(I);
      end;
      if I < N then
      begin
        Result[I]:= ' ';
        Result[I + 1]:= ' ';
      end;
      Inc(I, 2);
    end
    else
      Inc(I);
  end;
end;

/// <summary>Collects the components whose DataField the owning unit assigns in code.</summary>
/// <param name="ADfmPath">Path of the form file; the paired unit is the same base name with .pas.</param>
/// <returns>Lower-case component names assigned as Comp.DataField:= or Comp.DataBinding.DataField:=; empty when there is no paired unit.</returns>
/// <remarks>Reads only the paired unit's own source (comments and strings blanked); an assignment in any other unit is deliberately not seen.</remarks>
function CodeBoundFields(const ADfmPath: string): TDictionary<string, Boolean>;
var
  PasPath: string;
  M      : TMatch;
begin
  Result:= TDictionary<string, Boolean>.Create;
  PasPath:= ChangeFileExt(ADfmPath, '.pas');
  if not TFile.Exists(PasPath) then Exit;
  for M in TRegEx.Matches(BlankPasNoise(TFile.ReadAllText(PasPath, TEncoding.ANSI)),
    '\b([A-Za-z_]\w*)\s*\.\s*(?:DataBinding\s*\.\s*)?DataField\s*:=', [roIgnoreCase]) do
    Result.AddOrSetValue(LowerCase(M.Groups[1].Value), True);
end;

procedure CheckDupBinding(const AModel: TDfmModel; const ACfg: TLintConfig; const AFile: string;
  const ACodeBound: TDictionary<string, Boolean>; AOut: TFindingList);
var
  First: TDictionary<string, TDfmObj>;
  O, F : TDfmObj;
  Key  : string;
begin
  First:= TDictionary<string, TDfmObj>.Create;
  try
    for O in AModel.All do
    begin
      if CtlKindOf(O.ClsName) = ckNone then Continue;
      if BindSource(O) = '' then Continue;
      if BindField(O) = '' then Continue;
      if ACodeBound.ContainsKey(LowerCase(O.ObjName)) then Continue;
      if IsTrue(O.Val('ReadOnly')) or IsTrue(O.Val('Properties.ReadOnly')) or not VisibleChain(O) then Continue;
      Key:= LowerCase(BindSource(O)) + '|' + LowerCase(BindField(O));
      if First.TryGetValue(Key, F) then
        AOut.Add(NewFinding(ACfg, RULE_DUPBIND, AFile, 'warning',
          O.ObjName + ' is bound to ' + BindSource(O) + '.' + BindField(O) + ', which ' + F.ObjName +
          ' (line ' + IntToStr(F.Line) + ') already edits; one of the two is probably a copy-and-paste slip',
          BindFieldLine(O), 1))
      else
        First.Add(Key, O);
    end;
  finally
    First.Free;
  end;
end;

{ True for a property that makes a dataset query-like: its parameters link to the master by name. }
function IsQueryProp(const AName: string): Boolean;
begin
  Result:= StartsText('SQL', AName) or StartsText('SelectSQL', AName) or StartsText('Command', AName)  // dl:ok boolean-expression-complexity@d922 -- REVIEWED 2026-11-14 v151 INT: one flat predicate over fixed values; splitting it does not make it clearer
    or SameText(AName, 'Params') or SameText(AName, 'ProviderName') or StartsText('Proc', AName);
end;

procedure CheckMasterFields(const AModel: TDfmModel; const ACfg: TLintConfig; const AFile: string; AOut: TFindingList);
var
  O: TDfmObj;
  I: Integer;
  QueryLike: Boolean;
  N: string;
begin
  for O in AModel.All do
  begin
    if Unq(O.Val('MasterSource')) = '' then Continue;
    if Unq(O.Val('MasterFields')) <> '' then Continue;
    QueryLike:= False;
    for I:= 0 to O.Props.Count - 1 do
    begin
      N:= O.Props[I].Name;
      if IsQueryProp(N) then QueryLike:= True;
    end;
    if QueryLike then Continue;
    I:= O.IndexOfProp('MasterSource');
    AOut.Add(NewFinding(ACfg, RULE_MASTER, AFile, 'warning',
      O.ObjName + ' has MasterSource ' + Unq(O.Props[I].Value) + ' but no MasterFields: the detail is not filtered and shows every record',
      O.Props[I].Line, O.Props[I].Col));
  end;
end;

{ Field objects of one dataset by lower field name. }
function FieldKey(const ADataSet, AField: string): string;
begin
  Result:= LowerCase(ADataSet) + '|' + LowerCase(AField);
end;

procedure CheckTypeMismatch(const AModel: TDfmModel; const ACfg: TLintConfig; const AFile: string; AOut: TFindingList);
var
  Fields: TDictionary<string, TDfmObj>;
  O, Src, Fld: TDfmObj;
  CK: TCtlKind;
begin
  Fields:= TDictionary<string, TDfmObj>.Create;
  try
    for O in AModel.All do
      if IsPersistentField(O) then
        Fields.AddOrSetValue(FieldKey(Unq(O.Val('DataSet')), Unq(O.Val('FieldName'))), O);
    if Fields.Count = 0 then Exit;
    for O in AModel.All do
    begin
      CK:= CtlKindOf(O.ClsName);
      if CK = ckNone then Continue;
      if (BindSource(O) = '') or (BindField(O) = '') then Continue;
      Src:= AModel.Find(BindSource(O));
      if Src = nil then Continue;
      if not Fields.TryGetValue(FieldKey(Unq(Src.Val('DataSet')), BindField(O)), Fld) then Continue;
      if KindMismatch(FldKindOf(Fld.ClsName), CK) then
        AOut.Add(NewFinding(ACfg, RULE_TYPEMISM, AFile, 'warning',
          O.ClsName + ' ' + O.ObjName + ' is bound to ' + Fld.ObjName + ', a ' + FldKindName(FldKindOf(Fld.ClsName)) +
          ' field (' + Fld.ClsName + '); the control does not suit that field type',
          BindFieldLine(O), 1));
    end;
  finally
    Fields.Free;
  end;
end;

{ Field names a grid column collection lists (items with Visible = False dropped). }
procedure CollectColumnFields(const AValue: string; ANames: TStringList);
var
  Lines: TStringList;
  L, T, Cur: string;
  CurHidden: Boolean;

  procedure Flush;
  begin
    if (Cur <> '') and not CurHidden then ANames.Add(LowerCase(Cur));
    Cur:= '';
    CurHidden:= False;
  end;

begin
  Lines:= TStringList.Create;
  try
    Lines.Text:= StringReplace(AValue, #10, sLineBreak, [rfReplaceAll]);
    Cur:= '';
    CurHidden:= False;
    for L in Lines do
    begin
      T:= Trim(L);
      if SameText(T, 'item') or SameText(T, '<item') then Flush
      else if StartsText('FieldName', T) and ContainsStr(T, '=') then Cur:= Unq(Copy(T, Pos('=', T) + 1, MaxInt))
      else if StartsText('Visible', T) and ContainsText(T, 'False') then CurHidden:= True;
    end;
    Flush;
  finally
    Lines.Free;
  end;
end;

type
  TCover = class
  strict private
    FAll  : Boolean;
    FNames: TStringList;
    FUsed : Boolean;
  public
    property All: Boolean read FAll write FAll;
    property Names: TStringList read FNames;
    property Used: Boolean read FUsed write FUsed;
    constructor Create;
    destructor Destroy; override;
  end;

constructor TCover.Create;
begin
  inherited Create;
  FNames:= TStringList.Create;
end;

destructor TCover.Destroy;
begin
  FNames.Free;
  inherited Destroy;
end;

procedure CheckRequired(const AModel: TDfmModel; const ACfg: TLintConfig; const AFile: string; AOut: TFindingList);
var
  Cover: TObjectDictionary<string, TCover>;
  O, Src, DS: TDfmObj;
  C: TCover;
  DsName, K, FldName: string;
  Names: TStringList;
  I: Integer;

  function CoverOf(const ADataSet: string): TCover;
  begin
    if not Cover.TryGetValue(LowerCase(ADataSet), Result) then
    begin
      Result:= TCover.Create;
      Cover.Add(LowerCase(ADataSet), Result);
    end;
  end;

begin
  Cover:= TObjectDictionary<string, TCover>.Create([doOwnsValues]);
  try
    for O in AModel.All do
    begin
      DsName:= if BindSource(O) = '' then Unq(O.Val('DataController.DataSource')) else BindSource(O);
      if DsName = '' then Continue;
      Src:= AModel.Find(DsName);
      if (Src = nil) or (Unq(Src.Val('DataSet')) = '') then Continue;
      C:= CoverOf(Unq(Src.Val('DataSet')));
      C.Used:= True;
      if not VisibleChain(O) then Continue;
      if HasPart(O.ClsName, ['Grid', 'TableView', 'CardView']) and not HasPart(O.ClsName, ['CtrlGrid']) then
      begin
        if O.Has('Columns') then
          CollectColumnFields(O.Val('Columns'), C.Names)
        else
        begin
          { cx-style views keep their columns as child objects }
          Names:= TStringList.Create;
          try
            for DS in O.Kids do
              if HasPart(DS.ClsName, ['Column']) and not IsFalse(DS.Val('Visible')) then
                Names.Add(LowerCase(Unq(DS.Val('DataBinding.FieldName'))));
            if Names.Count = 0 then C.All:= True else C.Names.AddStrings(Names);
          finally
            Names.Free;
          end;
        end;
      end
      else if BindField(O) <> '' then
        C.Names.Add(LowerCase(BindField(O)));
    end;
    for O in AModel.All do
    begin
      if not IsPersistentField(O) or not IsTrue(O.Val('Required')) then Continue;
      if IsTrue(O.Val('ReadOnly')) or O.Has('DefaultExpression') or O.Has('AutoGenerateValue')
        or HasPart(O.ClsName, ['AutoInc']) then Continue;
      if O.Has('FieldKind') and not SameText(Trim(O.Val('FieldKind')), 'fkData') then Continue;
      if not Cover.TryGetValue(LowerCase(Unq(O.Val('DataSet'))), C) then Continue;
      if not C.Used or C.All then Continue;
      FldName:= LowerCase(Unq(O.Val('FieldName')));
      K:= FldName;
      I:= C.Names.IndexOf(K);
      if I >= 0 then Continue;
      AOut.Add(NewFinding(ACfg, RULE_REQUIRED, AFile, 'warning',
        'Field ' + Unq(O.Val('FieldName')) + ' of ' + Unq(O.Val('DataSet')) + ' is Required but no visible data-aware control edits it; '
        + 'the user cannot satisfy the requirement',
        O.Props[O.IndexOfProp('Required')].Line, 1));
    end;
  finally
    Cover.Free;
  end;
end;

{ ------------------------------------------------------------- policy }

procedure CheckDisallowed(const AModel: TDfmModel; const ACfg: TLintConfig; const AFile: string; AOut: TFindingList);
var
  E: TDisallowedEntry;
  Body, ClsPat, PropPat, ValPat: string;
  P: Integer;
  O: TDfmObj;
  Pr: TDfmProp;
  Msg: string;
begin
  for E in ACfg.DisallowedNames do
  begin
    if not StartsText(POLICY_PREFIX, E.Name) then Continue;
    if (Length(E.Exempt) > 0) and TLintConfig.MatchesAnyGlob(AFile, E.Exempt) then Continue;
    Body:= Trim(Copy(E.Name, Length(POLICY_PREFIX) + 1, MaxInt));
    ValPat:= '';
    P:= Pos('=', Body);
    if P > 0 then
    begin
      ValPat:= Unq(Copy(Body, P + 1, MaxInt));
      Body:= Trim(Copy(Body, 1, P - 1));
    end;
    P:= Pos('.', Body);
    if P = 0 then Continue;
    ClsPat:= Trim(Copy(Body, 1, P - 1));
    PropPat:= Trim(Copy(Body, P + 1, MaxInt));
    if (ClsPat = '') or (PropPat = '') then Continue;
    for O in AModel.All do
    begin
      if (ClsPat <> '*') and not SameText(ClsPat, O.ClsName) then Continue;
      for Pr in O.Props do
      begin
        if not SameText(Pr.Name, PropPat) then Continue;
        if (ValPat <> '') and not SameText(Unq(Pr.Value), ValPat) then Continue;
        Msg:= O.ClsName + '.' + Pr.Name + ' (' + O.ObjName + ') is disallowed in form files by project policy';
        if E.Reason <> '' then Msg:= Msg + ' -- ' + E.Reason;
        AOut.Add(NewFinding(ACfg, RULE_DISALLOW, AFile, 'warning', Msg, Pr.Line, Pr.Col));
      end;
    end;
  end;
end;

{ TDfmBChecker }

class function TDfmBChecker.Run(const ACfg: TLintConfig; const ADfmPath: string;
  const AWants: TFunc<string, Boolean>): TArray<TLintFinding>;
var
  Model: TDfmModel;
  Found : TFindingList;
  CodeBound: TDictionary<string, Boolean>;
begin
  Result:= nil;
  if not TFile.Exists(ADfmPath) then Exit;
  Model:= TDfmModel.Parse(TEncoding.ANSI.GetString(TFile.ReadAllBytes(ADfmPath)));
  Found:= TFindingList.Create;
  try
    if AWants(RULE_CIRCULAR) then CheckCircular(Model, ACfg, ADfmPath, Found);
    if AWants(RULE_DUPBIND) then
    begin
      CodeBound:= CodeBoundFields(ADfmPath);
      try
        CheckDupBinding(Model, ACfg, ADfmPath, CodeBound, Found);
      finally
        CodeBound.Free;
      end;
    end;
    if AWants(RULE_MASTER) then CheckMasterFields(Model, ACfg, ADfmPath, Found);
    if AWants(RULE_TYPEMISM) then CheckTypeMismatch(Model, ACfg, ADfmPath, Found);
    if AWants(RULE_REQUIRED) then CheckRequired(Model, ACfg, ADfmPath, Found);
    if AWants(RULE_DISALLOW) then CheckDisallowed(Model, ACfg, ADfmPath, Found);
    Result:= Found.ToArray;
  finally
    Found.Free;
    Model.Free;
  end;
end;

end.
