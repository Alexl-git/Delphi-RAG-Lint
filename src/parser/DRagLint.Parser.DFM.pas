unit DRagLint.Parser.DFM;

interface

uses
  System.SysUtils
  , System.Classes
  , System.Generics.Collections
  , TreeSitter
  , TreeSitterLib
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.IndexDictionary (DRagLint.CLI.pas), DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas)</para>
  /// <para>Used in units: DRagLint.CLI</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDFMParser = class(TInterfacedObject, IParser)
    strict private
      FLanguage: PTSLanguage;
    public
      /// <summary><!-- drag-lint:auto -->TDFMParser</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas), DRagLint.CLI.IndexDictionary (DRagLint.CLI.pas)</para>
      /// <para>constructor</para>
      /// <para>Writes: FLanguage</para>
      /// <seealso cref="DRagLint.Parser.DFM.TDFMParser.FileExtensions"/>
      /// <seealso cref="DRagLint.Parser.DFM.TDFMParser.LanguageName"/>
      /// <seealso cref="DRagLint.Parser.DFM.TDFMParser.Parse"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create;
      /// <returns><!-- drag-lint:auto -->string -- Observed: 'dfm'.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Implements: DRagLint.Core.Interfaces.IParser.LanguageName</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Parser.DFM.TDFMParser.Create"/>
      /// <seealso cref="DRagLint.Parser.DFM.TDFMParser.FileExtensions"/>
      /// <seealso cref="DRagLint.Parser.DFM.TDFMParser.Parse"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function LanguageName: string                                               ;
      /// <returns><!-- drag-lint:auto -->TArray&lt;string&gt; -- Observed: ['.dfm'].</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Implements: DRagLint.Core.Interfaces.IParser.FileExtensions</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Parser.DFM.TDFMParser.Create"/>
      /// <seealso cref="DRagLint.Parser.DFM.TDFMParser.LanguageName"/>
      /// <seealso cref="DRagLint.Parser.DFM.TDFMParser.Parse"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function FileExtensions: TArray<string>                                     ;
      /// <param name="ASource"><!-- drag-lint:auto type -->const TBytes</param>
      /// <param name="AFilePath"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto type -->TParseResult</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: Default, DRagLint.Parser.DFM.CollectParseErrors, DRagLint.Parser.DFM.TDfmState.Create, DRagLint.Parser.DFM.WalkObject, Integer, Move, TreeSitter.TTSParser.Create, TreeSitter.TTSParser.Parse</para>
      /// <para>Implements: DRagLint.Core.Interfaces.IParser.Parse</para>
      /// <para>Reads: FLanguage</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Parser.DFM.CollectParseErrors"/>
      /// <seealso cref="DRagLint.Parser.DFM.TDfmState.Create"/>
      /// <seealso cref="DRagLint.Parser.DFM.WalkObject"/>
      /// <seealso cref="TreeSitter.TTSParser.Create"/>
      /// <seealso cref="TreeSitter.TTSParser.Parse"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function Parse(const ASource: TBytes; const AFilePath: string): TParseResult;
  end;

  /// <summary>One DFM event-handler wiring: the object named ObjectName has
  /// its EventProp event property (e.g. 'OnClick') bound to the method named
  /// HandlerName -- e.g. `object Button1: TButton ... OnClick = Button1Click`
  /// yields (ObjectName='Button1', EventProp='OnClick',
  /// HandlerName='Button1Click'). Produced by ExtractDfmEventBindings.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Doc.SymbolFacts.DfmEventMapFor (DRagLint.Doc.SymbolFacts.pas), DRagLint.Parser.DFM.TDfmState.Create (DRagLint.Parser.DFM.pas), DRagLint.Parser.DFM.WalkProperty (DRagLint.Parser.DFM.pas)</para>
  /// <para>Used in units: DRagLint.Doc.SymbolFacts, DRagLint.Parser.DFM</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDfmEventBinding = record
    ObjectName : string;
    EventProp  : string;
    HandlerName: string;
  end;

function tree_sitter_dfm: PTSLanguage; cdecl;
external 'tree-sitter-dfm';

/// <summary>Extracts every (object, event-property, handler) triple from a
/// text DFM source -- e.g. `object Button1: TButton ... OnClick =
/// Button1Click end` yields (ObjectName='Button1', EventProp='OnClick',
/// HandlerName='Button1Click'). Reuses the SAME tree-sitter-dfm grammar walk
/// TDFMParser.Parse uses (WalkObject/WalkProperty), which now also threads
/// the enclosing object's own name down to the property scan; TDFMParser.
/// Parse itself is UNCHANGED (its TParseResult never surfaced this triple,
/// only the bare handler name via the 'event-binding' reference kind, which
/// is not enough to render 'Button1.OnClick' -- see DRagLint.Doc.SymbolFacts'
/// DFM event-wiring fact for why a second, focused extractor is needed).</summary>
/// <param name="ASource">Raw DFM file bytes, as read from disk. Callers that
/// need ANSI/UTF-16 transcoding (e.g. a caption with non-ASCII text) must do
/// it themselves before calling, exactly as TDFMParser.Parse's own callers
/// do -- this function does not transcode, and always checks the FIRST BYTE
/// of exactly what it is given for the binary-DFM guard below.</param>
/// <returns>One TDfmEventBinding per On*-property bound to a bare
/// method-name identifier, in document order. Empty for a binary DFM (first
/// byte $FF -- the text-DFM grammar cannot parse it; mirrors TDFMParser.
/// Parse's own guard) or a DFM with no event bindings at all.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Doc.SymbolFacts.DfmEventMapFor (DRagLint.Doc.SymbolFacts.pas)</para>
/// <para>Calls: DRagLint.Parser.DFM.TDfmState.Create, DRagLint.Parser.DFM.WalkObject, Integer, Move, TreeSitter.TTSParser.Create, TreeSitter.TTSParser.Parse</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Parser.DFM.TDfmState.Create"/>
/// <seealso cref="DRagLint.Parser.DFM.WalkObject"/>
/// <seealso cref="TreeSitter.TTSParser.Create"/>
/// <seealso cref="TreeSitter.TTSParser.Parse"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ExtractDfmEventBindings(const ASource: TBytes): TArray<TDfmEventBinding>;

implementation

function NodeText(const ANode: TTSNode; const ASource: TBytes): string;
var
  StartIdx: Integer;
  EndIdx  : Integer;
  Len     : Integer;
begin
  Result:= '';
  if ANode.IsNull then Exit;
  StartIdx:= Integer(ANode.StartByte);
  EndIdx  := Integer(ANode.EndByte  );
  Len:= EndIdx - StartIdx;
  if (Len <= 0) or (StartIdx < 0) or (EndIdx > Length(ASource)) then Exit;
  Result:= TEncoding.UTF8.GetString(ASource, StartIdx, Len);
end;

type
  TDfmState = class
    Source       : TBytes                    ;
    Symbols      : TList<TSymbol>            ;
    References   : TList<TReference>         ;
    Literals     : TList<TStringLiteral>     ;
    // ADP2 T6: (object, event-property, handler) triples collected by
    // WalkProperty's existing event-binding detection, alongside (not
    // instead of) the 'event-binding' Reference it already emits -- see
    // ExtractDfmEventBindings' header comment. Always collected (even by
    // the ordinary TDFMParser.Parse path, which does not read this field) --
    // mirrors Literals' own always-collect discipline; the cost of a few
    // TList.Add calls per DFM is negligible.
    EventBindings: TList<TDfmEventBinding>   ;
    constructor Create(const ASource: TBytes);
    destructor Destroy; override;
    function Emit(AKind: TSymbolKind; const AName, AQualifiedName, ASignature: string; AParentSymbolIdx: Integer; const ARangeNode: TTSNode): Integer;
    procedure EmitRef(const AKind, ANameText: string; const ARangeNode: TTSNode);
  end;

constructor TDfmState.Create(const ASource: TBytes);
begin
  inherited Create;
  Source:= ASource;
  Symbols      := TList<TSymbol         >.Create;
  References   := TList<TReference      >.Create;
  Literals     := TList<TStringLiteral  >.Create;
  EventBindings:= TList<TDfmEventBinding>.Create;
end;

destructor TDfmState.Destroy;
begin
  Symbols.Free;
  References.Free;
  Literals.Free;
  EventBindings.Free;
  inherited;
end;

function TDfmState.Emit(AKind: TSymbolKind; const AName, AQualifiedName, ASignature: string; AParentSymbolIdx: Integer; const ARangeNode: TTSNode): Integer;
var
  Sym: TSymbol;
begin
  Sym:= Default(TSymbol);
  Sym.Kind         := AKind;
  Sym.Name         := AName;
  Sym.QualifiedName:= AQualifiedName;
  Sym.Signature    := ASignature;
  if AParentSymbolIdx >= 0 then Sym.ParentId:= AParentSymbolIdx
  else Sym.ParentId:= -1;
  if not ARangeNode.IsNull then
  begin
    Sym.StartLine:= Integer(ARangeNode.StartPoint.row   ) + 1;
    Sym.StartCol := Integer(ARangeNode.StartPoint.column) + 1;
    Sym.EndLine  := Integer(ARangeNode.EndPoint  .row   ) + 1;
    Sym.EndCol   := Integer(ARangeNode.EndPoint  .column) + 1;
  end;
  Symbols.Add(Sym);
  Result:= Symbols.Count - 1;
end; // function

procedure TDfmState.EmitRef(const AKind, ANameText: string; const ARangeNode: TTSNode);
var
  Ref: TReference;
begin
  if ARangeNode.IsNull or (ANameText = '') then Exit;
  Ref:= Default(TReference);
  Ref.Kind    := AKind;
  Ref.NameText:= ANameText;
  Ref.SymbolId:= 0;
  Ref.StartLine:= Integer(ARangeNode.StartPoint.row   ) + 1;
  Ref.StartCol := Integer(ARangeNode.StartPoint.column) + 1;
  Ref.EndLine  := Integer(ARangeNode.EndPoint  .row   ) + 1;
  Ref.EndCol   := Integer(ARangeNode.EndPoint  .column) + 1;
  References.Add(Ref);
end;

procedure WalkObject(const ANode: TTSNode; const AState: TDfmState; AParentSymbolIdx: Integer; const AParentQualifiedName: string; AIsRoot: Boolean); forward;

/// <summary>Decodes a DFM `string` value node to its logical text: joins
/// quoted_string atoms (unescaping '' -> '), and renders char_code (#nn)
/// atoms as a single space (search-friendly).</summary>
function DfmDecodeString(const ANode: TTSNode; const ASource: TBytes): string;
var
  i   : Integer;
  Atom: TTSNode;
  Raw : string ;
begin
  Result:= '';
  for i:= 0 to ANode.NamedChildCount - 1 do
  begin
    Atom:= ANode.NamedChild(i);
    if Atom.NodeType = 'quoted_string' then
    begin
      Raw:= NodeText(Atom, ASource);
      if (Length(Raw) >= 2) and (Raw[1] = '''') and (Raw[Length(Raw)] = '''') then
        Raw:= Copy(Raw, 2, Length(Raw) - 2);
      Result:= Result + StringReplace(Raw, '''''', '''', [rfReplaceAll]);
    end
    else if Atom.NodeType = 'char_code' then
      Result:= Result + ' ';
  end;
end;

procedure WalkProperty(const ANode: TTSNode; const AState: TDfmState; const AObjectName: string);
var
  NameNode   : TTSNode;
  ValueNode  : TTSNode;
  NameInner  : TTSNode;
  PropName   : string ;
  HandlerName: string ;
  i          : Integer;
begin
  NameNode := ANode.ChildByField('name' );
  ValueNode:= ANode.ChildByField('value');
  if NameNode.IsNull then Exit;
  // qualified_identifier wraps an identifier (or chain). Take whole text.
  PropName:= NodeText(NameNode, AState.Source);
  if PropName = '' then Exit;
  // Event bindings: property names starting with "On" whose value is an
  // identifier_value (a method name).
  if not ValueNode.IsNull and (Copy(PropName, 1, 2) = 'On') and (ValueNode.NodeType = 'identifier_value') then
  begin
    HandlerName:= '';
    for i:= 0 to ValueNode.NamedChildCount - 1 do
    begin
      NameInner:= ValueNode.NamedChild(i);
      if NameInner.NodeType = 'qualified_identifier' then
      begin
        HandlerName:= NodeText(NameInner, AState.Source);
        Break;
      end;
    end;
    if HandlerName <> '' then
    begin
      AState.EmitRef('event-binding', HandlerName, ValueNode);
      // ADP2 T6: also record the full (object, event-property, handler)
      // triple -- the EmitRef call above stores ONLY the handler name (the
      // pre-existing 'event-binding' reference, kept as-is for its existing
      // consumers, e.g. FindEventHandlersForForm/DRagLint.Wiring), which
      // cannot answer "which control/property is THIS handler wired to".
      // See ExtractDfmEventBindings' header comment.
      var EB: TDfmEventBinding;
      EB.ObjectName := AObjectName;
      EB.EventProp  := PropName;
      EB.HandlerName:= HandlerName;
      AState.EventBindings.Add(EB);
    end;
  end;
  // v10: harvest string property text for the text index.
  if (not ValueNode.IsNull) and (ValueNode.NodeType = 'string') then
  begin
    var Lit: TStringLiteral; Lit:= Default(TStringLiteral);
    Lit.Source   := 'dfm';
    Lit.Kind     := 'dfm-prop';
    Lit.OwnerName:= PropName;
    Lit.Text     := DfmDecodeString(ValueNode, AState.Source);
    if Lit.Text <> '' then
    begin
      Lit.StartLine:= Integer(ValueNode.StartPoint.row   ) + 1;
      Lit.StartCol := Integer(ValueNode.StartPoint.column) + 1;
      Lit.EndLine  := Integer(ValueNode.EndPoint  .row   ) + 1;
      Lit.EndCol   := Integer(ValueNode.EndPoint  .column) + 1;
      AState.Literals.Add(Lit);
    end;
  end;
end; // procedure

procedure WalkObject(const ANode: TTSNode; const AState: TDfmState; AParentSymbolIdx: Integer; const AParentQualifiedName: string; AIsRoot: Boolean);
var
  NameNode : TTSNode    ;
  ClassNode: TTSNode    ;
  ChildNode: TTSNode    ;
  ObjName  : string     ;
  ObjClass : string     ;
  QName    : string     ;
  Signature: string     ;
  Kind     : TSymbolKind;
  Idx      : Integer    ;
  i        : Integer    ;
begin
  NameNode := ANode.ChildByField('name' );
  ClassNode:= ANode.ChildByField('class');
  if NameNode.IsNull then Exit;
  ObjName:= NodeText(NameNode, AState.Source);
  if ObjName = '' then Exit;
  ObjClass:= '';
  if not ClassNode.IsNull then ObjClass:= NodeText(ClassNode, AState.Source);
  if AParentQualifiedName <> '' then QName:= AParentQualifiedName + '.' + ObjName
  else QName:= ObjName;
  Signature:= ObjClass;
  if AIsRoot then Kind:= skForm
  else Kind:= skComponent;
  Idx:= AState.Emit(Kind, ObjName, QName, Signature, AParentSymbolIdx, ANode);
  for i:= 0 to ANode.NamedChildCount - 1 do
  begin
    ChildNode:= ANode.NamedChild(i);
    if ChildNode.NodeType      = 'object' then WalkObject(ChildNode, AState, Idx, QName, False)
    else if ChildNode.NodeType = 'property' then WalkProperty(ChildNode, AState, ObjName);
  end;
end; // procedure

function ExtractDfmEventBindings(const ASource: TBytes): TArray<TDfmEventBinding>;
var
  Parser: TTSParser;
  Tree  : TTSTree  ;
  State : TDfmState;
  Root  : TTSNode  ;
  Child : TTSNode  ;
  i     : Integer  ;
begin
  Result:= nil;
  { Binary DFM files start with $FF; the text-DFM grammar cannot handle them --
    mirrors TDFMParser.Parse's own guard (see that function's comment). Checked
    on ASource exactly as given (no transcoding here -- see this function's
    <param> comment), so a genuine binary DFM is never misread as text. }
  if (Length(ASource) > 0) and (ASource[0] = $FF) then Exit;

  Parser:= TTSParser.Create;
  try
    Parser.Language:= tree_sitter_dfm;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      var Remaining: Integer;
      begin
        Remaining:= Length(ASource) - Integer(AByteIndex);
        if Remaining <= 0 then
        begin
          ABytesRead:= 0;
          SetLength(Result, 0);
          Exit;
        end;
        SetLength(Result, Remaining);
        Move(ASource[AByteIndex], Result[0], Remaining);
        ABytesRead:= Remaining;
      end, TTSInputEncoding.TSInputEncodingUTF8);
    try
      State:= TDfmState.Create(ASource);
      try
        Root:= Tree.RootNode;
        for i:= 0 to Root.NamedChildCount - 1 do
        begin
          Child:= Root.NamedChild(i);
          if Child.NodeType = 'object' then WalkObject(Child, State, -1, '', True);
        end;
        Result:= State.EventBindings.ToArray;
      finally
        State.Free;
      end;
    finally
      Tree.Free;
    end;
  finally
    Parser.Free;
  end;
end; // function

/// <summary>Walks the parse tree collecting ERROR/MISSING node positions into ADiags (max AMaxErrors).</summary>
/// <remarks>Only recurses into subtrees where HasError is set; exits early once the cap is reached.</remarks>
procedure CollectParseErrors(const ARoot: TTSNode; const AFilePath: string; var ADiags: TArray<string>; AMaxErrors, ADepth: Integer);
var
  ChildIdx: Integer;
  Child   : TTSNode;
  Pt      : TTSPoint;
begin
  if ARoot.IsNull then Exit;
  if ADepth > 30 then Exit;
  if Length(ADiags) >= AMaxErrors then Exit;
  if ARoot.IsError or ARoot.IsMissing then
  begin
    Pt:= ARoot.StartPoint;
    ADiags:= ADiags + [Format('%s(%d,%d): parse error [%s]', [AFilePath, Integer(Pt.row) + 1, Integer(Pt.column) + 1, ARoot.NodeType])];
    Exit; { don't descend into ERROR node's children - they are noise }
  end;
  if ARoot.HasError then
    for ChildIdx:= 0 to ARoot.ChildCount - 1 do
    begin
      if Length(ADiags) >= AMaxErrors then Break;
      Child:= ARoot.Child(ChildIdx);
      CollectParseErrors(Child, AFilePath, ADiags, AMaxErrors, ADepth + 1);
    end;
end;

{ TDFMParser }

constructor TDFMParser.Create;
begin
  inherited Create;
  FLanguage:= tree_sitter_dfm;
end;

function TDFMParser.LanguageName: string;
begin
  Result:= 'dfm';
end;

function TDFMParser.FileExtensions: TArray<string>;
begin
  Result:= ['.dfm'];
end;

function TDFMParser.Parse(const ASource: TBytes; const AFilePath: string): TParseResult;
var
  Parser: TTSParser;
  Tree  : TTSTree  ;
  Source: TBytes   ;
  State : TDfmState;
  Root  : TTSNode  ;
  Child : TTSNode  ;
  i     : Integer  ;
begin
  Result:= Default(TParseResult);
  { Binary DFM files start with $FF; the text-DFM parser cannot handle them. }
  if (Length(ASource) > 0) and (ASource[0] = $FF) then
  begin
    Result.Diagnostics:= [AFilePath + ': binary DFM (TPF0) -- save as Text DFM in the IDE to index this file'];
    Exit;
  end;
  Source:= ASource;
  Tree  := nil;
  Parser:= nil;
  State := nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= FLanguage;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes var Remaining: Integer; begin Remaining:= Length(Source)
        - Integer(AByteIndex); if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end; SetLength(Result, Remaining); Move(Source[AByteIndex], Result[0],
          Remaining); ABytesRead:= Remaining; end, TTSInputEncoding.TSInputEncodingUTF8);

    State:= TDfmState.Create(Source);
    Root:= Tree.RootNode;
    if Root.HasError then CollectParseErrors(Root, AFilePath, Result.Diagnostics, 10, 0);
    // source_file -> [object ...]. Top-level objects are forms.
    for i:= 0 to Root.NamedChildCount - 1 do
    begin
      Child:= Root.NamedChild(i);
      if Child.NodeType = 'object' then WalkObject(Child, State, -1, '', True);
    end;
    Result.Symbols   := State.Symbols   .ToArray;
    Result.References:= State.References.ToArray;
    Result.Literals  := State.Literals  .ToArray;
  finally
    State.Free;
    Tree.Free;
    Parser.Free;
  end; // try
end; // function

end.
