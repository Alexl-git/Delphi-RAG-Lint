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

function ParseDfmBlock(const ABlockText: string; out ARoot: TDfmNode): Boolean;
begin
  ARoot := nil;
  Result:= False; // implemented in Task 3
end;

function ReemitComponent(const AFromBlock: string; const ARules: TConversionRuleSet;
  const AFromTree, AToTree: TPropTree): TReemitResult;
begin
  Result:= Default(TReemitResult);
  Result.Ok   := False;
  Result.Error:= 'not implemented'; // implemented in Tasks 4-7
end;

end.
