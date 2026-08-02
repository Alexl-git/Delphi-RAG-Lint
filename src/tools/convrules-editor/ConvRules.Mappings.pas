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

  /// <summary>One case of a #mapping: the enum member it fires on and the assignments
  ///   that member selects.</summary>
  /// <remarks>This is the shape an EDITOR wants -- one row per enum member -- and it is a
  ///   VIEW over the flat node model, never a replacement for it. The model stays flat:
  ///   MappingCasesOf folds nodes into cases, BuildMappingNodes unfolds cases back into
  ///   one node per line, and neither ever nests. A case whose Sets are empty is a member
  ///   the author has not mapped; it emits no line at all.</remarks>
  TMappingCase = record
    /// <summary>The enum member this case fires on; '' on the #else case.</summary>
    Member: string;
    /// <summary>True on the single #else case, which carries Sets but no member.</summary>
    IsElse: Boolean;
    /// <summary>The source property this case reads, ONLY when it differs from the
    ///   mapping's primary one; '' means "whatever the mapping reads".</summary>
    /// <remarks>Almost always ''. A mapping normally tests ONE source property, and a
    ///   case that agrees leaves this blank so the caller's AWhenFrom applies -- which is
    ///   what lets an editor rename the source property in one box. It is filled in only
    ///   for the rare clause that tests a DIFFERENT property, and then it is load-bearing:
    ///   folding '#when Style = stOK' and '#when Kind = stOK' into one case would destroy
    ///   the second condition and silently re-home its assignments onto the first.</remarks>
    WhenFrom: string;
    /// <summary>The assignments this case makes, in author order.</summary>
    Sets  : TArray<TSetPair>;
  end;

  /// <summary>A From property that applied #mappings decide conditionally, and how many
  ///   cases decide it.</summary>
  /// <remarks>What a grid needs to render such a From leaf as "&lt;conditional: N cases&gt;"
  ///   rather than as unassigned.</remarks>
  TConditionalFrom = record
    /// <summary>The From property path the #when clauses read.</summary>
    FromPath: string;
    /// <summary>Case count: one per #when on that path, plus one for the mapping's
    ///   #else when it has one.</summary>
    Cases   : Integer;
  end;

/// <summary>Severity of an issue kind: True = warning, False = error.</summary>
/// <param name="AKind">The kind to classify.</param>
/// <returns>True only for mikNonExhaustive; False for every other kind.</returns>
/// <remarks>The one place this rule is written down, so a consumer never re-derives it.
///   Non-exhaustiveness is deliberately NOT an error: a rule book may map only the enum
///   members that matter and leave the rest to the target's own defaults, which is
///   authoring intent rather than a defect. Every other kind describes a rule that will
///   silently fail to do what it says at apply time, so those must block.
///   <para>Callers gating an OK button should let warnings through and stop on errors.</para></remarks>
function MappingIssueIsWarning(AKind: TMappingIssueKind): Boolean;

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

{ ---- reading a flat node list as named mappings ----------------------------------

  Everything below is the fold/unfold pair an authoring UI needs, kept HERE rather than
  in the form so it is testable without VCL. None of it changes the model: the array in
  is read-only, the array out is one node per physical line. }

/// <summary>Every distinct #mapping name in ANodes, in first-seen order.</summary>
/// <param name="ANodes">Any node list; non-mapping kinds and nil entries are ignored.</param>
/// <returns>The names, de-duplicated case-insensitively; [] when there are none.</returns>
function MappingNames(const ANodes: TArray<TRuleNode>): TArray<string>;

/// <summary>The declaration line of the mapping called AName.</summary>
/// <param name="ANodes">The node list to search; ownership stays with the caller.</param>
/// <param name="AName">The mapping name, matched case-insensitively.</param>
/// <returns>The node carrying MapFromType/MapToTypes, or nil when the mapping has only
///   clause lines (or does not exist). The node is BORROWED -- never free it.</returns>
function MappingDeclaration(const ANodes: TArray<TRuleNode>; const AName: string): TRuleNode;

/// <summary>The source property path AName's #when clauses read.</summary>
/// <param name="ANodes">The node list to search.</param>
/// <param name="AName">The mapping name, matched case-insensitively.</param>
/// <returns>The first non-empty WhenFrom found, or '' when the mapping has no #when
///   clause yet.</returns>
/// <remarks>This is the mapping's PRIMARY source property, not its only one: the model
///   allows a different WhenFrom per clause, and MappingCasesOf keeps any clause that
///   reads something else as a case of its own rather than normalising it away. Use this
///   to seed an editor's "source property" field; use MappingCasesOf to find out whether
///   the mapping is actually uniform.</remarks>
function MappingWhenFrom(const ANodes: TArray<TRuleNode>; const AName: string): string;

/// <summary>The enum values AName's #when clauses fire on, in first-seen order.</summary>
/// <param name="ANodes">The node list to search.</param>
/// <param name="AName">The mapping name, matched case-insensitively.</param>
/// <returns>The distinct WhenValues; [] when there are no #when clauses.</returns>
/// <remarks>This is the FALLBACK member list for a source type that does not resolve --
///   method-pointer types are not indexed at all and some enums resolve ambiguously, and
///   for those the members the author already named are the only ones known.</remarks>
function MappingWhenValues(const ANodes: TArray<TRuleNode>; const AName: string): TArray<string>;

/// <summary>Fold AName's flat clause lines into one case per enum member.</summary>
/// <param name="ANodes">The node list to read; nodes are borrowed, never retained.</param>
/// <param name="AName">The mapping name, matched case-insensitively.</param>
/// <param name="AMembers">The source enum's members, in declaration order. May be [].</param>
/// <returns>One case per member of AMembers in that order, then a case for every #when
///   clause NOT already covered (a literal the enum does not contain, or one that tests a
///   different source property), then ALWAYS the #else case last -- present even when
///   empty, so an editor has a row to fill in.</returns>
/// <remarks>Clauses are keyed on the PAIR (WhenFrom, WhenValue), not on the value alone.
///   Two lines that agree on both are merged into one case with their Sets concatenated
///   in file order; two lines that name the same value but read DIFFERENT source
///   properties stay two cases, or the second one's condition would be destroyed and its
///   assignments silently re-homed onto the first.
///   <para>The mapping's PRIMARY source property is the first #when's WhenFrom. Cases
///   that read it leave TMappingCase.WhenFrom blank, so an editor renaming that property
///   in one place still works; only a divergent case pins its own.</para>
///   <para>Never raises.</para></remarks>
function MappingCasesOf(const ANodes: TArray<TRuleNode>; const AName: string;
  const AMembers: TArray<string>): TArray<TMappingCase>;

/// <summary>Unfold a mapping back into flat nodes -- one per physical line.</summary>
/// <param name="AName">The mapping's name, written on the declaration AND every clause.</param>
/// <param name="AFromType">The source enum type. '' suppresses the declaration line
///   ENTIRELY -- MapFromType is what makes a node a declaration, so a node carrying only
///   target classes would be re-read as a clause and emitted as a malformed #when.</param>
/// <param name="AToTypes">The target classes the mapping is narrowed to. Dropped along
///   with the declaration when AFromType is '', for the reason above.</param>
/// <param name="AWhenFrom">The source property path used by every case that does not pin
///   its own (see TMappingCase.WhenFrom).</param>
/// <param name="ACases">The cases to emit; a case with no Sets emits nothing.</param>
/// <returns>Freshly created nodes, Dirty and in emit order: the declaration first (when
///   there is one), then the clauses in ACases order. The CALLER OWNS every node and must
///   free them or hand them to a TRuleBook.</returns>
/// <remarks>Dirty is set so Emit() re-serializes from the typed fields; Raw is left empty
///   because these lines did not come from a file. A caller that wants an untouched
///   mapping to round-trip byte-for-byte must therefore NOT replace nodes it did not
///   change -- compare before splicing.</remarks>
function BuildMappingNodes(const AName, AFromType: string; const AToTypes: TArray<string>;
  const AWhenFrom: string; const ACases: TArray<TMappingCase>): TArray<TRuleNode>;

/// <summary>The mapping names #applied by the nodes in ANodes.</summary>
/// <param name="ANodes">Typically ONE #convert block's nodes.</param>
/// <returns>The distinct #apply names, in first-seen order; [] when the block applies
///   nothing.</returns>
function AppliedMappingNames(const ANodes: TArray<TRuleNode>): TArray<string>;

/// <summary>The From paths the applied mappings decide conditionally.</summary>
/// <param name="ANodes">Every node that could carry a #mapping clause -- normally the
///   WHOLE book, since a mapping is file-scope and an #apply reaches across blocks.</param>
/// <param name="AApplied">The mapping names in force, from AppliedMappingNames.</param>
/// <returns>One entry per distinct From path, with its case count. A path decided by two
///   applied mappings appears ONCE, with the counts summed.</returns>
/// <remarks>A mapping's #else adds one case to each From path that mapping reads, because
///   it is another branch of the same decision. A mapping with an #else but no #when
///   contributes nothing: without a #when there is no From path to attach it to.</remarks>
function ConditionalFromPaths(const ANodes: TArray<TRuleNode>;
  const AApplied: TArray<string>): TArray<TConditionalFrom>;

/// <summary>Case count for one From path, looked up in a ConditionalFromPaths result.</summary>
/// <param name="AConds">The result of ConditionalFromPaths.</param>
/// <param name="APath">The From path, matched case-insensitively.</param>
/// <returns>The case count, or 0 when no applied mapping decides that path.</returns>
/// <remarks>Exists so a caller loops over the property tree ONCE against a prepared list
///   instead of rescanning every node per leaf.</remarks>
function ConditionalCasesOf(const AConds: TArray<TConditionalFrom>;
  const APath: string): Integer;

/// <summary>The target paths the applied mappings assign.</summary>
/// <param name="ANodes">Every node that could carry a #mapping clause (normally the book).</param>
/// <param name="AApplied">The mapping names in force, from AppliedMappingNames.</param>
/// <returns>The distinct ToPaths of every clause of every applied mapping, in first-seen
///   order; [] when nothing is applied.</returns>
/// <remarks>These targets ARE assigned -- by the mapping rather than by a #link -- so a
///   pool of "unassigned To leaves" that still offers them is lying about the block.</remarks>
function MappedTargetPaths(const ANodes: TArray<TRuleNode>;
  const AApplied: TArray<string>): TArray<string>;

implementation

function MappingIssueIsWarning(AKind: TMappingIssueKind): Boolean;
begin
  Result := AKind = mikNonExhaustive;
end;

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

{ ---- fold / unfold ---------------------------------------------------------------- }

function MappingNames(const ANodes: TArray<TRuleNode>): TArray<string>;
var
  Node: TRuleNode;
begin
  Result := nil;
  for Node in ANodes do
    if (Node <> nil) and (Node.Kind = rnkMapping) and (Node.MapName <> '')
       and not HasText(Result, Node.MapName) then
      Result := Result + [Node.MapName];
end;

function MappingDeclaration(const ANodes: TArray<TRuleNode>; const AName: string): TRuleNode;
var
  Node: TRuleNode;
begin
  Result := nil;
  for Node in ANodes do
    if IsDeclaration(Node) and SameText(Node.MapName, AName) then Exit(Node);
end;

function MappingWhenFrom(const ANodes: TArray<TRuleNode>; const AName: string): string;
var
  Node: TRuleNode;
begin
  Result := '';
  for Node in ANodes do
    if IsClause(Node) and SameText(Node.MapName, AName) and (not Node.IsElse)
       and (Node.WhenFrom <> '') then
      Exit(Node.WhenFrom);
end;

function MappingWhenValues(const ANodes: TArray<TRuleNode>; const AName: string): TArray<string>;
var
  Node: TRuleNode;
begin
  Result := nil;
  for Node in ANodes do
    if IsClause(Node) and SameText(Node.MapName, AName) and (not Node.IsElse)
       and (Node.WhenValue <> '') and not HasText(Result, Node.WhenValue) then
      Result := Result + [Node.WhenValue];
end;

function MappingCasesOf(const ANodes: TArray<TRuleNode>; const AName: string;
  const AMembers: TArray<string>): TArray<TMappingCase>;
var
  L      : TList<TMappingCase>;
  Item   : TMappingCase       ;
  Node   : TRuleNode          ;
  Member : string             ;
  Primary: string             ;   // the source property the mapping mainly reads
  Placed : TArray<string>     ;   // keys already turned into a case (see CaseKey)

  { The identity of a clause: the PAIR it fires on. Keyed on both halves because the same
    value tested on two different source properties is two rules, not one. The separator
    cannot occur in either half -- a property path is dotted identifiers, a value is a
    single identifier. }
  function CaseKey(const AFrom, AValue: string): string;
  begin
    Result := AFrom + '|' + AValue;
  end;

  { Every #when clause on exactly this (property, value) pair, concatenated in file order.
    Two lines that agree on both are one case; the editor could only show one row anyway,
    and merging them loses nothing. }
  function SetsFor(const AFrom, AValue: string): TArray<TSetPair>;
  var
    N: TRuleNode;
  begin
    Result := nil;
    for N in ANodes do
      if IsClause(N) and SameText(N.MapName, AName) and (not N.IsElse)
         and SameText(N.WhenFrom, AFrom) and SameText(N.WhenValue, AValue) then
        Result := Result + N.Sets;
  end;

begin
  Primary := MappingWhenFrom(ANodes, AName);
  L := TList<TMappingCase>.Create;
  try
    for Member in AMembers do
    begin
      Item.Member   := Member;
      Item.IsElse   := False;
      Item.WhenFrom := '';                       // reads the primary property
      Item.Sets     := SetsFor(Primary, Member);
      L.Add(Item);
      Placed := Placed + [CaseKey(Primary, Member)];
    end;

    // Two kinds of clause are not covered by the member sweep above and must not vanish:
    // one on a value the enum does not contain (an unresolved type, or a typo the author
    // has to SEE), and one that tests a DIFFERENT source property. Both get their own row.
    for Node in ANodes do
      if IsClause(Node) and SameText(Node.MapName, AName) and (not Node.IsElse)
         and (Node.WhenValue <> '')
         and not HasText(Placed, CaseKey(Node.WhenFrom, Node.WhenValue)) then
      begin
        Item.Member := Node.WhenValue;
        Item.IsElse := False;
        // Blank when it agrees with the mapping's primary property, so it still follows a
        // rename; pinned only when it genuinely reads something else.
        if SameText(Node.WhenFrom, Primary) then Item.WhenFrom := ''
        else                                     Item.WhenFrom := Node.WhenFrom;
        Item.Sets   := SetsFor(Node.WhenFrom, Node.WhenValue);
        L.Add(Item);
        Placed := Placed + [CaseKey(Node.WhenFrom, Node.WhenValue)];
      end;

    // The #else pseudo-member is always last and always present, empty or not.
    Item.Member   := '';
    Item.IsElse   := True;
    Item.WhenFrom := '';
    Item.Sets     := nil;
    for Node in ANodes do
      if IsClause(Node) and SameText(Node.MapName, AName) and Node.IsElse then
        Item.Sets := Item.Sets + Node.Sets;
    L.Add(Item);

    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function BuildMappingNodes(const AName, AFromType: string; const AToTypes: TArray<string>;
  const AWhenFrom: string; const ACases: TArray<TMappingCase>): TArray<TRuleNode>;
var
  L   : TList<TRuleNode>;
  Item: TMappingCase    ;
  N   : TRuleNode       ;
begin
  L := TList<TRuleNode>.Create;
  try
    // The source type is what MAKES a node a declaration -- IsDeclaration tests exactly
    // MapFromType <> '', and Emit branches on the same field. A node with target classes
    // but no source type is therefore classified as a CLAUSE and emitted through the
    // #when branch as '#mapping M #when  =  -> ', which is not a line the grammar has.
    // So: no source type, no declaration, and the target classes are dropped with it.
    // ValidateMappings then reports every #apply naming this mapping as undefined, which
    // is the honest signal. This guard is the invariant's home; a caller's own
    // required-field check is a convenience on top of it, never the thing holding it up.
    if AFromType <> '' then
    begin
      N := TRuleNode.Create;
      N.Kind        := rnkMapping;
      N.Dirty       := True;
      N.MapName     := AName;
      N.MapFromType := AFromType;
      N.MapToTypes  := AToTypes;
      L.Add(N);
    end;

    for Item in ACases do
    begin
      if Length(Item.Sets) = 0 then Continue;   // an unmapped member has no line
      N := TRuleNode.Create;
      N.Kind    := rnkMapping;
      N.Dirty   := True;
      N.MapName := AName;
      N.Sets    := Item.Sets;
      if Item.IsElse then
        N.IsElse := True
      else
      begin
        // A case that pinned its own source property keeps it; every other one follows
        // the mapping's, which is what makes renaming that property a one-field edit.
        if Item.WhenFrom <> '' then N.WhenFrom := Item.WhenFrom
        else                        N.WhenFrom := AWhenFrom;
        N.WhenValue := Item.Member;
      end;
      L.Add(N);
    end;

    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function AppliedMappingNames(const ANodes: TArray<TRuleNode>): TArray<string>;
var
  Node: TRuleNode;
begin
  Result := nil;
  for Node in ANodes do
    if (Node <> nil) and (Node.Kind = rnkApply) and (Node.ApplyName <> '')
       and not HasText(Result, Node.ApplyName) then
      Result := Result + [Node.ApplyName];
end;

function ConditionalFromPaths(const ANodes: TArray<TRuleNode>;
  const AApplied: TArray<string>): TArray<TConditionalFrom>;
var
  L      : TList<TConditionalFrom>;
  Name   : string                 ;
  Node   : TRuleNode              ;
  Paths  : TArray<string>         ;
  Path   : string                 ;
  Item   : TConditionalFrom       ;
  Count  : Integer                ;
  HasElse: Boolean                ;
  i      : Integer                ;
  Merged : Boolean                ;
begin
  L := TList<TConditionalFrom>.Create;
  try
    for Name in AApplied do
    begin
      Paths   := nil;
      HasElse := False;
      for Node in ANodes do
        if IsClause(Node) and SameText(Node.MapName, Name) then
          if Node.IsElse then
            HasElse := True
          else if (Node.WhenFrom <> '') and not HasText(Paths, Node.WhenFrom) then
            Paths := Paths + [Node.WhenFrom];

      for Path in Paths do
      begin
        Count := 0;
        for Node in ANodes do
          if IsClause(Node) and SameText(Node.MapName, Name) and (not Node.IsElse)
             and SameText(Node.WhenFrom, Path) then
            Inc(Count);
        if HasElse then Inc(Count);

        // Two applied mappings may decide the same From path; the reader wants one
        // entry carrying the total, not two rows fighting over the same cell.
        Merged := False;
        for i := 0 to L.Count - 1 do
          if SameText(L[i].FromPath, Path) then
          begin
            Item       := L[i];
            Item.Cases := Item.Cases + Count;
            L[i]       := Item;
            Merged     := True;
            Break;
          end;
        if not Merged then
        begin
          Item.FromPath := Path;
          Item.Cases    := Count;
          L.Add(Item);
        end;
      end;
    end;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function ConditionalCasesOf(const AConds: TArray<TConditionalFrom>;
  const APath: string): Integer;
var
  C: TConditionalFrom;
begin
  for C in AConds do
    if SameText(C.FromPath, APath) then Exit(C.Cases);
  Result := 0;
end;

function MappedTargetPaths(const ANodes: TArray<TRuleNode>;
  const AApplied: TArray<string>): TArray<string>;
var
  Node: TRuleNode;
  Pair: TSetPair ;
begin
  Result := nil;
  for Node in ANodes do
    if IsClause(Node) and HasText(AApplied, Node.MapName) then
      for Pair in Node.Sets do
        if (Pair.ToPath <> '') and not HasText(Result, Pair.ToPath) then
          Result := Result + [Pair.ToPath];
end;

end.
