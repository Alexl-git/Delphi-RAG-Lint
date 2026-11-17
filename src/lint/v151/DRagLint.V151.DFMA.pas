unit DRagLint.V151.DFMA;

{ Wave v151 lane DFMA -- form/unit consistency rules A (form fields vs form objects, form resources, autocreate, cross-form access, self-free in handlers).
  Lane DFMA owns this unit, its DRagLint.V151.DFMA.Support helpers and
  DRagLint.Fix.V151.DFMA. Called only by DRagLint.V151.Dispatch.
  How-to: C:\TEMP\claude\lanes\v151\FRAME\HOWTO-RULE-LANE.md. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

const
  /// <summary>Rule ids of this lane, as `rules --json`, `--rule` and dl:ok markers spell them.</summary>
  RULE_FIELD_TYPE_MISMATCH   = 'form-field-type-mismatch';
  RULE_FIELD_WITHOUT_OBJECT  = 'form-field-without-object';
  RULE_OBJECT_WITHOUT_FIELD  = 'form-object-without-field';
  RULE_RESOURCE_MISSING      = 'form-resource-missing';
  RULE_HANDLER_NO_INHERITED  = 'inherited-form-handler-without-inherited';
  RULE_AUTOCREATE_AND_MANUAL = 'form-autocreate-and-manual';
  RULE_ACCESS_BEFORE_CREATE  = 'form-access-before-create';
  RULE_FOREIGN_FORM_ACCESS   = 'foreign-form-control-access';
  RULE_SELF_FREE_IN_HANDLER  = 'self-free-in-event-handler';
  /// <summary>Host rule this lane widens to the form file side (a component reference
  /// `Prop = Module.Component` whose module's unit is not used).</summary>
  RULE_HOST_UNIT_MISSING     = 'unit-missing-from-uses';

type
  /// <summary>Checker entry points of v151 lane DFMA; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.
  /// Every rule reads the unit through the shared parse cache and its sibling .dfm as text;
  /// a binary .dfm, a unit that does not declare the form file's root class, or a lookup that
  /// cannot be answered keeps the rule silent. The index (Store / LibStore) only widens what
  /// can be answered: ancestor chains, unit files of other modules, the project's .dpr.</remarks>
  TV151DFMARules = class
  public
    /// <summary>Declares every rule id this lane may emit: the nine form rules and the host
    /// id unit-missing-from-uses (form-file side).</summary>
    /// <param name="ADecls">List to append to; owned by the caller.</param>
    /// <remarks>Called ONCE at start-up (unit initialization of DRagLint.V151.Dispatch); must not touch files or stores.</remarks>
    class procedure Catalog(const ADecls: TList<TV151RuleDecl>); static;
    /// <summary>Per-file checks that need the .dpr or other units:
    /// form-autocreate-and-manual (a global form variable the .dpr creates with
    /// Application.CreateForm is also assigned TClass.Create(...) here),
    /// form-access-before-create (a constructor, AfterConstruction or OnCreate handler of an
    /// auto-created module reads the global variable of a module the .dpr creates later) and
    /// foreign-form-control-access (Form2.Edit1 through another unit's global form variable).</summary>
    /// <param name="ACtx">The file being linted; Store / LibStore may be nil.</param>
    /// <returns>Findings; nil when none.</returns>
    class function CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Checks of the unit against its sibling form file: form-field-without-object,
    /// form-object-without-field, form-field-type-mismatch, form-resource-missing,
    /// inherited-form-handler-without-inherited, self-free-in-event-handler and the form-file
    /// side of unit-missing-from-uses.</summary>
    /// <param name="ACtx">The file being linted; ACtx.DfmPath is not empty when this is called.</param>
    /// <returns>Findings (FilePath is the .dfm for findings about a form object or property); nil when none.</returns>
    class function CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Nothing to check on raw bytes in this lane.</summary>
    /// <param name="ACtx">The file being linted.</param>
    /// <param name="AFilePath">The file the bytes come from (ACtx.Path or ACtx.DfmPath).</param>
    /// <param name="ABytes">The file content exactly as on disk.</param>
    /// <returns>nil.</returns>
    class function CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>; static;
    /// <summary>Nothing project-wide in this lane: every rule runs per file in lint and lint-all alike.</summary>
    /// <param name="ACtx">The project; Store is not nil.</param>
    /// <returns>nil.</returns>
    class function CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.StrUtils
  , System.IOUtils
  , System.RegularExpressions
  , TreeSitter
  , DRagLint.V151.DFMA.Support
  , DRagLint.V152.DEFAULTS
  , DRagLint.V151.Dfm.Common
  ;

const
  SEV_WARNING = 'warning';
  SEV_HINT    = 'hint';
  MAX_FORM_DEPTH = 8;

class procedure TV151DFMARules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(RULE_FIELD_TYPE_MISMATCH, 'bug-patterns', SEV_WARNING,
    'A published form field is declared with a class the form file''s object of that name is not -- the field holds an object of another class'));
  ADecls.Add(V151Rule(RULE_FIELD_WITHOUT_OBJECT, 'bug-patterns', SEV_WARNING,
    'A published field of the form class has no object of that name in the form file -- it stays nil after the form loads'));
  ADecls.Add(V151Rule(RULE_OBJECT_WITHOUT_FIELD, 'bug-patterns', SEV_HINT,
    'An object of the form file has no field in the form class -- code cannot reach it by name and the designer re-adds the field',
    True));  // ON (v152 DEFAULTS C6: DevExpress sub-objects without a field are exempted by rules\form-object-without-field.exempt.txt + project exempt_classes)
  ADecls.Add(V151Rule(RULE_RESOURCE_MISSING, 'bug-patterns', SEV_WARNING,
    'The unit declares the class of its form file but includes no form resource ({$R *.dfm}) -- creating the form raises EResNotFound'));
  ADecls.Add(V151Rule(RULE_HANDLER_NO_INHERITED, 'bug-patterns', SEV_WARNING,
    'An inherited form re-declares an event handler of its ancestor form under the same name without calling inherited -- the ancestor''s handler no longer runs'));
  ADecls.Add(V151Rule(RULE_AUTOCREATE_AND_MANUAL, 'bug-patterns', SEV_WARNING,
    'The .dpr auto-creates a form and the code also assigns a new instance to the same global variable -- the first instance is orphaned'));
  ADecls.Add(V151Rule(RULE_ACCESS_BEFORE_CREATE, 'bug-patterns', SEV_WARNING,
    'The creation code of an auto-created form or data module reads the global variable of a module the .dpr creates later -- it is still nil'));
  ADecls.Add(V151Rule(RULE_FOREIGN_FORM_ACCESS, 'structure', SEV_HINT,
    'Code reaches a control of another unit''s form through its global variable (Form2.Edit1) -- the units are coupled to the form layout', True));  // ON (v152 DEFAULTS B9g)
  ADecls.Add(V151Rule(RULE_SELF_FREE_IN_HANDLER, 'bug-patterns', SEV_WARNING,
    'A form frees itself in its own event handler -- the VCL still uses the object after the handler returns; use Release'));
  ADecls.Add(V151Host(RULE_HOST_UNIT_MISSING));
end;

{ ---------------------------------------------------------------------------
  shared helpers
  --------------------------------------------------------------------------- }

{ The class of the unit that the form file's root object names; -1 when the unit does
  not declare it (then every form-file rule is silent). }
function RootClassIndex(const AUnit: TPasUnit; const ADfm: TDfmDoc): Integer;
begin
  Result:= -1;
  if ADfm.IsEmpty or not AUnit.Ok then Exit;
  Result:= AUnit.ClassIndex(ADfm.Nodes[0].CompClass);
end;

{ Calls AVisit on every descendant of N, not entering anonymous methods, nor (when
  ASkipWith) with statements; AVisit returns False to stop the walk. }
type
  TNodeVisit = reference to function(const N: TTSNode): Boolean;

function WalkNodes(const N: TTSNode; ASkipWith: Boolean; const AVisit: TNodeVisit): Boolean;
begin
  Result:= True;
  if N.IsNull then Exit;
  if N.NodeType = 'lambda' then Exit;
  if ASkipWith and (N.NodeType = 'with') then Exit;
  if not AVisit(N) then Exit(False);
  for var I:= 0 to N.NamedChildCount - 1 do
    if not WalkNodes(N.NamedChild(I), ASkipWith, AVisit) then Exit(False);
end;

{ ---------------------------------------------------------------------------
  form-field-without-object / form-object-without-field / form-field-type-mismatch
  --------------------------------------------------------------------------- }

/// Lower-cased names the unit's routines assign (`X := ...` or `Self.X := ...`).
function AssignedNames(const AUnit: TPasUnit): THashSet<string>;
begin
  var Names: THashSet<string>:= THashSet<string>.Create;
  for var R in AUnit.Routines do
    WalkNodes(R.Body, False,
      function(const N: TTSNode): Boolean
      begin
        Result:= True;
        if N.NodeType <> 'assignment' then Exit;
        var L: TTSNode:= N.ChildByField('lhs');
        if L.NodeType = 'exprDot' then
        begin
          if not SameText(AUnit.Text(L.ChildByField('lhs')), 'Self') then Exit;
          L:= L.ChildByField('rhs');
        end;
        if L.NodeType = 'identifier' then Names.Add(LowerCase(AUnit.Text(L)));
      end);
  Result:= Names;
end;

/// Published fields of the root class with no node of that name anywhere in the form file
/// and no assignment in the unit (a code-owned published field is not nil). A field of a
/// frame instance's inner control is not a field of the form, so every node counts,
/// inline or not.
function CheckFieldsWithoutObject(const ACtx: TV151FileCtx; const AUnit: TPasUnit; const ADfm: TDfmDoc;
  ACls: Integer): TArray<TLintFinding>;
begin
  Result:= nil;
  var Assigned_: THashSet<string>:= nil;
  try
    for var F in AUnit.Classes[ACls].Fields do
    begin
      if not F.IsPublished then Continue;
      if ADfm.IndexOfName(F.Name) >= 0 then Continue;
      if Assigned_ = nil then Assigned_:= AssignedNames(AUnit);
      if Assigned_.Contains(LowerCase(F.Name)) then Continue;
      Result:= Result + [MakeFinding(RULE_FIELD_WITHOUT_OBJECT, ACtx.Path, F.Line, F.Col, SEV_WARNING,
        Format('Published field %s: %s of %s has no object named %s in %s -- it stays nil after the form loads. '
          + 'Add the component on the form or move the field out of the published section.',
          [F.Name, F.TypeName, AUnit.Classes[ACls].Name, F.Name, TPath.GetFileName(ADfm.Path)]))];
    end;
  finally
    Assigned_.Free;
  end;
end;

/// `object` and `inline` nodes (not inherited, not inside an inline frame, not collection
/// items, not unnamed, not the root) whose name is not a field of the root class or of a class it inherits from.
/// True for a DevExpress bar (TdxBar*) or layout (TdxLayout*) class name.
function IsBarOrLayoutClass(const AClass: string): Boolean;
begin
  var C: string:= LastSegment(AClass);
  Result:= StartsText('TdxBar', C) or StartsText('TdxLayout', C);
end;

/// True when the unit's source holds AName as a whole word (a name-reachable use).
function NameUsedIn(const AUnit: TPasUnit; const AName: string): Boolean;
begin
  Result:= TRegEx.IsMatch(TEncoding.UTF8.GetString(AUnit.Src), '\b' + TRegEx.Escape(AName) + '\b', [roIgnoreCase]);
end;

function CheckObjectsWithoutField(const ACtx: TV151FileCtx; const AUnit: TPasUnit; const ADfm: TDfmDoc;
  ACls: Integer): TArray<TLintFinding>;
var
  Complete, Left: Boolean;
begin
  Result:= nil;
  var Cls: TPasClass:= AUnit.Classes[ACls];
  { fields of ancestors declared in this unit }
  var Known: TList<string>:= TList<string>.Create;
  try
    for var F in Cls.Fields do Known.Add(LowerCase(F.Name));
    var Chain: TArray<string>:= ClassChain(Cls.Name, AUnit, ACtx.Store, ACtx.LibStore, Complete, Left);
    var Exempt: TArray<string>:= V152FormObjectExemptList(ACtx.Cfg);
    for var A in Chain do
    begin
      var Idx: Integer:= AUnit.ClassIndex(A);
      if Idx >= 0 then
        for var F in AUnit.Classes[Idx].Fields do Known.Add(LowerCase(F.Name))
      else if ACtx.Store <> nil then
        for var S in ACtx.Store.FindSymbolsByExactName(A) do
          if S.Kind = skClass then
            for var Ch in ACtx.Store.FindAllChildSymbols(S.Id) do Known.Add(LowerCase(Ch.Name));
    end;
    for var I:= 1 to High(ADfm.Nodes) do
    begin
      var N: TDfmNode:= ADfm.Nodes[I];
      if (N.Kind not in [dnkObject, dnkInline]) or N.InInline or (N.Name = '') then Continue;
      if Known.Contains(LowerCase(N.Name)) then Continue;
      if V152IsExemptClass(Exempt, N.CompClass) then Continue;  { v152 D3: shipped + project exempt-class list }
      { T03: a DevExpress bar / layout object is built by the designer without a field by design;
        it matters only when the unit's source mentions its name (FindComponent('name') and the like) }
      if IsBarOrLayoutClass(N.CompClass) and not NameUsedIn(AUnit, N.Name) then Continue;
      Result:= Result + [MakeFinding(RULE_OBJECT_WITHOUT_FIELD, ADfm.Path, N.Line, N.Col, SEV_HINT,
        Format('Form object %s: %s has no field in %s -- code cannot reach it by name and the designer will add '
          + '"%s: %s;" the next time the form is saved.', [N.Name, N.CompClass, Cls.Name, N.Name, N.CompClass]))];
    end;
  finally
    Known.Free;
  end;
end;

/// A published field whose declared class is not the class (or an ancestor of the class)
/// of the form object with the same name. Silent when the object's class is unknown, or its
/// chain is incomplete and the field's class is not a project class.
function CheckFieldTypes(const ACtx: TV151FileCtx; const AUnit: TPasUnit; const ADfm: TDfmDoc;
  ACls: Integer): TArray<TLintFinding>;
var
  Complete, Left: Boolean;
begin
  Result:= nil;
  for var F in AUnit.Classes[ACls].Fields do
  begin
    if not F.IsPublished or (F.TypeName = '') then Continue;
    var Idx: Integer:= ADfm.IndexOfName(F.Name);
    if Idx < 0 then Continue;
    var N: TDfmNode:= ADfm.Nodes[Idx];
    if N.InInline or (N.CompClass = '') then Continue;
    var ObjCls: string:= LastSegment(N.CompClass);
    if SameText(ObjCls, F.TypeName) then Continue;
    var Chain: TArray<string>:= ClassChain(ObjCls, AUnit, ACtx.Store, ACtx.LibStore, Complete, Left);
    if (Length(Chain) = 0) and not Complete then Continue;   { the object's class is unknown }
    var Found: Boolean:= False;
    for var A in Chain do
      if SameText(A, F.TypeName) then Found:= True;
    if Found then Continue;
    if not (Complete or (Left and IsProjectClass(F.TypeName, AUnit, ACtx.Store))) then Continue;
    Result:= Result + [MakeFinding(RULE_FIELD_TYPE_MISMATCH, ACtx.Path, F.Line, F.Col, SEV_WARNING,
      Format('Field %s is declared %s but the form file creates %s: %s, which does not descend from %s. '
        + 'Declare the field as %s (or a class it descends from).',
        [F.Name, F.TypeName, N.Name, ObjCls, F.TypeName, ObjCls]))];
  end;
end;

{ ---------------------------------------------------------------------------
  form-resource-missing
  --------------------------------------------------------------------------- }

/// True when the raw source carries a {$R ...} / {$RESOURCE ...} directive (in any branch of
/// conditional compilation) naming a form file: *.dfm, Name.dfm, *.fmx, *.xfm, *.nfm.
function HasFormResourceDirective(const ARaw: TBytes): Boolean;
var
  S: string;
  I, L: Integer;
begin
  Result:= False;
  S:= TEncoding.UTF8.GetString(ARaw);
  L:= Length(S);
  I:= 1;
  while I <= L do
  begin
    var Ch: Char:= S[I];
    if (Ch = '/') and (I < L) and (S[I + 1] = '/') then
    begin
      while (I <= L) and not CharInSet(S[I], [#10, #13]) do Inc(I);
      Continue;
    end;
    if Ch = '''' then
    begin
      Inc(I);
      while (I <= L) and (S[I] <> '''') do Inc(I);
      Inc(I);
      Continue;
    end;
    if (Ch = '{') or ((Ch = '(') and (I < L) and (S[I + 1] = '*')) then
    begin
      var Paren: Boolean:= Ch = '(';
      var Start: Integer:= if Paren then I + 2 else I + 1;
      var J: Integer:= Start;
      if Paren then
        while (J < L) and not ((S[J] = '*') and (S[J + 1] = ')')) do Inc(J)
      else
        while (J <= L) and (S[J] <> '}') do Inc(J);
      var Inner: string:= LowerCase(Trim(Copy(S, Start, J - Start)));
      if StartsText('$r ', Inner) or StartsText('$resource ', Inner) then
      begin
        Inner:= Trim(Copy(Inner, Pos(' ', Inner) + 1, MaxInt)).DeQuotedString;
        if Inner.EndsWith('.dfm') or Inner.EndsWith('.fmx') or Inner.EndsWith('.xfm') or Inner.EndsWith('.nfm') then
          Exit(True);
      end;
      I:= if Paren then J + 2 else J + 1;
      Continue;
    end;
    Inc(I);
  end;
end;

function CheckResourceMissing(const ACtx: TV151FileCtx; const AUnit: TPasUnit; const ADfm: TDfmDoc;
  ACls: Integer): TArray<TLintFinding>;
begin
  Result:= nil;
  if HasFormResourceDirective(AUnit.RawSrc) then Exit;
  var C: TPasClass:= AUnit.Classes[ACls];
  Result:= [MakeFinding(RULE_RESOURCE_MISSING, ACtx.Path, C.Line, C.Col, SEV_WARNING,
    Format('%s is the root class of %s but the unit includes no form resource -- creating it with Create(Owner) '
      + 'raises EResNotFound. Add {$R *.dfm} after "implementation".', [C.Name, TPath.GetFileName(ADfm.Path)]))];
end;

{ ---------------------------------------------------------------------------
  inherited-form-handler-without-inherited
  --------------------------------------------------------------------------- }

/// Handler names the ancestor forms of AClass assign in their form files, walking up while
/// the ancestor's own form file is an inherited one. Empty when no ancestor form file is found.
function AncestorHandlers(const ACtx: TV151FileCtx; const AUnit: TPasUnit; const AClass: TPasClass;
  out AAncestor: string): TArray<string>;
var
  Parent  : string;
  FromUnit: TPasUnit;
  Depth   : Integer;
begin
  Result:= nil;
  AAncestor:= '';
  Parent:= AClass.ParentName;
  FromUnit:= AUnit;
  Depth:= 0;
  while (Parent <> '') and (Depth < MAX_FORM_DEPTH) do
  begin
    Inc(Depth);
    { the unit that declares Parent: this unit, the index, or a used unit next to it }
    var PasPath: string:= '';
    if FromUnit.ClassIndex(Parent) >= 0 then PasPath:= FromUnit.Path;
    if (PasPath = '') and (ACtx.Store <> nil) then
      for var S in ACtx.Store.FindSymbolsByExactName(Parent) do
        if S.Kind = skClass then
        begin
          PasPath:= ACtx.Store.GetFilePath(S.FileId);
          Break;
        end;
    if PasPath = '' then
      for var U in FromUnit.IntfUses + FromUnit.ImplUses do
      begin
        var Cand: string:= FindUnitFile(U, FromUnit.Path, nil);
        if Cand = '' then Continue;
        var CU: TPasUnit:= LoadPasSummary(Cand);
        if CU.Ok and (CU.ClassIndex(Parent) >= 0) then
        begin
          PasPath:= Cand;
          Break;
        end;
      end;
    if (PasPath = '') or SameText(PasPath, AUnit.Path) then Exit;
    var Dfm: TDfmHead:= LoadDfmHead(TPath.ChangeExtension(PasPath, '.dfm'));
    if not Dfm.Ok or not SameText(Dfm.RootClass, Parent) then Exit;
    if AAncestor = '' then AAncestor:= Parent;
    Result:= Result + Dfm.Handlers;
    if Dfm.RootKind <> dnkInherited then Exit;
    FromUnit:= LoadPasSummary(PasPath);
    if not FromUnit.Ok then Exit;
    var Idx: Integer:= FromUnit.ClassIndex(Parent);
    if Idx < 0 then Exit;
    Parent:= FromUnit.Classes[Idx].ParentName;
  end;
end;

function BodyCallsInherited(const ABody: TTSNode): Boolean;
var
  Found: Boolean;
begin
  Found:= False;
  WalkNodes(ABody, False,
    function(const N: TTSNode): Boolean
    begin
      if (N.NodeType = 'inherited') or (N.NodeType = 'kInherited') then Found:= True;
      Result:= not Found;
    end);
  Result:= Found;
end;

function CheckHandlerWithoutInherited(const ACtx: TV151FileCtx; const AUnit: TPasUnit; const ADfm: TDfmDoc;
  ACls: Integer): TArray<TLintFinding>;
var
  Ancestor: string;
begin
  Result:= nil;
  if ADfm.Nodes[0].Kind <> dnkInherited then Exit;
  var Cls: TPasClass:= AUnit.Classes[ACls];
  var Handlers: TArray<string>:= AncestorHandlers(ACtx, AUnit, Cls, Ancestor);
  if Length(Handlers) = 0 then Exit;
  for var R in AUnit.Routines do
  begin
    if not SameText(R.OwnerClass, Cls.Name) or R.Body.IsNull then Continue;
    if not Cls.HasMethod(R.Name) then Continue;
    if IndexText(R.Name, Handlers) < 0 then Continue;
    if BodyCallsInherited(R.Body) then Continue;
    Result:= Result + [MakeFinding(RULE_HANDLER_NO_INHERITED, ACtx.Path, R.Line, R.Col, SEV_WARNING,
      Format('%s.%s replaces the handler of the same name that the ancestor form %s assigns in its form file, '
        + 'but never calls inherited -- the ancestor''s handler no longer runs. Add "inherited;" (or rename the '
        + 'handler if the replacement is deliberate).', [Cls.Name, R.Name, Ancestor]))];
  end;
end;

{ ---------------------------------------------------------------------------
  self-free-in-event-handler
  --------------------------------------------------------------------------- }

function IsFreeName(const S: string): Boolean;
begin
  Result:= SameText(S, 'Free') or SameText(S, 'Destroy') or SameText(S, 'DisposeOf');
end;

/// True when the statement node frees the form itself: Free / Destroy / DisposeOf (bare or
/// on Self or on AOwnVar), or FreeAndNil(Self | AOwnVar).
function IsSelfFreeStatement(const AUnit: TPasUnit; const S: TTSNode; const AOwnVar: string): Boolean;

  function IsSelfRef(const N: TTSNode): Boolean;
  begin
    Result:= (N.NodeType = 'identifier') and (SameText(AUnit.Text(N), 'Self')
      or ((AOwnVar <> '') and SameText(AUnit.Text(N), AOwnVar)));
  end;

  function IsFreeExpr(const E: TTSNode): Boolean;
  begin
    Result:= False;
    if E.IsNull then Exit;
    if E.NodeType = 'identifier' then Exit(IsFreeName(AUnit.Text(E)));
    if E.NodeType = 'exprDot' then
      Exit(IsSelfRef(E.ChildByField('lhs')) and IsFreeName(AUnit.Text(E.ChildByField('rhs'))));
    if E.NodeType = 'exprCall' then
    begin
      var Ent: TTSNode:= E.ChildByField('entity');
      var Args: TTSNode:= E.ChildByField('args');
      if (Ent.NodeType = 'identifier') and SameText(AUnit.Text(Ent), 'FreeAndNil') and not Args.IsNull
        and (Args.NamedChildCount = 1) then
        Exit(IsSelfRef(Args.NamedChild(0)));
      if (Args.IsNull or (Args.NamedChildCount = 0)) then Exit(IsFreeExpr(Ent));
    end;
  end;

begin
  Result:= (S.NodeType = 'statement') and (S.NamedChildCount = 1) and IsFreeExpr(S.NamedChild(0));
end;

function IsFormClass(const ACtx: TV151FileCtx; const AUnit: TPasUnit; const ADfm: TDfmDoc; const ACls: TPasClass): Boolean;
var
  Complete, Left: Boolean;
begin
  if SameText(ACls.ParentName, 'TForm') or SameText(ACls.ParentName, 'TCustomForm') then Exit(True);
  if ADfm.RootHasProp('ClientWidth') or ADfm.RootHasProp('ClientHeight') then
  begin
    { a frame or data module has no Release: exclude them when the chain says so }
    var Chain: TArray<string>:= ClassChain(ACls.Name, AUnit, ACtx.Store, ACtx.LibStore, Complete, Left);
    for var A in Chain do
      if SameText(A, 'TCustomFrame') or SameText(A, 'TDataModule') then Exit(False);
    Exit(True);
  end;
  Result:= False;
end;

function CheckSelfFree(const ACtx: TV151FileCtx; const AUnit: TPasUnit; const ADfm: TDfmDoc;
  ACls: Integer): TArray<TLintFinding>;
var
  Hits: TList<TLintFinding>;
begin
  Result:= nil;
  var Cls: TPasClass:= AUnit.Classes[ACls];
  if not IsFormClass(ACtx, AUnit, ADfm, Cls) then Exit;
  var Handlers: TArray<string>:= ADfm.HandlerNames;
  { the global variable of the form's own class, declared in this unit }
  var OwnVar: string:= '';
  for var V in AUnit.Vars do
    if SameText(V.TypeName, Cls.Name) then
    begin
      OwnVar:= V.Name;
      Break;
    end;
  Hits:= TList<TLintFinding>.Create;
  try
    for var R in AUnit.Routines do
    begin
      if not SameText(R.OwnerClass, Cls.Name) or R.Body.IsNull then Continue;
      if not (R.SenderObj or (IndexText(R.Name, Handlers) >= 0)) then Continue;
      var RName: string:= R.Name;
      WalkNodes(R.Body, True,
        function(const N: TTSNode): Boolean
        begin
          Result:= True;
          if IsSelfFreeStatement(AUnit, N, OwnVar) then
            Hits.Add(MakeFinding(RULE_SELF_FREE_IN_HANDLER, ACtx.Path, NodeLine(N), NodeCol(N), SEV_WARNING,
              Format('%s.%s frees the form inside its own event handler -- the VCL still touches the object after '
                + 'the handler returns (access violation). Call Release instead, or set Action := caFree in OnClose.',
                [Cls.Name, RName])));
        end);
    end;
    Result:= Hits.ToArray;
  finally
    Hits.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  unit-missing-from-uses, form-file side
  --------------------------------------------------------------------------- }

/// The unit that declares module AModule (a form / data module / frame instance name):
/// the .dpr's `Unit in 'Unit.pas' {Module}` first, then a unit-level variable of that name in
/// the project index whose type is a class.
function UnitOfModule(const ACtx: TV151FileCtx; const ADpr: TDprInfo; AHasDpr: Boolean; const AModule: string): string;
begin
  Result:= '';
  if AHasDpr then Result:= ADpr.UnitOfModule(AModule);
  if (Result <> '') or (ACtx.Store = nil) then Exit;
  var Found: string:= '';
  for var S in ACtx.Store.FindSymbolsByExactName(AModule) do
  begin
    if S.Kind <> skVarDecl then Continue;
    var P: TSymbol:= ACtx.Store.GetSymbolById(S.ParentId);
    if P.Kind <> skUnit then Continue;
    var TypeName: string:= LastSegment(Trim(S.Signature));
    var IsCls: Boolean:= False;
    for var C in ACtx.Store.FindSymbolsByExactName(TypeName) do
      if (C.Kind = skClass) and (C.FileId = S.FileId) then IsCls:= True;
    if not IsCls then Continue;
    if (Found <> '') and not SameText(Found, P.Name) then Exit;   { two candidates: unknown }
    Found:= P.Name;
  end;
  Result:= Found;
end;

function CheckDfmReferenceUnits(const ACtx: TV151FileCtx; const AUnit: TPasUnit; const ADfm: TDfmDoc): TArray<TLintFinding>;
var
  Dpr   : TDprInfo;
  HasDpr: Boolean;
  Seen  : TList<string>;
begin
  Result:= nil;
  HasDpr:= FindDprFor(ACtx.Path, AUnit.UnitName, ACtx.Store, Dpr);
  Seen:= TList<string>.Create;
  try
    for var N in ADfm.Nodes do
      for var P in N.Props do
      begin
        var V: string:= P.Value;
        var Dot: Integer:= Pos('.', V);
        if (Dot <= 1) or V.Contains(' ') or CharInSet(V[1], ['0'..'9', '-', '[', '''', '#', '$']) then Continue;
        var Module: string:= Copy(V, 1, Dot - 1);
        if not IsPascalIdent(Module) then Continue;
        if SameText(Module, ADfm.Nodes[0].Name) or (ADfm.IndexOfName(Module) >= 0) then Continue;
        if Seen.Contains(LowerCase(Module)) then Continue;
        Seen.Add(LowerCase(Module));
        var UnitName: string:= UnitOfModule(ACtx, Dpr, HasDpr, Module);
        if (UnitName = '') or SameText(LastSegment(UnitName), LastSegment(AUnit.UnitName)) then Continue;
        if AUnit.UsesUnit(UnitName) then Continue;
        Result:= Result + [MakeFinding(RULE_HOST_UNIT_MISSING, ADfm.Path, P.Line, 1, SEV_WARNING,
          Format('%s = %s refers to module %s, whose unit %s is not in the uses clause of %s -- the designer does not '
            + 'open %s with this form and the reference is lost when the form is saved. Add %s to the implementation uses clause.',
            [P.Name, V, Module, UnitName, AUnit.UnitName, Module, UnitName]))];
      end;
  finally
    Seen.Free;
  end;
end;

class function TV151DFMARules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= nil;
  if not (ACtx.Wants(RULE_FIELD_TYPE_MISMATCH) or ACtx.Wants(RULE_FIELD_WITHOUT_OBJECT)  // dl:ok boolean-expression-complexity@a34f -- REVIEWED 2026-11-14 v151 DFM-A: flat list of rule ids / creation hooks, each named once
    or ACtx.Wants(RULE_OBJECT_WITHOUT_FIELD) or ACtx.Wants(RULE_RESOURCE_MISSING)
    or ACtx.Wants(RULE_HANDLER_NO_INHERITED) or ACtx.Wants(RULE_SELF_FREE_IN_HANDLER)
    or ACtx.Wants(RULE_HOST_UNIT_MISSING)) then Exit;
  var Dfm: TDfmDoc:= LoadDfm(ACtx.DfmPath);
  if Dfm.IsEmpty then Exit;
  var U: TPasUnit:= LoadPas(ACtx.Path);
  if not U.Ok then Exit;
  if ACtx.Wants(RULE_HOST_UNIT_MISSING) then Result:= Result + CheckDfmReferenceUnits(ACtx, U, Dfm);
  var Cls: Integer:= RootClassIndex(U, Dfm);
  if Cls < 0 then Exit;
  if ACtx.Wants(RULE_FIELD_WITHOUT_OBJECT) then Result:= Result + CheckFieldsWithoutObject(ACtx, U, Dfm, Cls);
  if ACtx.Wants(RULE_OBJECT_WITHOUT_FIELD) then Result:= Result + CheckObjectsWithoutField(ACtx, U, Dfm, Cls);
  if ACtx.Wants(RULE_FIELD_TYPE_MISMATCH) then Result:= Result + CheckFieldTypes(ACtx, U, Dfm, Cls);
  if ACtx.Wants(RULE_RESOURCE_MISSING) then Result:= Result + CheckResourceMissing(ACtx, U, Dfm, Cls);
  if ACtx.Wants(RULE_HANDLER_NO_INHERITED) then Result:= Result + CheckHandlerWithoutInherited(ACtx, U, Dfm, Cls);
  if ACtx.Wants(RULE_SELF_FREE_IN_HANDLER) then Result:= Result + CheckSelfFree(ACtx, U, Dfm, Cls);
end;

{ ---------------------------------------------------------------------------
  form-autocreate-and-manual / form-access-before-create
  --------------------------------------------------------------------------- }

/// True when R checks AVar (Assigned(AVar), AVar = nil, AVar <> nil) anywhere, or frees it
/// (AVar.Free / AVar.Release / FreeAndNil(AVar)) before byte offset ABefore.
function RoutineGuards(const AUnit: TPasUnit; const R: TPasRoutine; const AVar: string; ABefore: UInt32): Boolean;
var
  Hit: Boolean;
begin
  Hit:= False;
  WalkNodes(R.Body, False,
    function(const N: TTSNode): Boolean
    begin
      var T: string:= N.NodeType;
      if T = 'exprCall' then
      begin
        var Ent: TTSNode:= N.ChildByField('entity');
        var Args: TTSNode:= N.ChildByField('args');
        var EntText: string:= AUnit.Text(Ent);
        var FirstArgIsVar: Boolean:= not Args.IsNull and (Args.NamedChildCount >= 1) and SameText(AUnit.Text(Args.NamedChild(0)), AVar);
        if FirstArgIsVar and (SameText(EntText, 'Assigned') or (SameText(EntText, 'FreeAndNil') and (N.StartByte < ABefore))) then Hit:= True;
      end
      else if T = 'exprBinary' then
      begin
        var L: string:= AUnit.Text(N.ChildByField('lhs'));
        var Rr: string:= AUnit.Text(N.ChildByField('rhs'));
        if (SameText(L, AVar) and SameText(Rr, 'nil')) or (SameText(Rr, AVar) and SameText(L, 'nil')) then Hit:= True;
      end
      else if (T = 'exprDot') and (N.StartByte < ABefore) then
      begin
        if SameText(AUnit.Text(N.ChildByField('lhs')), AVar) then
        begin
          var M: string:= AUnit.Text(N.ChildByField('rhs'));
          if SameText(M, 'Free') or SameText(M, 'Release') or SameText(M, 'Destroy') then Hit:= True;
        end;
      end;
      Result:= not Hit;
    end);
  Result:= Hit;
end;

/// The class name of `TClass.Create(...)` / `TClass.Create`, '' for any other expression.
function CreateCallClass(const AUnit: TPasUnit; const E: TTSNode): string;
begin
  Result:= '';
  var D: TTSNode:= E;
  if D.NodeType = 'exprCall' then D:= D.ChildByField('entity');
  if D.IsNull or (D.NodeType <> 'exprDot') then Exit;
  if not SameText(AUnit.Text(D.ChildByField('rhs')), 'Create') then Exit;
  var L: TTSNode:= D.ChildByField('lhs');
  if L.NodeType = 'identifier' then Result:= AUnit.Text(L);
end;

function OwnClassHasField(const AUnit: TPasUnit; const R: TPasRoutine; const AName: string): Boolean;
begin
  Result:= False;
  if R.OwnerClass = '' then Exit;
  var Idx: Integer:= AUnit.ClassIndex(R.OwnerClass);
  Result:= (Idx >= 0) and (AUnit.Classes[Idx].FieldIndex(AName) >= 0);
end;

function CheckAutocreateAndManual(const ACtx: TV151FileCtx; const AUnit: TPasUnit; const ADpr: TDprInfo): TArray<TLintFinding>;  // dl:ok too-many-exit-points@4614 -- REVIEWED 2026-11-14 v151 DFM-A: one guard clause per rule precondition; splitting scatters them
var
  Hits: TList<TLintFinding>;
begin
  Result:= nil;
  if Length(ADpr.Creates) = 0 then Exit;
  Hits:= TList<TLintFinding>.Create;
  try
    for var R in AUnit.Routines do
    begin
      if R.Body.IsNull then Continue;
      var Rt: TPasRoutine:= R;
      WalkNodes(R.Body, False,
        function(const N: TTSNode): Boolean
        begin
          Result:= True;
          if N.NodeType <> 'assignment' then Exit;
          var L: TTSNode:= N.ChildByField('lhs');
          if L.NodeType <> 'identifier' then Exit;
          var VarName: string:= AUnit.Text(L);
          var Ci: Integer:= ADpr.CreateIndexOfVar(VarName);
          if Ci < 0 then Exit;
          var Cls: string:= CreateCallClass(AUnit, N.ChildByField('rhs'));
          if (Cls = '') or not SameText(Cls, ADpr.Creates[Ci].ClassName) then Exit;
          if Rt.HasLocal(VarName) or OwnClassHasField(AUnit, Rt, VarName) then Exit;
          if RoutineGuards(AUnit, Rt, VarName, N.StartByte) then Exit;
          Hits.Add(MakeFinding(RULE_AUTOCREATE_AND_MANUAL, ACtx.Path, NodeLine(N), NodeCol(N), SEV_WARNING,
            Format('%s := %s.Create(...) creates a second instance: %s already creates %s with Application.CreateForm. '
              + 'The first instance stays alive and invisible. Drop the CreateForm line from the .dpr, or test '
              + 'Assigned(%s) first.', [VarName, Cls, TPath.GetFileName(ADpr.Path), VarName, VarName])));
        end);
    end;
    Result:= Hits.ToArray;
  finally
    Hits.Free;
  end;
end;

function CheckAccessBeforeCreate(const ACtx: TV151FileCtx; const AUnit: TPasUnit; const ADpr: TDprInfo): TArray<TLintFinding>;  // dl:ok too-many-exit-points@aa11 -- REVIEWED 2026-11-14 v151 DFM-A: one guard clause per rule precondition; splitting scatters them
var
  Hits: TList<TLintFinding>;
begin
  Result:= nil;
  if Length(ADpr.Creates) < 2 then Exit;
  Hits:= TList<TLintFinding>.Create;
  try
    for var CiLoop:= 0 to High(ADpr.Creates) do
    begin
      var Ci: Integer:= CiLoop;
      var Cls: string:= ADpr.Creates[Ci].ClassName;
      var Idx: Integer:= AUnit.ClassIndex(Cls);
      if Idx < 0 then Continue;
      { the OnCreate handler: from the form file, else the IDE's default names }
      var OnCreate: string:= '';
      var DfmPath: string:= TPath.ChangeExtension(AUnit.Path, '.dfm');
      var Dfm: TDfmDoc:= LoadDfm(DfmPath);
      if not Dfm.IsEmpty and SameText(Dfm.Nodes[0].CompClass, Cls) then OnCreate:= Dfm.RootProp('OnCreate');
      for var R in AUnit.Routines do
      begin
        if not SameText(R.OwnerClass, Cls) or R.Body.IsNull then Continue;
        var IsCreation: Boolean:= R.IsCtor or SameText(R.Name, 'AfterConstruction')  // dl:ok boolean-expression-complexity@27e6 -- REVIEWED 2026-11-14 v151 DFM-A: flat list of rule ids / creation hooks, each named once
          or ((OnCreate <> '') and SameText(R.Name, OnCreate))
          or ((OnCreate = '') and (SameText(R.Name, 'FormCreate') or SameText(R.Name, 'DataModuleCreate')));
        if not IsCreation then Continue;
        var Rt: TPasRoutine:= R;
        var Reported: TList<string>:= TList<string>.Create;
        try
          WalkNodes(R.Body, False,
            function(const N: TTSNode): Boolean
            begin
              Result:= True;
              if N.NodeType <> 'identifier' then Exit;
              { only a base name: not the member part of A.B }
              var P: TTSNode:= N.Parent;
              if (P.NodeType = 'exprDot') and (P.ChildByField('rhs').StartByte = N.StartByte) then Exit;
              var Name: string:= AUnit.Text(N);
              var Later: Integer:= ADpr.CreateIndexOfVar(Name);
              if Later <= Ci then Exit;
              if Reported.Contains(LowerCase(Name)) then Exit;
              if Rt.HasLocal(Name) or OwnClassHasField(AUnit, Rt, Name) then Exit;
              if RoutineGuards(AUnit, Rt, Name, High(UInt32)) then Exit;
              { assigned in the routine itself counts as created here }
              var Assigned_: Boolean:= False;
              WalkNodes(Rt.Body, False,
                function(const A: TTSNode): Boolean
                begin
                  if (A.NodeType = 'assignment') and SameText(AUnit.Text(A.ChildByField('lhs')), Name) then Assigned_:= True;
                  Result:= not Assigned_;
                end);
              if Assigned_ then Exit;
              Reported.Add(LowerCase(Name));
              Hits.Add(MakeFinding(RULE_ACCESS_BEFORE_CREATE, ACtx.Path, NodeLine(N), NodeCol(N), SEV_WARNING,
                Format('%s.%s runs while %s creates %s (CreateForm #%d) and reads %s, which the .dpr creates later '
                  + '(CreateForm #%d) -- it is still nil here. Move %s earlier in the .dpr or the access to OnShow.',
                  [Cls, Rt.Name, TPath.GetFileName(ADpr.Path), Cls, Ci + 1, Name, Later + 1, Name])));
            end);
        finally
          Reported.Free;
        end;
      end;
    end;
    Result:= Hits.ToArray;
  finally
    Hits.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  foreign-form-control-access
  --------------------------------------------------------------------------- }

type
  /// A global form variable of another unit: its name, class and the class's fields.
  TForeignForm = record
    VarName : string;
    ClassName: string;
    UnitName: string;
    Fields  : TArray<string>;
  end;

/// Global form / frame variables declared in the interface of the units AUnit uses (only
/// units with a sibling text .dfm whose root class is the variable's class and is not a data module).
var
  GForeignLock : TObject;
  GForeignCache: TDictionary<string, TArray<TForeignForm>>;   // lower-case unit path -> its form globals

/// The global form / frame variables declared in the interface of the unit at APath (a sibling
/// text .dfm whose root class is the variable's class and is not a data module). Cached per
/// path for the process: a lint-all asks the same used units again for every unit.
function ForeignFormsOf(const ACtx: TV151FileCtx; const APath: string): TArray<TForeignForm>;
var
  Complete, Left: Boolean;
begin
  var Key: string:= LowerCase(APath);
  TMonitor.Enter(GForeignLock);
  try
    if GForeignCache.TryGetValue(Key, Result) then Exit;
    Result:= nil;
    var Dfm: TDfmHead:= LoadDfmHead(TPath.ChangeExtension(APath, '.dfm'));
    if Dfm.Ok then
    begin
      var OU: TPasUnit:= LoadPasSummary(APath);
      var Idx: Integer:= if OU.Ok then OU.ClassIndex(Dfm.RootClass) else -1;
      if Idx >= 0 then
      begin
        var Chain: TArray<string>:= ClassChain(OU.Classes[Idx].Name, OU, ACtx.Store, ACtx.LibStore, Complete, Left);
        var IsForm: Boolean:= Dfm.ClientSized;
        for var A in Chain do
          if SameText(A, 'TDataModule') then IsForm:= False
          else if SameText(A, 'TCustomForm') or SameText(A, 'TCustomFrame') then IsForm:= True;
        if IsForm then
          for var V in OU.Vars do
          begin
            if not V.InInterface or not SameText(V.TypeName, OU.Classes[Idx].Name) then Continue;
            var FF: TForeignForm;
            FF.VarName:= V.Name;
            FF.ClassName:= OU.Classes[Idx].Name;
            FF.UnitName:= OU.UnitName;
            FF.Fields:= nil;
            for var F in OU.Classes[Idx].Fields do
              if F.IsPublished then FF.Fields:= FF.Fields + [LowerCase(F.Name)];   { controls, not private state }
            Result:= Result + [FF];
          end;
      end;
    end;
    GForeignCache.AddOrSetValue(Key, Result);
  finally
    TMonitor.Exit(GForeignLock);
  end;
end;

/// Global form / frame variables of the units AUnit uses (see ForeignFormsOf).
function ForeignForms(const ACtx: TV151FileCtx; const AUnit: TPasUnit): TArray<TForeignForm>;
begin
  Result:= nil;
  for var UName in AUnit.IntfUses + AUnit.ImplUses do
  begin
    var Path: string:= FindUnitFile(UName, AUnit.Path, ACtx.Store);
    if (Path = '') or SameText(Path, AUnit.Path) then Continue;
    Result:= Result + ForeignFormsOf(ACtx, Path);
  end;
end;

function CheckForeignFormAccess(const ACtx: TV151FileCtx; const AUnit: TPasUnit): TArray<TLintFinding>;  // dl:ok too-many-exit-points@4acc -- REVIEWED 2026-11-14 v151 DFM-A: one guard clause per rule precondition; splitting scatters them
var
  Hits: TList<TLintFinding>;
begin
  Result:= nil;
  var Forms: TArray<TForeignForm>:= ForeignForms(ACtx, AUnit);
  if Length(Forms) = 0 then Exit;
  Hits:= TList<TLintFinding>.Create;
  try
    for var R in AUnit.Routines do
    begin
      if R.Body.IsNull then Continue;
      var Rt: TPasRoutine:= R;
      var Seen: TList<string>:= TList<string>.Create;
      try
        WalkNodes(R.Body, True,
          function(const N: TTSNode): Boolean
          begin
            Result:= True;
            if N.NodeType <> 'exprDot' then Exit;
            var L: TTSNode:= N.ChildByField('lhs');
            if L.NodeType <> 'identifier' then Exit;
            var VName: string:= AUnit.Text(L);
            var Member: string:= AUnit.Text(N.ChildByField('rhs'));
            if Rt.HasLocal(VName) or OwnClassHasField(AUnit, Rt, VName) or (AUnit.VarIndex(VName) >= 0) then Exit;
            for var FF in Forms do
              if SameText(FF.VarName, VName) and (IndexText(Member, FF.Fields) >= 0) then
              begin
                var Key: string:= LowerCase(VName + '.' + Member);
                if Seen.Contains(Key) then Exit;
                Seen.Add(Key);
                Hits.Add(MakeFinding(RULE_FOREIGN_FORM_ACCESS, ACtx.Path, NodeLine(N), NodeCol(N), SEV_HINT,
                  Format('%s.%s reaches the control %s of form %s (unit %s) through its global variable -- this unit now '
                    + 'depends on that form''s layout. Give %s a method or property for what is needed.',
                    [VName, Member, Member, FF.ClassName, FF.UnitName, FF.ClassName])));
                Exit;
              end;
          end);
      finally
        Seen.Free;
      end;
    end;
    Result:= Hits.ToArray;
  finally
    Hits.Free;
  end;
end;

class function TV151DFMARules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
var
  Dpr: TDprInfo;
begin
  Result:= nil;
  var WantDpr: Boolean:= ACtx.Wants(RULE_AUTOCREATE_AND_MANUAL) or ACtx.Wants(RULE_ACCESS_BEFORE_CREATE);
  var WantForeign: Boolean:= ACtx.Wants(RULE_FOREIGN_FORM_ACCESS);
  if not (WantDpr or WantForeign) then Exit;
  if not SameText(TPath.GetExtension(ACtx.Path), '.pas') then Exit;
  var U: TPasUnit:= LoadPas(ACtx.Path);
  if not U.Ok then Exit;
  if WantDpr and FindDprFor(ACtx.Path, U.UnitName, ACtx.Store, Dpr) then
  begin
    if ACtx.Wants(RULE_AUTOCREATE_AND_MANUAL) then Result:= Result + CheckAutocreateAndManual(ACtx, U, Dpr);
    if ACtx.Wants(RULE_ACCESS_BEFORE_CREATE) then Result:= Result + CheckAccessBeforeCreate(ACtx, U, Dpr);
  end;
  if WantForeign then Result:= Result + CheckForeignFormAccess(ACtx, U);
end;

class function TV151DFMARules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@215e -- REVIEWED 2026-11-14 v151 DFM-A: signature fixed by the TV151 lane interface; this lane has no raw-byte or project check
begin
  Result:= nil;
end;

class function TV151DFMARules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@fca7 -- REVIEWED 2026-11-14 v151 DFM-A: signature fixed by the TV151 lane interface; this lane has no raw-byte or project check
begin
  Result:= nil;
end;

initialization
  GForeignLock:= TObject.Create;
  GForeignCache:= TDictionary<string, TArray<TForeignForm>>.Create;

finalization
  GForeignCache.Free;
  GForeignLock.Free;

end.
