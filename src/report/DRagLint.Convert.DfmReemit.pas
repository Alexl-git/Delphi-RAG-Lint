unit DRagLint.Convert.DfmReemit;

{
  Track 3 (component conversion), Batch 2a-i -- the PURE DFM component re-emit
  engine. Given one F component's DFM `object` block text, a validated 1:1
  conversion rule set, and the F/T property trees, it parses the F block into an
  in-memory object model, remaps each scalar/event/sub-object/collection leaf to
  its T path (creating intermediate sub-objects for moved-depth), and
  re-serializes a well-formed T `object` block plus a structured report.

  PURE: no file I/O, no store, no CLI, no IDE, no LLM. Fully headless-testable.
  Reuses Batch 1's TConversionRuleSet (DRagLint.Convert.Rules) and TPropTree
  (DRagLint.Convert.PropTree). The only new DSL surface is #ignore (rkIgnore),
  added to DRagLint.Convert.Rules.

  Scope: 1:1 #link + #default + #ignore + #remove only. NO split/merge, NO
  expression interpreter, NO cross-type binary conversion (a binary/complex value
  is copied VERBATIM only when F and T leaf types resolve to the same type, else
  WARN). Those are deferred past 2a.
}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DRagLint.Convert.Rules,
  DRagLint.Convert.PropTree;

type
  /// <summary>The kind of one leaf or sub-node of a parsed DFM object: a scalar
  /// property, an event binding, a nested sub-object, a collection (item list),
  /// or a binary/data blob.</summary>
  TDfmNodeKind = (dnkScalar, dnkEvent, dnkSubObject, dnkCollection, dnkBinary);

  /// <summary>One node of the in-memory DFM object model: a property, event,
  /// nested object, or collection.</summary>
  /// <remarks>Name is the property/event name, or the nested object's instance
  /// name. ClassName_ is populated only for dnkSubObject nodes that are nested
  /// `object`s (the DFM class after the ':'). ValueText is the RAW property value
  /// text as it appears in the DFM (verbatim, for round-trip fidelity) and is ''
  /// ONLY for dnkSubObject nodes; dnkScalar/dnkEvent/dnkCollection/dnkBinary all
  /// carry their verbatim value in ValueText. Children are owned (freed with this
  /// node). A scalar/event/collection/binary node is a LEAF (no children); a
  /// dnkCollection's/dnkBinary's whole `&lt; ... &gt;` / `{ ... }` text is stored
  /// verbatim in ValueText, not modelled as child nodes. Only a dnkSubObject has
  /// children: its properties + nested objects.</remarks>
  TDfmNode = class
  strict private
    FChildren: TObjectList<TDfmNode>;
  public
    Name      : string;
    Kind      : TDfmNodeKind;
    ValueText : string;
    ClassName_: string;
    constructor Create;
    destructor Destroy; override;
    /// <summary>The owned child nodes (properties, nested objects, or items).</summary>
    property Children: TObjectList<TDfmNode> read FChildren;
  end;

  /// <summary>A structured report of what the re-emit did and what needs human
  /// attention. WARN-level: Dropped, Mismatched, OwnedParts. Silent: Ignored (an
  /// acknowledged #ignore).</summary>
  /// <remarks>Dropped=unmapped F props/events with a NON-default value (potential
  /// loss). Ignored=#ignore'd F props (acknowledged, no warn). Mismatched=binary/
  /// complex values whose F/T resolved types differ (WARN, not copied). Created=
  /// intermediate T sub-objects synthesized for moved-depth (Style/Active/Font).
  /// OwnedParts=nested owned parts (fields/columns) needing their own #convert
  /// rules (WARN). Notes=free-form (e.g. a relocated collection). Each entry is an
  /// ASCII, human-readable string.</remarks>
  TReemitReport = record
    Dropped   : TArray<string>;
    Ignored   : TArray<string>;
    Mismatched: TArray<string>;
    Created   : TArray<string>;
    OwnedParts: TArray<string>;
    Notes     : TArray<string>;
  end;

  /// <summary>The result of ReemitComponent: the emitted T object block plus the
  /// report, or a hard-failure flag.</summary>
  /// <remarks>DfmText is the well-formed T `object` block (2-space indentation),
  /// valid only when Ok. Ok is False only on a HARD failure: an unparseable F
  /// block, or no #convert header in the rules. Error carries the reason when Ok
  /// is False.</remarks>
  TReemitResult = record
    DfmText: string;
    Report : TReemitReport;
    Ok     : Boolean;
    Error  : string;
  end;

/// <summary>Parses one DFM `object` block into the in-memory model via
/// tree-sitter-dfm.</summary>
/// <param name="ABlockText">The raw text of ONE component's DFM object block,
/// from `object Name: TType` through its matching `end`.</param>
/// <param name="ARoot">Receives the root node (a dnkSubObject) on success; caller
/// OWNS and must Free it. Set to nil on failure.</param>
/// <returns>True when the block parsed into a single root object; False on a
/// binary DFM, an empty block, or a parse with no top-level object.</returns>
/// <remarks>Pure: no file I/O. Uses the same tree-sitter-dfm grammar the indexer
/// uses (node types object/property/identifier_value/qualified_identifier/
/// quoted_string/char_code/string), but captures property VALUES verbatim (the
/// indexer's TDFMParser is lossy -- symbols/refs only). Not thread-safe with
/// respect to the tree-sitter runtime if called concurrently.</remarks>
function ParseDfmBlock(const ABlockText: string; out ARoot: TDfmNode): Boolean;

/// <summary>Re-emit an F component's DFM object block as the T equivalent, driven
/// by a validated 1:1 rule set and the F/T property trees. Pure: no I/O.</summary>
/// <param name="AFromBlock">The raw F DFM `object` block text.</param>
/// <param name="ARules">The parsed+validated conversion rule set (must contain a
/// #convert F -&gt; T header; #link/#default/#ignore/#remove drive the remap).</param>
/// <param name="AFromTree">The F type's flattened property tree (BuildPropTree).</param>
/// <param name="AToTree">The T type's flattened property tree (BuildPropTree).</param>
/// <returns>A TReemitResult: on success, the emitted T block in DfmText plus the
/// structured Report; on hard failure, Ok=False with Error set.</returns>
/// <remarks>Only MAPPED properties are assigned -- there is NO auto-carry by
/// same-name. Every property PRESENT in the F DFM is a non-default value (DFM
/// omits defaults); an unmapped present property with no rule goes to
/// Report.Dropped (WARN, a genuine potential loss); a #ignore'd property goes to
/// Report.Ignored (no warn). Moved-depth #link creates intermediate T
/// sub-objects (Report.Created). A binary/complex value is copied VERBATIM only
/// when F/T leaf types resolve to the same type, else Report.Mismatched (not
/// copied). A nested owned part (a non-Controls/Components child) without its own
/// #convert rules is left unconverted + Report.OwnedParts. A nested Controls/
/// Components child is left ALONE. Pure; deterministic; no I/O.</remarks>
function ReemitComponent(const AFromBlock: string; const ARules: TConversionRuleSet;
  const AFromTree, AToTree: TPropTree): TReemitResult;

implementation

uses
  System.Classes,
  TreeSitter,
  TreeSitterLib,
  DRagLint.Parser.DFM; // for tree_sitter_dfm (external decl lives there)

{ TDfmNode }

constructor TDfmNode.Create;
begin
  inherited Create;
  FChildren:= TObjectList<TDfmNode>.Create(True { owns });
end;

destructor TDfmNode.Destroy;
begin
  FChildren.Free;
  inherited;
end;

// Verbatim UTF-8 slice of a node (mirrors DRagLint.Parser.DFM.NodeText).
function NodeText(const ANode: TTSNode; const ASource: TBytes): string;
var
  StartIdx, EndIdx, Len: Integer;
begin
  Result:= '';
  if ANode.IsNull then Exit;
  StartIdx:= Integer(ANode.StartByte);
  EndIdx  := Integer(ANode.EndByte  );
  Len:= EndIdx - StartIdx;
  if (Len <= 0) or (StartIdx < 0) or (EndIdx > Length(ASource)) then Exit;
  Result:= TEncoding.UTF8.GetString(ASource, StartIdx, Len);
end;

// Classify a property's value node into a TDfmNodeKind + capture verbatim text.
// Event bindings are recognized structurally (name starts with "On" + value
// node type identifier_value); collections/binary blobs are recognized by a
// TEXT-SHAPE fallback (leading '<' / '{') because the tree-sitter-dfm grammar's
// collection/binary node-type names are not documented -- DFM collection values
// always begin with '<' and data blocks with '{', so this is robust.
procedure ClassifyValue(const AName: string; const AValueNode: TTSNode;
  const ASource: TBytes; out AKind: TDfmNodeKind; out AValueText: string);
var
  Raw: string;
begin
  AValueText:= NodeText(AValueNode, ASource);
  Raw:= Trim(AValueText);
  if (Copy(AName, 1, 2) = 'On') and (not AValueNode.IsNull) and
     (AValueNode.NodeType = 'identifier_value') then
    AKind:= dnkEvent
  else if (Raw <> '') and (Raw[1] = '<') then
    AKind:= dnkCollection
  else if (Raw <> '') and (Raw[1] = '{') then
    AKind:= dnkBinary
  else
    AKind:= dnkScalar;
end;

// Walks the named children of a tree-sitter object/source node, appending a
// TDfmNode (owned by AParent) per nested `object` (recursed) or `property`.
procedure WalkNodeInto(const ATsNode: TTSNode; const ASource: TBytes;
  const AParent: TDfmNode);
var
  i        : Integer;
  Child    : TTSNode;
  NameNode : TTSNode;
  ValueNode: TTSNode;
  ClassNode: TTSNode;
  Sub      : TDfmNode;
  Prop     : TDfmNode;
  K        : TDfmNodeKind;
  VText    : string;
begin
  for i:= 0 to ATsNode.NamedChildCount - 1 do
  begin
    Child:= ATsNode.NamedChild(i);
    if Child.NodeType = 'object' then
    begin
      Sub:= TDfmNode.Create;
      Sub.Kind:= dnkSubObject;
      NameNode := Child.ChildByField('name');
      ClassNode:= Child.ChildByField('class');
      if not NameNode.IsNull then Sub.Name:= NodeText(NameNode, ASource);
      if not ClassNode.IsNull then Sub.ClassName_:= NodeText(ClassNode, ASource);
      AParent.Children.Add(Sub);
      WalkNodeInto(Child, ASource, Sub); // recurse into the nested object
    end
    else if Child.NodeType = 'property' then
    begin
      NameNode := Child.ChildByField('name');
      ValueNode:= Child.ChildByField('value');
      if NameNode.IsNull then Continue;
      Prop:= TDfmNode.Create;
      Prop.Name:= NodeText(NameNode, ASource);
      ClassifyValue(Prop.Name, ValueNode, ASource, K, VText);
      Prop.Kind     := K;
      Prop.ValueText:= VText;
      AParent.Children.Add(Prop);
    end;
  end;
end;

function ParseDfmBlock(const ABlockText: string; out ARoot: TDfmNode): Boolean;
var
  Src      : TBytes;
  Parser   : TTSParser;
  Tree     : TTSTree;
  Root     : TTSNode;
  ObjNode  : TTSNode;
  NameNode : TTSNode;
  ClassNode: TTSNode;
  i        : Integer;
  Found    : Boolean;
begin
  ARoot := nil;
  Result:= False;
  if Trim(ABlockText) = '' then Exit;
  Src:= TEncoding.UTF8.GetBytes(ABlockText);
  if (Length(Src) > 0) and (Src[0] = $FF) then Exit; // binary DFM unsupported
  Parser:= nil; Tree:= nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= tree_sitter_dfm;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      var Remaining: Integer;
      begin
        Remaining:= Length(Src) - Integer(AByteIndex);
        if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end;
        SetLength(Result, Remaining);
        Move(Src[AByteIndex], Result[0], Remaining);
        ABytesRead:= Remaining;
      end, TTSInputEncoding.TSInputEncodingUTF8);
    Root:= Tree.RootNode;
    // source_file -> [object ...]. Take the FIRST top-level object as the root.
    Found:= False;
    ObjNode:= Root; // placeholder assignment; overwritten below when Found
    for i:= 0 to Root.NamedChildCount - 1 do
    begin
      ObjNode:= Root.NamedChild(i);
      if ObjNode.NodeType = 'object' then begin Found:= True; Break; end;
    end;
    if not Found then Exit;
    ARoot:= TDfmNode.Create;
    ARoot.Kind:= dnkSubObject;
    NameNode := ObjNode.ChildByField('name');
    ClassNode:= ObjNode.ChildByField('class');
    if not NameNode.IsNull then ARoot.Name:= NodeText(NameNode, Src);
    if not ClassNode.IsNull then ARoot.ClassName_:= NodeText(ClassNode, Src);
    WalkNodeInto(ObjNode, Src, ARoot);
    Result:= True;
  finally
    Tree.Free;
    Parser.Free;
  end;
end;

// Render a 2-space indent prefix.
function Ind(ALevel: Integer): string;
begin
  Result:= StringOfChar(' ', ALevel * 2);
end;

// Re-serialize a TDfmNode sub-object tree to well-formed DFM text. Scalars/events
// emit `Name = Value`; nested objects emit `object Name: TClass ... end`;
// collections/binary values emit their verbatim ValueText (which already carries
// the `< ... >` / `{ ... }` structure). Indentation normalized to 2 spaces.
function EmitBlock(const ANode: TDfmNode; AIndent: Integer): string;
var
  SB   : TStringBuilder;
  Child: TDfmNode;
  Head : string;
begin
  SB:= TStringBuilder.Create;
  try
    // Header line for a sub-object.
    if ANode.ClassName_ <> '' then
      Head:= Format('object %s: %s', [ANode.Name, ANode.ClassName_])
    else
      Head:= Format('object %s', [ANode.Name]);
    SB.Append(Ind(AIndent)).Append(Head).Append(#13#10);
    for Child in ANode.Children do
    begin
      case Child.Kind of
        dnkSubObject:
          SB.Append(EmitBlock(Child, AIndent + 1));
        dnkScalar, dnkEvent, dnkBinary, dnkCollection:
          SB.Append(Ind(AIndent + 1))
            .Append(Child.Name).Append(' = ').Append(Child.ValueText)
            .Append(#13#10);
      end;
    end;
    SB.Append(Ind(AIndent)).Append('end').Append(#13#10);
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

// Ensure the dotted ToPath exists under ARoot, creating intermediate dnkSubObject
// nodes for every segment but the last (each new intermediate recorded in
// ACreated by its dotted prefix). The final segment becomes/updates a leaf node
// of AKind with AValueText. Returns the leaf node.
function PlaceAtPath(const ARoot: TDfmNode; const ADottedPath, AValueText: string;
  AKind: TDfmNodeKind; var ACreated: TArray<string>): TDfmNode;
var
  Segs   : TArray<string>;
  Cur    : TDfmNode;
  Child  : TDfmNode;
  i, j   : Integer;
  Prefix : string;
  Found  : Boolean;
begin
  Segs:= ADottedPath.Split(['.']);
  Cur := ARoot;
  Prefix:= '';
  for i:= 0 to High(Segs) - 1 do // every segment EXCEPT the last -> sub-objects
  begin
    if Prefix = '' then Prefix:= Segs[i] else Prefix:= Prefix + '.' + Segs[i];
    Found:= False;
    for j:= 0 to Cur.Children.Count - 1 do
      if SameText(Cur.Children[j].Name, Segs[i]) and
         (Cur.Children[j].Kind = dnkSubObject) then
      begin Cur:= Cur.Children[j]; Found:= True; Break; end;
    if not Found then
    begin
      Child:= TDfmNode.Create;
      Child.Name:= Segs[i];
      Child.Kind:= dnkSubObject;
      // A synthesized intermediate has no DFM class of its own (it is a sub-property
      // object like Font/Style); emit as `object Name` with no class, which the
      // DFM streamer accepts for owned TPersistent sub-properties. If a class is
      // required by the T shape, 2a-ii/iii supply it; 2a-i notes the creation.
      Cur.Children.Add(Child);
      ACreated:= ACreated + [Prefix];
      Cur:= Child;
    end;
  end;
  // Final segment -> the leaf.
  Found:= False;
  for j:= 0 to Cur.Children.Count - 1 do
    if SameText(Cur.Children[j].Name, Segs[High(Segs)]) then
    begin Child:= Cur.Children[j]; Found:= True; Break; end;
  if not Found then
  begin
    Child:= TDfmNode.Create;
    Child.Name:= Segs[High(Segs)];
    Cur.Children.Add(Child);
  end;
  Child.Kind     := AKind;
  Child.ValueText:= AValueText;
  Result:= Child;
end;

// Deep-copy a TDfmNode subtree (for verbatim copies of contained children /
// unconverted owned parts / relocated collections).
function CloneNode(const ASrc: TDfmNode): TDfmNode;
var C: TDfmNode;
begin
  Result:= TDfmNode.Create;
  Result.Name      := ASrc.Name;
  Result.Kind      := ASrc.Kind;
  Result.ValueText := ASrc.ValueText;
  Result.ClassName_:= ASrc.ClassName_;
  for C in ASrc.Children do
    Result.Children.Add(CloneNode(C));
end;

// Look up a #convert rule for a specific From part-type. 2a-i recurses with the
// SAME ARules (the nested #convert header for the part type is found by
// ReemitComponent itself). Returns True if ANY #convert names AFromType as its
// FromType.
function HasConvertFor(const ARules: TConversionRuleSet; const AFromType: string): Boolean;
var Q: TConversionRule;
begin
  Result:= False;
  for Q in ARules.Rules do
    if (Q.Kind = rkConvert) and SameText(Q.FromType, AFromType) then Exit(True);
end;

// Resolve a leaf's declared type from a property tree by its top-level name.
function LeafTypeOf(const ATree: TPropTree; const AName: string): string;
var N: TPropNode;
begin
  Result:= '';
  for N in ATree.Nodes do
    if SameText(N.Path, AName) then Exit(N.TypeName);
end;

// 2a-i deterministic owned-part signal: a `#note owned:<ClassName>` in the rules
// declares a nested class as an OWNED part (a field/column) that needs its own
// #convert. Without the full class graph, this is the explicit, testable marker;
// 2a-ii wires the index-based Controls/Components container check that replaces it.
function IsOwnedPartByRulesHint(const ARules: TConversionRuleSet; const AClass: string): Boolean;
var Q: TConversionRule;
begin
  Result:= False;
  for Q in ARules.Rules do
    if (Q.Kind = rkNote) and SameText(Trim(Q.Text), 'owned:' + AClass) then Exit(True);
end;

function ReemitComponent(const AFromBlock: string; const ARules: TConversionRuleSet;
  const AFromTree, AToTree: TPropTree): TReemitResult;
var
  FRoot, TRoot: TDfmNode;
  R           : TConversionRule;
  HaveConvert : Boolean;
  ToType      : string;
  Created     : TArray<string>;
  Dropped     : TArray<string>;
  Ignored     : TArray<string>;

  // Find a #link whose FromPath equals AFromPath (a top-level F property name in
  // 2a-i; deep F paths supported for completeness).
  function FindLinkFor(const AFromPath: string; out AToPath: string): Boolean;
  var Q: TConversionRule;
  begin
    Result:= False; AToPath:= '';
    for Q in ARules.Rules do
      if (Q.Kind = rkLink) and SameText(Q.FromPath, AFromPath) then
      begin AToPath:= Q.ToPath; Exit(True); end;
  end;

  function IsIgnored(const AFromPath: string): Boolean;
  var Q: TConversionRule;
  begin
    Result:= False;
    for Q in ARules.Rules do
      if (Q.Kind = rkIgnore) and SameText(Q.FromPath, AFromPath) then Exit(True);
  end;

  function IsRemoved(const APropName: string): Boolean;
  var Q: TConversionRule;
  begin
    Result:= False;
    for Q in ARules.Rules do
      if (Q.Kind = rkRemove) and SameText(Q.PropName, APropName) then Exit(True);
  end;

  // NOTE (Controller decision 1): there is NO IsDefaultValued check. DFM only
  // serializes NON-default values, so every property PRESENT in the F block is a
  // developer-set value that MUST be carried. An unmapped present property with
  // no rule is therefore a genuine potential loss -> Dropped (WARN), never a
  // silent default-drop.
  //
  // DEFAULT-OVERLAY SEAM (Controller decision 2, Batch 2a-0 plugs in here): the
  // F-default-vs-T-default divergence for properties ABSENT from the DFM is a
  // known gap. When 2a-0 lands (indexer captures `default` specifiers), the
  // caller will materialize F's absent-but-non-T-default properties and inject
  // them as synthetic leaves BEFORE this loop -- RemapLeaf needs NO change then.
  // 2a-i only sees what is in the DFM.

  procedure RemapLeaf(const ALeaf: TDfmNode);
  var ToPath: string;
  begin
    if IsRemoved(ALeaf.Name) then Exit; // #remove: ensure absent from T
    if IsIgnored(ALeaf.Name) then
    begin Ignored:= Ignored + [ALeaf.Name]; Exit; end;
    if FindLinkFor(ALeaf.Name, ToPath) then
    begin
      if Trim(ToPath) = '???' then
      begin Result.Report.Notes:= Result.Report.Notes + [Format('unfilled ToPath (???) for %s', [ALeaf.Name])]; Exit; end;
      if ALeaf.Kind = dnkCollection then
      begin
        // Collection relocate-keep-items: move the whole collection verbatim.
        PlaceAtPath(TRoot, ToPath, ALeaf.ValueText, dnkCollection, Created);
        Result.Report.Notes:= Result.Report.Notes +
          [Format('collection %s relocated to %s, items unchanged', [ALeaf.Name, ToPath])];
        Exit;
      end;
      if ALeaf.Kind = dnkBinary then
      begin
        // Copy a binary/complex value only when F and T leaf types resolve to the
        // same type; else WARN and do not copy (cross-type conversion is the
        // interpreter stage, deferred past 2a).
        var FType: string; var TType: string;
        FType:= LeafTypeOf(AFromTree, ALeaf.Name);
        TType:= LeafTypeOf(AToTree, ToPath);
        if (FType <> '') and (TType <> '') and (not SameText(FType, TType)) then
        begin
          Result.Report.Mismatched:= Result.Report.Mismatched +
            [Format('%s: F type %s != T type %s (binary not copied)', [ALeaf.Name, FType, TType])];
          Exit;
        end;
        PlaceAtPath(TRoot, ToPath, ALeaf.ValueText, dnkBinary, Created);
        Exit;
      end;
      PlaceAtPath(TRoot, ToPath, ALeaf.ValueText, ALeaf.Kind, Created);
      Exit;
    end;
    // UNMAPPED + present in the DFM == non-default -> genuine potential loss.
    Dropped:= Dropped + [ALeaf.Name];
  end;

  procedure HandleNested(const ASub: TDfmNode);
  var
    PartResult: TReemitResult;
    Clone     : TDfmNode;
  begin
    if HasConvertFor(ARules, ASub.ClassName_) then
    begin
      // OWNED part with a rule -> recurse. Re-emit the part block by round-
      // tripping it: emit the sub-object as its own block, re-run ReemitComponent.
      PartResult:= ReemitComponent(EmitBlock(ASub, 0), ARules, AFromTree, AToTree);
      if PartResult.Ok then
      begin
        // Re-parse the converted part text back into a node and graft it.
        var PartRoot: TDfmNode;
        if ParseDfmBlock(PartResult.DfmText, PartRoot) then
        begin
          TRoot.Children.Add(PartRoot); // TRoot owns it now
          // fold the part's report notes up
          Result.Report.Created := Result.Report.Created + PartResult.Report.Created;
          Result.Report.Dropped := Result.Report.Dropped + PartResult.Report.Dropped;
        end;
      end;
    end
    else
    begin
      // No #convert for this nested class -> contained child OR unconverted owned
      // part. 2a-i heuristic: copy verbatim; flag in OwnedParts only when a
      // `#note owned:<Class>` marker explicitly declares it an owned part.
      Clone:= CloneNode(ASub);
      TRoot.Children.Add(Clone);
      if IsOwnedPartByRulesHint(ARules, ASub.ClassName_) then
        Result.Report.OwnedParts:= Result.Report.OwnedParts +
          [Format('%s: %s -- owned part with no #convert rule (left unconverted)', [ASub.Name, ASub.ClassName_])];
    end;
  end;

var
  i: Integer;
  Leaf: TDfmNode;
begin
  Result:= Default(TReemitResult);
  FRoot := nil; TRoot:= nil;
  Created:= nil; Dropped:= nil; Ignored:= nil;

  // 1. Require a #convert header.
  HaveConvert:= False; ToType:= '';
  for R in ARules.Rules do
    if R.Kind = rkConvert then
    begin HaveConvert:= True; ToType:= R.ToType; Break; end;
  if not HaveConvert then
  begin
    Result.Ok:= False;
    Result.Error:= 'no #convert F -> T header in the rule set';
    Exit;
  end;

  // 2. Parse the F block.
  if not ParseDfmBlock(AFromBlock, FRoot) then
  begin
    Result.Ok:= False;
    Result.Error:= 'could not parse the F DFM object block';
    Exit;
  end;

  try
    // 3. Build the T root: same instance Name, swapped class.
    TRoot:= TDfmNode.Create;
    TRoot.Kind      := dnkSubObject;
    TRoot.Name      := FRoot.Name;
    TRoot.ClassName_:= ToType;

    // 4. Per top-level F leaf, remap. Nested sub-objects are classified as an
    // owned part (recurse via #convert) or a contained child (copied verbatim).
    for i:= 0 to FRoot.Children.Count - 1 do
    begin
      Leaf:= FRoot.Children[i];
      if Leaf.Kind = dnkSubObject then HandleNested(Leaf)
      else RemapLeaf(Leaf);
    end;

    // 5. Apply #default (T-only props).
    for R in ARules.Rules do
      if R.Kind = rkDefault then
      begin
        if Trim(R.ToPath) = '???' then Continue;
        PlaceAtPath(TRoot, R.ToPath, R.Value, dnkScalar, Created);
      end;

    // 6. Divergence-risk Note (Controller decision 4): when F and T are different
    // types, a property absent from the F DFM (== F default) may adopt a DIFFERENT
    // T default when re-emitted absent. 2a-i cannot resolve this (indexer has no
    // default values -- Batch 2a-0); warn the user it MAY happen.
    if (AFromTree.RootType <> '') and (AToTree.RootType <> '') and
       (not SameText(AFromTree.RootType, AToTree.RootType)) then
      Result.Report.Notes:= Result.Report.Notes +
        [Format('property defaults may diverge between %s and %s -- values not present in the F DFM adopt the T default (verify; full default fidelity pending Batch 2a-0)',
          [AFromTree.RootType, AToTree.RootType])];

    // Fold the local accumulators into the report (do NOT clobber Task-6 appends).
    Result.Report.Created:= Result.Report.Created + Created;
    Result.Report.Dropped:= Result.Report.Dropped + Dropped;
    Result.Report.Ignored:= Result.Report.Ignored + Ignored;
    Result.DfmText:= EmitBlock(TRoot, 0);
    Result.Ok:= True;
  finally
    FRoot.Free;
    TRoot.Free;
  end;
end;

end.
