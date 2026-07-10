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
  /// for dnkSubObject/dnkCollection nodes. Children are owned (freed with this
  /// node). A scalar/event has no children; a sub-object's children are its
  /// properties + nested objects; a collection's children are `item` pseudo-nodes
  /// (each an unnamed dnkSubObject whose children are the item's properties).</remarks>
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

function ReemitComponent(const AFromBlock: string; const ARules: TConversionRuleSet;
  const AFromTree, AToTree: TPropTree): TReemitResult;
begin
  Result:= Default(TReemitResult);
  Result.Ok   := False;
  Result.Error:= 'not implemented'; // implemented in Tasks 4-7
end;

end.
