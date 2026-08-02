unit ConvRules.Mappings;

{ Validation for the #mapping / #apply DSL directives.

  A #mapping declares a reusable enum -> property-value rule once and #apply pulls it
  into a #convert block. Nothing about that is checked by parsing: a target property
  that does not exist on the To class, or exists but is read-only, parses perfectly and
  then silently does nothing when the conversion runs. This unit is where that becomes
  visible.

  Pure and headless: System.* plus the model and the engine's property-tree records. No
  UI, no file I/O, no process spawn -- the property tree arrives as data, so the whole
  unit is unit-testable without an index or the drag-lint exe. }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  ConvRules.Model,
  ConvRules.Engine;

type
  /// <summary>What is wrong with a #mapping or #apply.</summary>
  /// <remarks>All kinds are ERRORS -- a rule that will not do what it says -- with the
  ///   single exception of mikNonExhaustive, which is a WARNING: leaving an enum member
  ///   unmapped is a legitimate authoring choice, not a defect. A consumer that renders
  ///   these must not treat a coverage gap with the same weight as a broken target.
  ///   <para>mikUndefined: an #apply names a #mapping that was never declared.</para>
  ///   <para>mikTargetMissing: a set target path is absent from the To class's tree.</para>
  ///   <para>mikTargetReadOnly: the target exists but cannot be assigned to.</para>
  ///   <para>mikBadLiteral: a #when fires on a value that is not a member of the source
  ///   enum.</para>
  ///   <para>mikToTypeNotDeclared: the block converts to a class the mapping never
  ///   narrowed itself to, so applying it there is out of contract.</para>
  ///   <para>mikNonExhaustive (WARNING): an enum member has neither a #when nor an
  ///   #else.</para></remarks>
  TMappingIssueKind = (mikUndefined, mikTargetMissing, mikTargetReadOnly, mikBadLiteral,
                       mikToTypeNotDeclared, mikNonExhaustive);

  /// <summary>One validation finding, addressed to a named mapping.</summary>
  /// <remarks>Detail is the specific offender -- the path, the literal, the class or the
  ///   uncovered member -- and is meant to be shown verbatim next to the kind.</remarks>
  TMappingIssue = record
    Kind   : TMappingIssueKind;
    MapName: string           ;
    Detail : string           ;
  end;

/// <summary>Validate every #mapping and #apply node in one #convert block's context.</summary>
/// <param name="ANodes">The flat node list to check, in file order. Non-mapping kinds are
///   ignored. Nodes are read only; ownership stays with the caller.</param>
/// <param name="AToTree">The property tree of the block's To class, used to resolve set
///   targets. When it has no leaves the target checks are SKIPPED entirely rather than
///   reporting every target as missing -- an absent tree is unknown, not wrong.</param>
/// <param name="AEnumMembers">The members of the mapping's source enum. When EMPTY, both
///   the literal check and the exhaustiveness check are skipped -- the member list is
///   unknown, so neither question can be answered.</param>
/// <param name="ABlockToType">Fully-qualified To type of the #convert block the mapping is
///   used in. When '' the declared-To-type check is skipped (no block context).</param>
/// <returns>Every issue found, in node order; an empty array when the mappings are sound.
///   mikNonExhaustive entries are warnings (see TMappingIssueKind); every other kind is an
///   error.</returns>
/// <remarks>Never raises. Comparisons of type names, paths, enum members and mapping names
///   are all case-insensitive, matching the DSL's own case tolerance. The node model is
///   FLAT -- a #mapping with three clauses is three sibling nodes sharing a MapName -- so
///   grouping by MapName happens here.</remarks>
function ValidateMappings(const ANodes: TArray<TRuleNode>; const AToTree: TProptree;
  const AEnumMembers: TArray<string>; const ABlockToType: string): TArray<TMappingIssue>;

implementation

{ Case-insensitive membership, the comparison the DSL uses everywhere. }
function HasText(const AArr: TArray<string>; const AValue: string): Boolean;
var
  S: string;
begin
  for S in AArr do
    if SameText(S, AValue) then Exit(True);
  Result := False;
end;

{ A declaration line is the one that names the source enum; every other #mapping node with
  the same MapName is a clause (#when or #else). }
function IsDeclaration(ANode: TRuleNode): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind = rnkMapping) and (ANode.MapFromType <> '');
end;

function IsClause(ANode: TRuleNode): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind = rnkMapping) and (ANode.MapFromType = '');
end;

function ValidateMappings(const ANodes: TArray<TRuleNode>; const AToTree: TProptree;
  const AEnumMembers: TArray<string>; const ABlockToType: string): TArray<TMappingIssue>;
var
  Issues   : TList<TMappingIssue>;
  DeclNames: TArray<string>      ;  // mappings that have a declaration line
  GroupName: TArray<string>      ;  // distinct MapNames over ALL #mapping nodes
  Node     : TRuleNode           ;
  Pair     : TSetPair            ;
  Leaf     : TPropLeaf           ;
  Name     : string              ;
  Member   : string              ;
  Covered  : TArray<string>      ;
  HasElse  : Boolean             ;

  procedure AddIssue(AKind: TMappingIssueKind; const AMapName, ADetail: string);
  var
    Issue: TMappingIssue;
  begin
    Issue.Kind    := AKind   ;
    Issue.MapName := AMapName;
    Issue.Detail  := ADetail ;
    Issues.Add(Issue);
  end;

  { The tree is flat: a dotted path is matched whole, not walked segment by segment. }
  function FindLeaf(const APath: string; out ALeaf: TPropLeaf): Boolean;
  var
    L: TPropLeaf;
  begin
    for L in AToTree.Leaves do
      if SameText(L.Path, APath) then
      begin
        ALeaf := L;
        Exit(True);
      end;
    ALeaf  := Default(TPropLeaf);
    Result := False;
  end;

begin
  Issues := TList<TMappingIssue>.Create;
  try
    // Pass 1: what is declared, and which groups exist at all.
    for Node in ANodes do
      if (Node <> nil) and (Node.Kind = rnkMapping) and (Node.MapName <> '') then
      begin
        if not HasText(GroupName, Node.MapName) then
          GroupName := GroupName + [Node.MapName];
        if IsDeclaration(Node) and not HasText(DeclNames, Node.MapName) then
          DeclNames := DeclNames + [Node.MapName];
      end;

    // Pass 2: per-node checks, in file order.
    for Node in ANodes do
    begin
      if Node = nil then Continue;

      if (Node.Kind = rnkApply) and not HasText(DeclNames, Node.ApplyName) then
        AddIssue(mikUndefined, Node.ApplyName,
          'no #mapping declares "' + Node.ApplyName + '"');

      // The declaration narrows the mapping to a set of target classes; using it in a
      // block that converts to anything else is out of contract.
      if IsDeclaration(Node) and (ABlockToType <> '') and (Length(Node.MapToTypes) > 0)
         and not HasText(Node.MapToTypes, ABlockToType) then
        AddIssue(mikToTypeNotDeclared, Node.MapName,
          ABlockToType + ' is not among the mapping''s declared target classes');

      if IsClause(Node) then
      begin
        if (not Node.IsElse) and (Node.WhenValue <> '') and (Length(AEnumMembers) > 0)
           and not HasText(AEnumMembers, Node.WhenValue) then
          AddIssue(mikBadLiteral, Node.MapName,
            '"' + Node.WhenValue + '" is not a member of ' + Node.WhenFrom + '''s enum');

        if Length(AToTree.Leaves) > 0 then
          for Pair in Node.Sets do
            if not FindLeaf(Pair.ToPath, Leaf) then
              AddIssue(mikTargetMissing, Node.MapName,
                Pair.ToPath + ' is not a property of ' + AToTree.RootType)
            else if not Leaf.IsWritable then
              AddIssue(mikTargetReadOnly, Node.MapName,
                Pair.ToPath + ' is read-only, so assigning it would do nothing');
      end;
    end;

    // Pass 3: exhaustiveness -- a WARNING, per group, and only when the member list is known.
    if Length(AEnumMembers) > 0 then
      for Name in GroupName do
      begin
        Covered := nil;
        HasElse := False;
        for Node in ANodes do
          if IsClause(Node) and SameText(Node.MapName, Name) then
          begin
            if Node.IsElse then
              HasElse := True
            else if Node.WhenValue <> '' then
              Covered := Covered + [Node.WhenValue];
          end;

        if not HasElse then
          for Member in AEnumMembers do
            if not HasText(Covered, Member) then
              AddIssue(mikNonExhaustive, Name,
                Member + ' has neither a #when nor an #else');
      end;

    Result := Issues.ToArray;
  finally
    Issues.Free;
  end;
end;

end.
