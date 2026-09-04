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
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Convert.DfmReemit.pas), DRagLint.Convert.DfmReemit.WalkNodeInto (DRagLint.Convert.DfmReemit.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDfmNodeKind = (dnkScalar, dnkEvent, dnkSubObject, dnkCollection, dnkBinary);

  /// <summary>One node of the in-memory DFM object model: a property, event,
  /// nested object, or collection.</summary>
  /// <remarks>
  /// Name is the property/event name, or the nested object's instance
  /// name. ClassName_ is populated only for dnkSubObject nodes that are nested
  /// `object`s (the DFM class after the ':'). ValueText is the RAW property value
  /// text as it appears in the DFM (verbatim, for round-trip fidelity) and is ''
  /// ONLY for dnkSubObject nodes; dnkScalar/dnkEvent/dnkCollection/dnkBinary all
  /// carry their verbatim value in ValueText. Children are owned (freed with this
  /// node). A scalar/event/collection/binary node is a LEAF (no children); a
  /// dnkCollection's/dnkBinary's whole `&lt; ... &gt;` / `{ ... }` text is stored
  /// verbatim in ValueText, not modelled as child nodes. Only a dnkSubObject has
  /// children: its properties + nested objects.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Convert.DfmReemit.pas), DRagLint.Convert.DfmReemit.WalkNodeInto (DRagLint.Convert.DfmReemit.pas), DRagLint.Convert.DfmReemit.ParseDfmBlock (DRagLint.Convert.DfmReemit.pas), DRagLint.Convert.DfmReemit.EmitBlock (DRagLint.Convert.DfmReemit.pas), DRagLint.Convert.DfmReemit.PlaceAtPath (DRagLint.Convert.DfmReemit.pas) (+3 more)</para>
  /// <para>Used in units: DRagLint.Convert.DfmReemit</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDfmNode = class
  strict private
    FChildren: TObjectList<TDfmNode>;
  public
    Name      : string;
    Kind      : TDfmNodeKind;
    ValueText : string;
    ClassName_: string;
    /// <summary><!-- drag-lint:auto -->TDfmNode</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Convert.DfmReemit.CloneNode (DRagLint.Convert.DfmReemit.pas), DRagLint.Convert.DfmReemit.ParseDfmBlock (DRagLint.Convert.DfmReemit.pas), DRagLint.Convert.DfmReemit.PlaceAtPath (DRagLint.Convert.DfmReemit.pas), DRagLint.Convert.DfmReemit.ReemitComponent (DRagLint.Convert.DfmReemit.pas), DRagLint.Convert.DfmReemit.WalkNodeInto (DRagLint.Convert.DfmReemit.pas)</para>
    /// <para>constructor</para>
    /// <para>Writes: FChildren</para>
    /// <seealso cref="DRagLint.Convert.DfmReemit.TDfmNode.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create;
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: FChildren</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Convert.DfmReemit.TDfmNode.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    destructor Destroy; override;
    /// <summary>The owned child nodes (properties, nested objects, or items).</summary>
    property Children: TObjectList<TDfmNode> read FChildren;
  end;

  /// <summary>A structured report of what the re-emit did and what needs human
  /// attention. WARN-level: Dropped, Mismatched, OwnedParts. Silent: Ignored (an
  /// acknowledged #ignore).</summary>
  /// <remarks>
  /// Dropped=unmapped F props/events with a NON-default value (potential
  /// loss). Ignored=#ignore'd F props (acknowledged, no warn). Mismatched=binary/
  /// complex values whose F/T resolved types differ (WARN, not copied). Created=
  /// intermediate T sub-objects synthesized for moved-depth (Style/Active/Font).
  /// OwnedParts=nested owned parts (fields/columns) needing their own #convert
  /// rules (WARN). Stubs=#link targets still spelled '???' (an unfilled rule, so
  /// the F value was NOT carried over). Relocated=collections moved verbatim to a
  /// new ToPath (INFO). Notes=everything else, currently only the F/T default-
  /// divergence warning. Each entry is an ASCII, human-readable string.
  ///
  /// Stubs/Relocated were split OUT of Notes so a consumer can assign each entry a
  /// stable kind without matching on its prose (DRagLint.Convert.Apply's typed
  /// TApplyItem). The convert-reemit JSON still emits 'notes' as the UNION of the
  /// three, so existing consumers keep seeing what they saw; 'stubs' and
  /// 'relocated' are additive keys.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Convert.DfmReemit.pas)</para>
  /// <para>Used in units: DRagLint.Convert.DfmReemit</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  /// <summary>One applied #mapping that matched NOTHING: the source leaf was
  /// present and carried a value, but no #when branch matched it and the
  /// mapping had no #else to fall back to.</summary>
  /// <remarks>
  /// This is REMAINDER, and the reason the type exists: the value is still in
  /// the F DFM, the operator asked for it to be mapped, and it was not. Left as
  /// prose it is indistinguishable from an ordinary note, so it carries the
  /// mapping's name, the #apply line that requested it, the source path and the
  /// unmatched value -- everything needed to fix the rule book.
  ///
  /// A source leaf that is ABSENT is NOT recorded here: there was nothing to
  /// map, which is an informational note, not unfinished work.
  /// </remarks>
  TReemitNotApplied = record
    MapName : string;
    RuleLine: Integer; { the #apply line that requested the mapping }
    Path    : string;  { the F property path whose value went unmatched }
    Value   : string;  { that value, verbatim }
  end;

  TReemitReport = record
    Dropped    : TArray<string>;
    Ignored    : TArray<string>;
    Mismatched : TArray<string>;
    Created    : TArray<string>;
    OwnedParts : TArray<string>;
    Stubs      : TArray<string>;
    Relocated  : TArray<string>;
    /// <summary>Informational: an applied mapping whose source path is not in
    /// this block, so there was nothing to map.</summary>
    MappingNotes: TArray<string>;
    NotApplied  : TArray<TReemitNotApplied>;
    Notes       : TArray<string>;
  end;

  /// <summary>The result of ReemitComponent: the emitted T object block plus the
  /// report, or a hard-failure flag.</summary>
  /// <remarks>
  /// DfmText is the well-formed T `object` block (2-space indentation),
  /// valid only when Ok. Ok is False only on a HARD failure: an unparseable F
  /// block, or no #convert header in the rules. Error carries the reason when Ok
  /// is False.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoConvertReemit (DRagLint.CLI.pas), DRagLint.Convert.Apply.BuildApplyPlan (DRagLint.Convert.Apply.pas), declaration (DRagLint.Convert.DfmReemit.pas), DRagLint.Convert.DfmReemit.ReemitComponent (DRagLint.Convert.DfmReemit.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Convert.Apply, DRagLint.Convert.DfmReemit</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
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
/// <remarks>
/// Pure: no file I/O. Uses the same tree-sitter-dfm grammar the indexer
/// uses (node types object/property/identifier_value/qualified_identifier/
/// quoted_string/char_code/string), but captures property VALUES verbatim (the
/// indexer's TDFMParser is lossy -- symbols/refs only). Not thread-safe with
/// respect to the tree-sitter runtime if called concurrently.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Convert.DfmReemit.ReemitComponent (DRagLint.Convert.DfmReemit.pas), DRagLint.Convert.DfmReemit.ReemitComponent.HandleNested (DRagLint.Convert.DfmReemit.pas)</para>
/// <para>Calls: DRagLint.Convert.DfmReemit.NodeText, DRagLint.Convert.DfmReemit.TDfmNode.Create, DRagLint.Convert.DfmReemit.WalkNodeInto, Integer, Move, TreeSitter.TTSParser.Create, TreeSitter.TTSParser.Parse, Trim</para>
/// <para>Complexity: 10 (cyclomatic, outer body), 53 lines (full implementation)</para>
/// <para>Mutates: ARoot (out)</para>
/// <seealso cref="DRagLint.Convert.DfmReemit.NodeText"/>
/// <seealso cref="DRagLint.Convert.DfmReemit.TDfmNode.Create"/>
/// <seealso cref="DRagLint.Convert.DfmReemit.WalkNodeInto"/>
/// <seealso cref="TreeSitter.TTSParser.Create"/>
/// <seealso cref="TreeSitter.TTSParser.Parse"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
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
/// <remarks>
/// Only MAPPED properties are assigned -- there is NO auto-carry by
/// same-name. Every property PRESENT in the F DFM is a non-default value (DFM
/// omits defaults); an unmapped present property with no rule goes to
/// Report.Dropped (WARN, a genuine potential loss); a #ignore'd property goes to
/// Report.Ignored (no warn). Moved-depth #link creates intermediate T
/// sub-objects (Report.Created). A binary/complex value is copied VERBATIM only
/// when F/T leaf types resolve to the same type, else Report.Mismatched (not
/// copied). A nested owned part (a non-Controls/Components child) without its own
/// #convert rules is left unconverted + Report.OwnedParts. A nested Controls/
/// Components child is left ALONE. Pure; deterministic; no I/O.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoConvertReemit (DRagLint.CLI.pas), DRagLint.Convert.Apply.BuildApplyPlan (DRagLint.Convert.Apply.pas), DRagLint.Convert.DfmReemit.ReemitComponent.HandleNested (DRagLint.Convert.DfmReemit.pas)</para>
/// <para>Calls: CloneNode, Copy, Default, DRagLint.Convert.DfmReemit.BareTypeTail, DRagLint.Convert.DfmReemit.EmitBlock, DRagLint.Convert.DfmReemit.ParseDfmBlock, DRagLint.Convert.DfmReemit.PlaceAtPath, DRagLint.Convert.DfmReemit.ReemitComponent.HandleNested, DRagLint.Convert.DfmReemit.ReemitComponent.RemapLeaf, DRagLint.Convert.DfmReemit.TDfmNode.Create (+11 more)</para>
/// <para>Returns: Default(TReemitResult)</para>
/// <para>Complexity: 14 (cyclomatic, outer body), 275 lines (full implementation)</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Convert.DfmReemit.BareTypeTail"/>
/// <seealso cref="DRagLint.Convert.DfmReemit.EmitBlock"/>
/// <seealso cref="DRagLint.Convert.DfmReemit.ParseDfmBlock"/>
/// <seealso cref="DRagLint.Convert.DfmReemit.PlaceAtPath"/>
/// <seealso cref="DRagLint.Convert.DfmReemit.ReemitComponent.HandleNested"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
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

// Strips a leading 'Unit.' qualifier from a type name (e.g. 'LibA.TSrcBtn' ->
// 'TSrcBtn'; 'TSrcBtn' unchanged). Mirrors DRagLint.Convert.Apply's
// BareTypeTail (duplicated here rather than imported -- DRagLint.Convert.Apply
// already `uses` this unit, so importing back would be circular): a
// #convert rule's FromType/ToType may be written qualified, but a .dfm
// object's ClassName_ is always the bare tail, so every match/emit against it
// must compare/emit bare too (Bug 1 -- see DRagLint.Convert.Apply.
// BareTypeTail's own remarks).
function BareTypeTail(const AQName: string): string;
var
  DotAt: Integer;
begin
  DotAt:= LastDelimiter('.', AQName);
  if DotAt > 0 then Result:= Copy(AQName, DotAt + 1, MaxInt)
  else Result:= AQName;
end;

// Look up a #convert rule for a specific From part-type. 2a-i recurses with the
// SAME ARules (the nested #convert header for the part type is found by
// ReemitComponent itself). Returns True if ANY #convert names AFromType as its
// FromType (bare-tail compared -- see BareTypeTail).
function HasConvertFor(const ARules: TConversionRuleSet; const AFromType: string): Boolean;
var Q: TConversionRule;
begin
  Result:= False;
  for Q in ARules.Rules do
    if (Q.Kind = rkConvert) and SameText(BareTypeTail(Q.FromType), AFromType) then Exit(True);
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
  { F paths a #mapping has consumed -- see IsConsumed / ApplyMappings. }
  ConsumedPaths: TArray<string>;

  // Find a #link whose FromPath equals AFromPath (the dotted lookup key -- a
  // top-level F property name, OR a 'SubObj.Leaf' path when the leaf lives
  // inside a nested F sub-object with no #convert of its own; see
  // HandleNested's moved-depth-inside-a-sub-object branch below).
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

  // True when a #mapping already consumed this F path. Checked in RemapLeaf
  // exactly like IsIgnored: the mapping has ALREADY written the T side, so
  // re-emitting the raw F leaf would either duplicate it or, worse, overwrite
  // the mapped value with the unmapped one.
  function IsConsumed(const AFromPath: string): Boolean;
  var S: string;
  begin
    Result:= False;
    for S in ConsumedPaths do
      if SameText(S, AFromPath) then Exit(True);
  end;

  // Resolve a dotted F path ('Style.Active.Mode') against the parsed F tree.
  // Returns the leaf's verbatim ValueText. A dnkSubObject yields '' (it has no
  // value of its own), so callers get True with an empty value -- present, but
  // not a scalar.
  function FindLeafValue(const ADottedPath: string; out AValue: string): Boolean;
  var
    Segs : TArray<string>;
    Node : TDfmNode      ;
    i, j : Integer       ;
    Found: Boolean       ;
  begin
    Result:= False;
    AValue:= '';
    if (ADottedPath = '') or (not Assigned(FRoot)) then Exit;
    Segs:= ADottedPath.Split(['.']);
    Node:= FRoot;
    for i:= 0 to High(Segs) do
    begin
      Found:= False;
      for j:= 0 to Node.Children.Count - 1 do
        if SameText(Node.Children[j].Name, Segs[i]) then
        begin
          Node := Node.Children[j];
          Found:= True;
          Break;
        end;
      if not Found then Exit(False);
    end;
    AValue:= Node.ValueText;
    Result:= True;
  end;

  // True when ANY #link/#ignore/#remove rule's FromPath/PropName references a
  // dotted path under APrefix + '.' (e.g. prefix 'Font' matches 'Font.Size').
  // Used by HandleNested to recognize a nested F sub-object (no #convert of its
  // own) whose CHILDREN are individually redirected by moved-depth #link rules,
  // as opposed to an ordinary contained child that must be copied verbatim.
  function HasDeepRuleUnder(const APrefix: string): Boolean;
  var
    Q     : TConversionRule;
    DotPfx: string;
  begin
    Result:= False;
    DotPfx:= APrefix + '.';
    for Q in ARules.Rules do
    begin
      case Q.Kind of
        rkLink  : if (Length(Q.FromPath) > Length(DotPfx)) and SameText(Copy(Q.FromPath, 1, Length(DotPfx)), DotPfx) then Exit(True);
        rkIgnore: if (Length(Q.FromPath) > Length(DotPfx)) and SameText(Copy(Q.FromPath, 1, Length(DotPfx)), DotPfx) then Exit(True);
        rkRemove: if (Length(Q.PropName) > Length(DotPfx)) and SameText(Copy(Q.PropName, 1, Length(DotPfx)), DotPfx) then Exit(True);
      end;
    end;
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

  // AFromPath is the dotted RULE-LOOKUP key ('Caption' for a top-level leaf,
  // 'Font.Size' for a leaf one level inside a moved-depth F sub-object); ALeaf
  // supplies the actual DFM Kind/ValueText and its bare Name for report text.
  { -- #mapping / #apply -------------------------------------------------------

    A #mapping is a named, reusable conditional value map, authored as THREE
    FLAT SIBLING line forms tied together only by its name:

      #mapping M from <EnumType> to <Class>[, ...]      (declaration)
      #mapping M #when <Path> = <Value> -> <ToPath> = <V>[, ...]
      #mapping M #else                  -> <ToPath> = <V>[, ...]

    and requested by '#apply M'. This pass runs BEFORE the step-4 leaf loop, not
    after: RemapLeaf would otherwise already have recorded the source leaf as
    Dropped, and a leaf cannot be un-dropped. }

  // Is this #apply in scope for THIS block? Scope is the nearest PRECEDING
  // #convert by line number: the apply belongs to that block, so it fires only
  // when that #convert's From type is this block's class. An #apply with no
  // preceding #convert at all is file-scope and applies to every block.
  // Bare-tail compare, for the same reason the #convert gate uses it: a rule may
  // write 'LibA.TSrcBtn' while the .dfm class token is always bare.
  function ApplyInScope(const AApply: TConversionRule): Boolean;
  var
    Q       : TConversionRule;
    BestLine: Integer        ;
    BestFrom: string         ;
  begin
    BestLine:= -1;
    BestFrom:= '';
    for Q in ARules.Rules do
      if (Q.Kind = rkConvert) and (Q.LineNo <= AApply.LineNo) and (Q.LineNo > BestLine) then
      begin
        BestLine:= Q.LineNo;
        BestFrom:= Q.FromType;
      end;
    if BestLine < 0 then Exit(True); { file-scope }
    Result:= SameText(BareTypeTail(BestFrom), FRoot.ClassName_);
  end;

  // Write one branch's assignments into the T tree. '???' is the scaffolder's
  // explicit-unfilled stub and is skipped here exactly as #default skips it.
  procedure ApplySets(const ASets: TArray<TMappingSetPair>);
  var SP: TMappingSetPair;
  begin
    for SP in ASets do
    begin
      if (SP.ToPath = '') or (Trim(SP.ToPath) = '???') then Continue;
      PlaceAtPath(TRoot, SP.ToPath, SP.Value, dnkScalar, Created);
    end;
  end;

  // Evaluate one applied mapping against this block.
  procedure EvaluateMapping(const AApply: TConversionRule);
  var
    Q       : TConversionRule ;
    ElseRule: TConversionRule ;
    SrcPath : string          ;
    LeafVal : string          ;
    Matched : Boolean         ;
    HaveElse: Boolean         ;
    NA      : TReemitNotApplied;
  begin
    SrcPath := '';
    Matched := False;
    HaveElse:= False;
    ElseRule:= Default(TConversionRule);

    { FIRST #when WINS -- branches are evaluated in source order and the search
      stops at the first match, so an author can order specific before general. }
    for Q in ARules.Rules do
    begin
      if (Q.Kind <> rkMapping) or (not SameText(Q.MapName, AApply.MapName)) then Continue;
      if Q.IsElse then
      begin
        ElseRule:= Q;
        HaveElse:= True;
        Continue;
      end;
      if Q.WhenFrom = '' then Continue; { the declaration line carries no condition }
      if SrcPath = '' then SrcPath:= Q.WhenFrom;
      if Matched then Continue;
      if FindLeafValue(Q.WhenFrom, LeafVal) and
         SameText(Trim(LeafVal), Trim(Q.WhenValue)) then
      begin
        ApplySets(Q.Sets);
        ConsumedPaths:= ConsumedPaths + [Q.WhenFrom];
        Matched:= True;
      end;
    end;
    if Matched then Exit;

    { A declaration-only mapping (no #when at all) has no source path, so there
      is nothing to evaluate and nothing to report. }
    if SrcPath = '' then Exit;

    if not FindLeafValue(SrcPath, LeafVal) then
    begin
      { ABSENT source: nothing to map. Informational, NOT remainder -- and the
        reason #else is gated on presence: firing #else here would invent a T
        value from an F property the form never set. }
      Result.Report.MappingNotes:= Result.Report.MappingNotes +
        [Format('mapping %s: source path %s is not present in this block -- nothing to map',
          [AApply.MapName, SrcPath])];
      Exit;
    end;

    if HaveElse and (Length(ElseRule.Sets) > 0) then
    begin
      ApplySets(ElseRule.Sets);
      ConsumedPaths:= ConsumedPaths + [SrcPath];
      Exit;
    end;

    { Present, unmatched, no #else -- REMAINDER. The value is still in the F DFM
      and the operator asked for it to be mapped. }
    NA.MapName := AApply.MapName;
    NA.RuleLine:= AApply.LineNo;
    NA.Path    := SrcPath;
    NA.Value   := LeafVal;
    Result.Report.NotApplied:= Result.Report.NotApplied + [NA];
  end;

  procedure ApplyMappings;
  var Q: TConversionRule;
  begin
    for Q in ARules.Rules do
      if (Q.Kind = rkApply) and (Q.MapName <> '') and ApplyInScope(Q) then
        EvaluateMapping(Q);
  end;

  procedure RemapLeaf(const ALeaf: TDfmNode; const AFromPath: string);
  var ToPath: string;
  begin
    if IsRemoved(AFromPath) then Exit; // #remove: ensure absent from T
    if IsConsumed(AFromPath) then Exit; // a #mapping already wrote the T side
    if IsIgnored(AFromPath) then
    begin Ignored:= Ignored + [AFromPath]; Exit; end;
    if FindLinkFor(AFromPath, ToPath) then
    begin
      if Trim(ToPath) = '???' then
      begin Result.Report.Stubs:= Result.Report.Stubs + [Format('unfilled ToPath (???) for %s', [AFromPath])]; Exit; end;
      if ALeaf.Kind = dnkCollection then
      begin
        // Collection relocate-keep-items: move the whole collection verbatim.
        PlaceAtPath(TRoot, ToPath, ALeaf.ValueText, dnkCollection, Created);
        Result.Report.Relocated:= Result.Report.Relocated +
          [Format('collection %s relocated to %s, items unchanged', [AFromPath, ToPath])];
        Exit;
      end;
      if ALeaf.Kind = dnkBinary then
      begin
        // Copy a binary/complex value only when F and T leaf types resolve to the
        // same type; else WARN and do not copy (cross-type conversion is the
        // interpreter stage, deferred past 2a).
        var FType: string; var TType: string;
        FType:= LeafTypeOf(AFromTree, AFromPath);
        TType:= LeafTypeOf(AToTree, ToPath);
        if (FType <> '') and (TType <> '') and (not SameText(FType, TType)) then
        begin
          Result.Report.Mismatched:= Result.Report.Mismatched +
            [Format('%s: F type %s != T type %s (binary not copied)', [AFromPath, FType, TType])];
          Exit;
        end;
        PlaceAtPath(TRoot, ToPath, ALeaf.ValueText, dnkBinary, Created);
        Exit;
      end;
      PlaceAtPath(TRoot, ToPath, ALeaf.ValueText, ALeaf.Kind, Created);
      Exit;
    end;
    // UNMAPPED + present in the DFM == non-default -> genuine potential loss.
    Dropped:= Dropped + [AFromPath];
  end;

  // Recurse into a moved-depth F sub-object's children (see HandleNested),
  // remapping each leaf by its dotted 'APrefix.LeafName' rule-lookup path. A
  // further-nested dnkSubObject child recurses again (prefix extended one more
  // level), so multi-level F nesting composes without a depth limit here (the
  // #convert-guarded recursion in HandleNested has its own natural base case).
  procedure RemapUnderPrefix(const ASub: TDfmNode; const APrefix: string);
  var
    Child: TDfmNode;
  begin
    for Child in ASub.Children do
      if Child.Kind = dnkSubObject then
        RemapUnderPrefix(Child, APrefix + '.' + Child.Name)
      else
        RemapLeaf(Child, APrefix + '.' + Child.Name);
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
    else if HasDeepRuleUnder(ASub.Name) then
    begin
      // MOVED-DEPTH: this F sub-object has no #convert of its own, but one or
      // more of its children are individually redirected by a dotted #link
      // (e.g. 'Style.Active.Font.Size <- Font.Size'). The sub-object itself is
      // NOT copied -- only its remapped children land in T, at whatever T paths
      // their rules name (PlaceAtPath creates the intermediate T sub-objects).
      RemapUnderPrefix(ASub, ASub.Name);
    end
    else
    begin
      // No #convert and no deep rule for this nested class -> ordinary contained
      // child OR unconverted owned part. 2a-i heuristic: copy verbatim; flag in
      // OwnedParts only when a `#note owned:<Class>` marker explicitly declares
      // it an owned part.
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

  // 1. Parse the F block FIRST (moved ahead of the #convert gate below): the gate
  // needs FRoot.ClassName_ to pick the RIGHT #convert when the rule set holds more
  // than one (an owned-part recursion -- see HandleNested -- passes the FULL
  // parent rule set back into this same function for the part's own block).
  if not ParseDfmBlock(AFromBlock, FRoot) then
  begin
    Result.Ok:= False;
    Result.Error:= 'could not parse the F DFM object block';
    Exit;
  end;

  try
    // 2. Require a #convert header. Prefer the #convert whose FromType matches
    // THIS block's root class (so an owned-part recursion with its own #convert
    // picks its OWN target, not the first/parent one); fall back to the first
    // #convert when none matches by name (single-pair rule sets, unchanged
    // behavior). FRoot is freed by the `finally` below on every exit path from
    // here on, including the no-#convert-after-parse early return.
    // Bug 1: R.FromType may be qualified ('LibA.TSrcBtn') while FRoot.ClassName_
    // (the .dfm's own class token) is always bare -- compare by bare tail (see
    // BareTypeTail) so a qualified #convert header still matches THIS block's
    // root class instead of silently falling through to the "first #convert"
    // fallback below.
    HaveConvert:= False; ToType:= '';
    for R in ARules.Rules do
      if (R.Kind = rkConvert) and SameText(BareTypeTail(R.FromType), FRoot.ClassName_) then
      begin HaveConvert:= True; ToType:= R.ToType; Break; end;
    if not HaveConvert then
      for R in ARules.Rules do
        if R.Kind = rkConvert then
        begin HaveConvert:= True; ToType:= R.ToType; Break; end;
    if not HaveConvert then
    begin
      Result.Ok:= False;
      Result.Error:= 'no #convert F -> T header in the rule set';
      Exit;
    end;

    // 3. Build the T root: same instance Name, swapped class. ToType may be
    // qualified (R.ToType written as 'LibB.TDstBtn') but a .dfm object header
    // is always bare -- BareTypeTail so the emitted 'object Name: Class' line
    // stays well-formed/consistent regardless of the rule header's spelling
    // (Bug 1).
    TRoot:= TDfmNode.Create;
    TRoot.Kind      := dnkSubObject;
    TRoot.Name      := FRoot.Name;
    TRoot.ClassName_:= BareTypeTail(ToType);

    // 3b. Apply #mapping/#apply BEFORE the leaf loop. Order is load-bearing:
    // RemapLeaf below would already have recorded a mapped source leaf as
    // Dropped, and a leaf cannot be un-dropped. Running first also lets
    // RemapLeaf skip whatever a mapping consumed (IsConsumed).
    ApplyMappings;

    // 4. Per top-level F leaf, remap. Nested sub-objects are classified as an
    // owned part (recurse via #convert) or a contained child (copied verbatim).
    for i:= 0 to FRoot.Children.Count - 1 do
    begin
      Leaf:= FRoot.Children[i];
      if Leaf.Kind = dnkSubObject then HandleNested(Leaf)
      else RemapLeaf(Leaf, Leaf.Name);
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
