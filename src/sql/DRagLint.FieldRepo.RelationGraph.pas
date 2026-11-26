unit DRagLint.FieldRepo.RelationGraph;

{ drag-lint 1.55 -- lane XTABLE slice X2: the relation graph and the path finder of cross-table fields (design
  docs\superpowers\specs\2026-11-26-cross-table-fields-design.md section 3.2, rulings XQ2, XQ5, XQ6). Pure: no
  repository connection, no I/O; DRagLint.FieldRepo.RelationRepo loads the graph from a repository. }

interface

uses
  System.SysUtils,
  System.Generics.Collections;

const
  /// <summary>Default search depth of the path finder, in steps (design 3.2, ruling XQ5 A).</summary>
  PATH_DEPTH_DEFAULT = 3;

type
  /// <summary>One N:1 step of the relation graph: a child row reaches ONE parent row (design 2.2, 3.2).</summary>
  TFrRelation = record
    /// <summary>Role name: DL_RELATIONS.RELATION_NAME, else the FK constraint name.</summary>
    Name: string;
    /// <summary>Table of the child rows.</summary>
    ChildTable: string;
    /// <summary>Table of the one parent row.</summary>
    ParentTable: string;
    /// <summary>FK, FORM or HAND (DL_RELATIONS.SOURCE).</summary>
    Source: string;
    /// <summary>The FK constraint behind an FK relation; '' for FORM / HAND.</summary>
    ConstraintName: string;
    /// <summary>The PK / UNIQUE constraint of the parent the parent columns match; '' = no key (never an edge).</summary>
    ParentKey: string;
    /// <summary>True = the stored answer of P1 B for (ChildTable, ParentTable).</summary>
    IsDefault: Boolean;
    /// <summary>Child columns, in key order.</summary>
    ChildColumns: TArray<string>;
    /// <summary>Parent columns, position for position with ChildColumns.</summary>
    ParentColumns: TArray<string>;
  end;

  /// <summary>A simple path of relations from a home table up to a target table.</summary>
  TFrRelationPath = record
    /// <summary>The steps in order; Steps[0].ChildTable is the home table.</summary>
    Steps: TArray<TFrRelation>;
    /// <summary>The DL_FIELD_INPUTS.PATH form of the path.</summary>
    /// <returns>Relation names joined by REPO_PATH_SEPARATOR; '' for no step.</returns>
    function Text: string;
    /// <summary>The tables the path visits.</summary>
    /// <returns>Home table first, target table last; empty for no step.</returns>
    function Tables: TArray<string>;
  end;

  /// <summary>Which rule of design 3.2 chose a path.</summary>
  TFrPathRule = (
    /// <summary>No path within the depth.</summary>
    prNone,
    /// <summary>Rule 1: the binding already stored for the field.</summary>
    prStored,
    /// <summary>Rule 2: the path the form's own joins use.</summary>
    prForm,
    /// <summary>Rule 3: the IS_DEFAULT relations.</summary>
    prDefault,
    /// <summary>Rule 4: exactly one path.</summary>
    prSingle,
    /// <summary>Rule 5: several paths, none chosen (asked once; the answer becomes IS_DEFAULT).</summary>
    prAmbiguous);

  /// <summary>The paths between two tables and the one chosen, if any (design 3.2).</summary>
  TFrPathChoice = record
    /// <summary>Every simple path within the depth, shortest first, then by Text.</summary>
    Paths: TArray<TFrRelationPath>;
    /// <summary>The rule that decided.</summary>
    Rule: TFrPathRule;
    /// <summary>Index into Paths; -1 for prNone and prAmbiguous.</summary>
    Chosen: Integer;
  end;

  /// <summary>Reachability over every ordered table pair at one depth (design 3.2 measured check).</summary>
  TFrReachStats = record
    /// <summary>The depth counted, in steps.</summary>
    Depth: Integer;
    /// <summary>Ordered pairs (from, to), from &lt;&gt; to, with at least one path of at most Depth steps.</summary>
    Pairs: Integer;
    /// <summary>Of those, the pairs with more than one such path.</summary>
    Ambiguous: Integer;
  end;

  /// <summary>Directed graph child -&gt; parent over N:1 relations (design 3.2): nodes are tables, edges are
  /// relations whose parent side is a PK / UNIQUE key.</summary>
  /// <remarks>Table and relation names compare case-insensitively. Not thread-safe.</remarks>
  TFrRelationGraph = class
  private
    FEdges: TObjectDictionary<string, TList<TFrRelation>>;
    FTables: TDictionary<string, string>;
    FRelationCount: Integer;
    procedure Walk(const pNode, pTarget: string; pDepth: Integer; pVisited: TDictionary<string, Boolean>;
      pStack: TList<TFrRelation>; pOut: TList<TFrRelationPath>);
    function Overridden(const pStep: TFrRelation): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Adds one relation as an edge (design 3.2: a relation whose parent side has no key is never an
    /// edge).</summary>
    /// <param name="pRelation">The relation; ParentKey must name the parent's PK / UNIQUE constraint.</param>
    /// <returns>False, and nothing added, when ParentKey is '', a table name is '', or the column lists are empty
    /// or of different lengths.</returns>
    function AddRelation(const pRelation: TFrRelation): Boolean;
    /// <summary>Every simple path from pFrom up to pTo of at most pDepth steps (design 3.2 "Search").</summary>
    /// <param name="pFrom">Home table.</param>
    /// <param name="pTo">Target table; pFrom itself gives no path.</param>
    /// <param name="pDepth">Maximum steps (ruling XQ5: 3).</param>
    /// <returns>Shortest first, then by Text; two relations between the same tables (roles) are two paths.</returns>
    function FindPaths(const pFrom, pTo: string; pDepth: Integer = PATH_DEPTH_DEFAULT): TArray<TFrRelationPath>;
    /// <summary>Finds the paths and applies the choice of design 3.2, first rule that applies: 1 stored binding,
    /// 2 the form's joins, 3 IS_DEFAULT, 4 exactly one path, 5 several = ambiguous (never chosen by data).</summary>
    /// <param name="pFrom">Home table.</param>
    /// <param name="pTo">Target table.</param>
    /// <param name="pStored">The PATH already stored for the field; '' = none. Taken when it is one of the
    /// paths found.</param>
    /// <param name="pFormRelations">Relation names the form's joins match; the path taken by rule 2 is the only
    /// one whose every step is among them.</param>
    /// <param name="pDepth">Maximum steps.</param>
    /// <returns>The paths, the rule and the chosen index (-1 when none or ambiguous).</returns>
    /// <remarks>Rule 3 takes the only path whose every step IS_DEFAULT; else the only path with no step
    /// overridden (a step that is not default while another relation between the same two tables is).</remarks>
    function Choose(const pFrom, pTo, pStored: string; const pFormRelations: TArray<string>;
      pDepth: Integer = PATH_DEPTH_DEFAULT): TFrPathChoice;
    /// <summary>Counts reachable and ambiguous ordered pairs over every table (design 3.2 measured check).</summary>
    /// <param name="pDepth">Maximum steps.</param>
    /// <returns>Pairs with at least one path, and with more than one path, of at most pDepth steps.</returns>
    function Stats(pDepth: Integer): TFrReachStats;
    /// <summary>The tables named by any edge, sorted.</summary>
    /// <returns>Names as first added.</returns>
    function Tables: TArray<string>;
    /// <summary>Number of edges added.</summary>
    property RelationCount: Integer read FRelationCount;
  end;

/// <summary>The default input alias of a target table (ruling XQ2 A): the table name for the first path a field
/// uses to reach it, `TABLE_n` for the n-th.</summary>
/// <param name="pTarget">Target table.</param>
/// <param name="pOrdinal">1 for the first path, 2 for the second, ...</param>
/// <returns>pTarget, or pTarget + '_' + pOrdinal when pOrdinal &gt; 1.</returns>
function DefaultInputAlias(const pTarget: string; pOrdinal: Integer): string;

/// <summary>Lower-case name of a rule, as `repo paths` prints it.</summary>
/// <param name="pRule">The rule.</param>
/// <returns>none, stored, form, default, single or ambiguous.</returns>
function PathRuleName(pRule: TFrPathRule): string;

implementation

uses
  System.Generics.Defaults,
  DRagLint.FieldRepo.Schema;

const
  NO_CHOICE = -1;
  RULE_NAMES: array[TFrPathRule] of string = ('none', 'stored', 'form', 'default', 'single', 'ambiguous');

function TFrRelationPath.Text: string;
var
  VNames: TArray<string>;
  VI: Integer;
begin
  SetLength(VNames, Length(Steps));
  for VI := 0 to High(Steps) do
    VNames[VI] := Steps[VI].Name;
  Result := string.Join(REPO_PATH_SEPARATOR, VNames);
end;

function TFrRelationPath.Tables: TArray<string>;
var
  VStep: TFrRelation;
begin
  Result := nil;
  if Length(Steps) = 0 then
    Exit;
  Result := [Steps[0].ChildTable];
  for VStep in Steps do
    Result := Result + [VStep.ParentTable];
end;

function DefaultInputAlias(const pTarget: string; pOrdinal: Integer): string;
begin
  Result := if pOrdinal > 1 then pTarget + '_' + IntToStr(pOrdinal) else pTarget;
end;

function PathRuleName(pRule: TFrPathRule): string;
begin
  Result := RULE_NAMES[pRule];
end;

constructor TFrRelationGraph.Create;
begin
  inherited Create;
  FEdges := TObjectDictionary<string, TList<TFrRelation>>.Create([doOwnsValues]);
  FTables := TDictionary<string, string>.Create;
end;

destructor TFrRelationGraph.Destroy;
begin
  FTables.Free;
  FEdges.Free;
  inherited Destroy;
end;

function TFrRelationGraph.AddRelation(const pRelation: TFrRelation): Boolean;
var
  VList: TList<TFrRelation>;
  VKey: string;
begin
  Result := (pRelation.ParentKey <> '') and (pRelation.ChildTable <> '') and (pRelation.ParentTable <> '') and
    (Length(pRelation.ChildColumns) > 0) and (Length(pRelation.ChildColumns) = Length(pRelation.ParentColumns));
  if not Result then
    Exit;
  VKey := UpperCase(pRelation.ChildTable);
  if not FEdges.TryGetValue(VKey, VList) then
  begin
    VList := TList<TFrRelation>.Create;
    FEdges.Add(VKey, VList);
  end;
  VList.Add(pRelation);
  if not FTables.ContainsKey(VKey) then
    FTables.Add(VKey, pRelation.ChildTable);
  if not FTables.ContainsKey(UpperCase(pRelation.ParentTable)) then
    FTables.Add(UpperCase(pRelation.ParentTable), pRelation.ParentTable);
  Inc(FRelationCount);
end;

procedure TFrRelationGraph.Walk(const pNode, pTarget: string; pDepth: Integer;
  pVisited: TDictionary<string, Boolean>; pStack: TList<TFrRelation>; pOut: TList<TFrRelationPath>);
var
  VList: TList<TFrRelation>;
  VEdge: TFrRelation;
  VParent: string;
  VPath: TFrRelationPath;
begin
  if (pDepth <= 0) or not FEdges.TryGetValue(pNode, VList) then
    Exit;
  for VEdge in VList do
  begin
    VParent := UpperCase(VEdge.ParentTable);
    if pVisited.ContainsKey(VParent) then
      Continue;
    pStack.Add(VEdge);
    try
      if (pTarget = '') or (VParent = pTarget) then
      begin
        VPath.Steps := pStack.ToArray;
        pOut.Add(VPath);
      end;
      if VParent <> pTarget then
      begin
        pVisited.Add(VParent, True);
        try
          Walk(VParent, pTarget, pDepth - 1, pVisited, pStack, pOut);
        finally
          pVisited.Remove(VParent);
        end;
      end;
    finally
      pStack.Delete(pStack.Count - 1);
    end;
  end;
end;

function ComparePaths(const pLeft, pRight: TFrRelationPath): Integer;
begin
  Result := Length(pLeft.Steps) - Length(pRight.Steps);
  if Result = 0 then
    Result := CompareText(pLeft.Text, pRight.Text);
end;

function TFrRelationGraph.FindPaths(const pFrom, pTo: string; pDepth: Integer): TArray<TFrRelationPath>;
var
  VVisited: TDictionary<string, Boolean>;
  VStack: TList<TFrRelation>;
  VOut: TList<TFrRelationPath>;
begin
  Result := nil;
  if (pTo = '') or SameText(pFrom, pTo) then
    Exit;
  VVisited := TDictionary<string, Boolean>.Create;
  VStack := TList<TFrRelation>.Create;
  VOut := TList<TFrRelationPath>.Create(TComparer<TFrRelationPath>.Construct(ComparePaths));
  try
    VVisited.Add(UpperCase(pFrom), True);
    Walk(UpperCase(pFrom), UpperCase(pTo), pDepth, VVisited, VStack, VOut);
    VOut.Sort;
    Result := VOut.ToArray;
  finally
    VOut.Free;
    VStack.Free;
    VVisited.Free;
  end;
end;

function InNames(const pName: string; const pNames: TArray<string>): Boolean;
var
  VName: string;
begin
  Result := False;
  for VName in pNames do
    if SameText(VName, pName) then
      Exit(True);
end;

function OnlyMatch(const pPaths: TArray<TFrRelationPath>; const pTest: TFunc<TFrRelationPath, Boolean>): Integer;
var
  VI: Integer;
begin
  Result := NO_CHOICE;
  for VI := 0 to High(pPaths) do
    if pTest(pPaths[VI]) then
    begin
      if Result <> NO_CHOICE then
        Exit(NO_CHOICE);
      Result := VI;
    end;
end;

function TFrRelationGraph.Overridden(const pStep: TFrRelation): Boolean;
var
  VOther: TFrRelation;
begin
  Result := False;
  if pStep.IsDefault then
    Exit;
  for VOther in FEdges[UpperCase(pStep.ChildTable)] do
    if VOther.IsDefault and SameText(VOther.ParentTable, pStep.ParentTable) then
      Exit(True);
end;

function TFrRelationGraph.Choose(const pFrom, pTo, pStored: string; const pFormRelations: TArray<string>;
  pDepth: Integer): TFrPathChoice;

var

  VIndex: Integer;
begin
  Result.Paths := FindPaths(pFrom, pTo, pDepth);
  Result.Rule := prNone;
  Result.Chosen := NO_CHOICE;
  if Length(Result.Paths) = 0 then
    Exit;
  Result.Rule := prStored;
  VIndex := NO_CHOICE;
  if pStored <> '' then
    VIndex := OnlyMatch(Result.Paths,
      function(pPath: TFrRelationPath): Boolean
      begin
        Result := SameText(pPath.Text, pStored);
      end);
  if (VIndex = NO_CHOICE) and (Length(pFormRelations) > 0) then
  begin
    Result.Rule := prForm;
    VIndex := OnlyMatch(Result.Paths,
      function(pPath: TFrRelationPath): Boolean
      var
        VStep: TFrRelation;
      begin
        Result := True;
        for VStep in pPath.Steps do
          if not InNames(VStep.Name, pFormRelations) then
            Exit(False);
      end);
  end;
  if (VIndex = NO_CHOICE) and (Length(Result.Paths) > 1) then
  begin
    Result.Rule := prDefault;
    VIndex := OnlyMatch(Result.Paths,
      function(pPath: TFrRelationPath): Boolean
      var
        VStep: TFrRelation;
      begin
        Result := True;
        for VStep in pPath.Steps do
          if not VStep.IsDefault then
            Exit(False);
      end);
    if VIndex = NO_CHOICE then
      VIndex := OnlyMatch(Result.Paths,
        function(pPath: TFrRelationPath): Boolean
        var
          VStep: TFrRelation;
        begin
          Result := True;
          for VStep in pPath.Steps do
            if Overridden(VStep) then
              Exit(False);
        end);
  end;
  if VIndex = NO_CHOICE then
  begin
    if Length(Result.Paths) = 1 then
    begin
      Result.Rule := prSingle;
      VIndex := 0;
    end
    else
      Result.Rule := prAmbiguous;
  end;
  Result.Chosen := VIndex;
end;

function TFrRelationGraph.Stats(pDepth: Integer): TFrReachStats;
var
  VTable: string;
  VCounts: TDictionary<string, Integer>;
  VVisited: TDictionary<string, Boolean>;
  VStack: TList<TFrRelation>;
  VOut: TList<TFrRelationPath>;
  VPath: TFrRelationPath;
  VTarget: string;
  VCount: Integer;
begin
  Result := Default(TFrReachStats);
  Result.Depth := pDepth;
  VVisited := TDictionary<string, Boolean>.Create;
  VStack := TList<TFrRelation>.Create;
  VOut := TList<TFrRelationPath>.Create;
  VCounts := TDictionary<string, Integer>.Create;
  try
    for VTable in FEdges.Keys do
    begin
      VOut.Clear;
      VCounts.Clear;
      VVisited.Clear;
      VVisited.Add(VTable, True);
      Walk(VTable, '', pDepth, VVisited, VStack, VOut);
      for VPath in VOut do
      begin
        VTarget := UpperCase(VPath.Steps[High(VPath.Steps)].ParentTable);
        if VCounts.TryGetValue(VTarget, VCount) then
          VCounts[VTarget] := VCount + 1
        else
          VCounts.Add(VTarget, 1);
      end;
      for VCount in VCounts.Values do
      begin
        Inc(Result.Pairs);
        if VCount > 1 then
          Inc(Result.Ambiguous);
      end;
    end;
  finally
    VCounts.Free;
    VOut.Free;
    VStack.Free;
    VVisited.Free;
  end;
end;

function TFrRelationGraph.Tables: TArray<string>;
begin
  Result := FTables.Values.ToArray;
  TArray.Sort<string>(Result, TIStringComparer.Ordinal);
end;

end.
