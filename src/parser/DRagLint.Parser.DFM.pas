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
  /// <para>Used by: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas), DRagLint.CLI.IndexDictionary (DRagLint.CLI.pas), DRagLint.Convert.UsesReconcile.ReindexText (DRagLint.Convert.UsesReconcile.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Convert.UsesReconcile</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDFMParser = class(TInterfacedObject, IParser)
    strict private
      FLanguage: PTSLanguage;
    public
      /// <summary><!-- drag-lint:auto sum -->TDFMParser</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas), DRagLint.CLI.IndexDictionary (DRagLint.CLI.pas), DRagLint.Convert.UsesReconcile.ReindexText (DRagLint.Convert.UsesReconcile.pas)</para>
      /// <para>Calls: DRagLint.Parser.DFM.tree_sitter_dfm</para>
      /// <para>constructor</para>
      /// <para>Writes: FLanguage</para>
      /// <seealso cref="DRagLint.Parser.DFM.tree_sitter_dfm"/>
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
      /// <summary>Extracts the form / component symbols, event-binding references
      /// and dfm-prop / dfm-type literals of ONE text .dfm with tree-sitter-dfm.</summary>
      /// <param name="ASource">The .dfm bytes as UTF-8 WITHOUT a BOM, or the RAW bytes
      /// of a binary (TPF0 / FF 0A 00) .dfm. The caller transcodes: TIndexer.IndexFileBody
      /// runs EnsureUtf8Bytes (UTF-8 BOM stripped, UTF-16 BOM and BOM-less ANSI =
      /// Windows-1252 re-encoded) before this call, so a Windows-1252 `object
      /// btn&#xDC;ber: TButton` reaches the grammar as valid UTF-8 and the
      /// identifier rule (tree-sitter-dfm 1.2.0: Unicode letters, wave 149 DF) keeps the
      /// WHOLE name. Up to 1.48 the grammar was ASCII-only and the symbol was stored as
      /// its ASCII prefix (`btn`); invalid UTF-8 handed in raw still truncates there,
      /// because tree-sitter decodes it as U+FFFD, not a letter.</param>
      /// <param name="AFilePath"><!-- drag-lint:auto type -->const string</param>
      /// <returns>Symbol names / qualified names / signatures are the identifier text
      /// decoded from the UTF-8 node span (NodeText); columns are UTF-8 BYTE columns.</returns>
      /// <exception cref="ETreeSitterException"><!-- drag-lint:auto exc -->via TreeSitter.TTSParser.SetLanguage: Failed to set parser language to 0x%p</exception>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: Default, DRagLint.Parser.DFM.CollectParseErrors, DRagLint.Parser.DFM.IsBinaryDfmBytes, DRagLint.Parser.DFM.ParseDfmSource, DRagLint.Parser.DFM.TDfmState.Create, DRagLint.Parser.DFM.WalkObject, DRagLint.Parser.DfmNav.DfmNavLinesFromBytes, DRagLint.Parser.DfmNav.ScanDfmNav, TreeSitter.TTSNodeHelper.HasError, TreeSitter.TTSNodeHelper.NamedChild, TreeSitter.TTSNodeHelper.NamedChildCount, TreeSitter.TTSNodeHelper.NodeType, TreeSitter.TTSParser.Create, TreeSitter.TTSParser.SetLanguage, TreeSitter.TTSTree.RootNode</para>
      /// <para>Returns: Default(TParseResult)</para>
      /// <para>Implements: DRagLint.Core.Interfaces.IParser.Parse</para>
      /// <para>Reads: FLanguage</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Parser.DFM.CollectParseErrors"/>
      /// <seealso cref="DRagLint.Parser.DFM.IsBinaryDfmBytes"/>
      /// <seealso cref="DRagLint.Parser.DFM.ParseDfmSource"/>
      /// <seealso cref="DRagLint.Parser.DFM.TDfmState.Create"/>
      /// <seealso cref="DRagLint.Parser.DFM.WalkObject"/>
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
  /// <para>Used by: declaration (DRagLint.Parser.DFM.pas), DRagLint.Doc.SymbolFacts.DfmEventMapFor (DRagLint.Doc.SymbolFacts.pas), DRagLint.Parser.DFM.ExtractDfmEventBindings (DRagLint.Parser.DFM.pas), DRagLint.Parser.DFM.TDfmState.Create (DRagLint.Parser.DFM.pas), DRagLint.Parser.DFM.WalkProperty (DRagLint.Parser.DFM.pas)</para>
  /// <para>Used in units: DRagLint.Doc.SymbolFacts, DRagLint.Parser.DFM</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDfmEventBinding = record
    ObjectName : string;
    EventProp  : string;
    HandlerName: string;
  end;

/// <returns><!-- drag-lint:auto type -->PTSLanguage</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Convert.DfmReemit.ParseDfmBlock (DRagLint.Convert.DfmReemit.pas), DRagLint.Parser.DFM.ExtractDfmEventBindings (DRagLint.Parser.DFM.pas), DRagLint.Parser.DFM.ExtractDfmPropertyRowsFromBytes (DRagLint.Parser.DFM.pas), DRagLint.Parser.DFM.TDFMParser.Create (DRagLint.Parser.DFM.pas)</para>
/// <para>Directives: cdecl; external</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function tree_sitter_dfm: PTSLanguage; cdecl;  // dl:ok method-pascalcase@78b2 -- DLL export name must match the tree-sitter-dfm C symbol
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
/// <param name="ASource">Raw DFM file bytes, as read from disk, in ANY encoding the
/// indexer accepts: UTF-8 (with or without BOM), UTF-16 (BOM) or BOM-less ANSI
/// (Windows-1252). The function transcodes to UTF-8 itself (EnsureUtf8Bytes, the
/// rule the indexer applies before TDFMParser.Parse), so a non-ASCII identifier in
/// a BOM-less ANSI .dfm is no longer truncated (150 DF2). Already-UTF-8 input is
/// an identity passthrough. The binary-DFM guard below checks the FIRST BYTE of
/// exactly what it is given, BEFORE any transcoding.</param>
/// <returns>One TDfmEventBinding per On*-property bound to a bare
/// method-name identifier, in document order. Empty for a binary DFM (first
/// byte $FF -- the text-DFM grammar cannot parse it; mirrors TDFMParser.
/// Parse's own guard) or a DFM with no event bindings at all.</returns>
/// <exception cref="ETreeSitterException"><!-- drag-lint:auto exc -->via TreeSitter.TTSParser.SetLanguage: Failed to set parser language to 0x%p</exception>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Doc.SymbolFacts.DfmEventMapFor (DRagLint.Doc.SymbolFacts.pas)</para>
/// <para>Calls: DRagLint.Core.Encoding.EnsureUtf8Bytes, DRagLint.Parser.DFM.IsBinaryDfmBytes, DRagLint.Parser.DFM.ParseDfmSource, DRagLint.Parser.DFM.TDfmState.Create, DRagLint.Parser.DFM.tree_sitter_dfm, DRagLint.Parser.DFM.WalkObject, TreeSitter.TTSNodeHelper.NamedChild, TreeSitter.TTSNodeHelper.NamedChildCount, TreeSitter.TTSNodeHelper.NodeType, TreeSitter.TTSParser.Create, TreeSitter.TTSParser.SetLanguage, TreeSitter.TTSTree.RootNode</para>
/// <para>Pure</para>
/// <para>Returns: nil; State.EventBindings.ToArray</para>
/// <seealso cref="DRagLint.Core.Encoding.EnsureUtf8Bytes"/>
/// <seealso cref="DRagLint.Parser.DFM.IsBinaryDfmBytes"/>
/// <seealso cref="DRagLint.Parser.DFM.ParseDfmSource"/>
/// <seealso cref="DRagLint.Parser.DFM.TDfmState.Create"/>
/// <seealso cref="DRagLint.Parser.DFM.tree_sitter_dfm"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ExtractDfmEventBindings(const ASource: TBytes): TArray<TDfmEventBinding>;

/// <summary>151 Y2: every property assignment of ONE text .dfm as dfm_properties
/// rows, from the SAME tree-sitter-dfm walk (WalkObject / WalkProperty) that
/// writes dfm_objects, so TDfmPropertyRow.ObjectOrdinal is the index of the
/// owning block in TParseResult.DfmObjects of the same bytes.</summary>
/// <param name="ASource">The .dfm bytes in any encoding the indexer accepts
/// (UTF-8 with or without BOM, UTF-16 BOM, BOM-less Windows-1252); transcoded with
/// EnsureUtf8Bytes exactly as ExtractDfmEventBindings does, so a CP1252 or
/// UTF-8-BOM caption decodes to the same Unicode text. Already-UTF-8 input (the
/// indexer's SourceText) is an identity passthrough.</param>
/// <returns>Rows in source order (array index = ordinal). Object-level
/// properties have Depth 0 and Parent -1. A collection (`&lt; item .. end &gt;`)
/// gets one row of kind 'collection', then per item one row named 'item' of kind
/// 'item' (range = the `item` keyword to its `end`), whose properties follow with
/// Parent = that item row. A list (`( .. )`) gets one row of kind 'list', then
/// one row per element (Name '', Parent = the list row). Depth = the length of
/// the Parent chain. ValueText: a string DECODED (doubled quotes, #nnn as the
/// character, '+' continuations joined); 'list', 'collection', 'item' and
/// 'binary' rows carry '' (their content is in the child rows, a blob is never
/// copied); any other kind its source text with CR LF / CR as #10. Positions are
/// 1-based, columns in UTF-8 bytes. Empty for a binary .dfm.</returns>
/// <exception cref="ETreeSitterException">via TreeSitter.TTSParser.SetLanguage when the grammar DLL cannot be bound.</exception>
/// <remarks>
/// Objects nested INSIDE a collection item are not dfm_objects rows
/// (WalkObject never descends into a property value) and get no rows. Pure; one
/// parse per call.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Parser.DFMProps.ExtractDfmPropertyRows (DRagLint.Parser.DFMProps.pas)</para>
/// <para>Calls: DRagLint.Core.Encoding.EnsureUtf8Bytes, DRagLint.Parser.DFM.IsBinaryDfmBytes, DRagLint.Parser.DFM.ParseDfmSource, DRagLint.Parser.DFM.TDfmState.Create, DRagLint.Parser.DFM.tree_sitter_dfm, DRagLint.Parser.DFM.WalkObject, TreeSitter.TTSNodeHelper.NamedChild, TreeSitter.TTSNodeHelper.NamedChildCount, TreeSitter.TTSNodeHelper.NodeType, TreeSitter.TTSParser.Create, TreeSitter.TTSParser.SetLanguage, TreeSitter.TTSTree.RootNode</para>
/// <para>Returns: nil; State.DfmProps.ToArray</para>
/// <seealso cref="DRagLint.Core.Encoding.EnsureUtf8Bytes"/>
/// <seealso cref="DRagLint.Parser.DFM.IsBinaryDfmBytes"/>
/// <seealso cref="DRagLint.Parser.DFM.ParseDfmSource"/>
/// <seealso cref="DRagLint.Parser.DFM.TDfmState.Create"/>
/// <seealso cref="DRagLint.Parser.DFM.tree_sitter_dfm"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ExtractDfmPropertyRowsFromBytes(const ASource: TBytes): TArray<TDfmPropertyRow>;

implementation

uses
  DRagLint.Core.Encoding { 150 DF2: EnsureUtf8Bytes in ExtractDfmEventBindings }
  , DRagLint.Parser.DfmNav { 150 Y2: ScanDfmNav in TDFMParser.Parse }
  ;

const
  MaxDfmLiteralText   = 256; { stored literal text cap (the property-value backstop in WalkProperty) }
  MaxParseErrorDepth  = 30;  { CollectParseErrors recursion cap }
  MaxParseDiagnostics = 10;  { diagnostics kept per file by TDFMParser.Parse }

{ v22: collapse every run of whitespace to ONE space and trim.
  A local copy rather than a use of the identically-named helper in
  DRagLint.Parser.Delphi13: that one is implementation-only, and widening a
  parser unit's interface to share a four-line string routine would couple the
  DFM extractor to the Delphi extractor for no benefit. A `set` value spans
  lines in real .dfm files -- `Anchors = [akLeft,\r\n    akTop]` -- so without
  this the stored text would carry the file's own line breaks and indentation
  into the FTS index and no phrase search would ever match it. }
function CollapseDfmWs(const ARaw: string): string;
var
  i   : Integer;
  Prev: Boolean;
  Sb  : TStringBuilder;
begin
  Sb:= TStringBuilder.Create;
  try
    Prev:= False;
    for i:= 1 to Length(ARaw) do
      if CharInSet(ARaw[i], [#9, #10, #13, ' ']) then
      begin
        if not Prev then Sb.Append(' ');
        Prev:= True;
      end
      else
      begin
        Sb.Append(ARaw[i]);
        Prev:= False;
      end;
    Result:= Trim(Sb.ToString);
  finally
    Sb.Free;
  end;
end;

{ True for a binary DFM: first byte $FF (resource header FF 0A 00), or a bare
  stream starting with the 4-byte signature 'TPF0'. A text DFM starts with
  object / inherited / inline, so neither can be misread. }
function IsBinaryDfmBytes(const ASource: TBytes): Boolean;
const
  Tpf0Sig: array[0..3] of Byte = ($54, $50, $46, $30);  { 'TPF0' }
  ResHdr1 = $FF;  { first byte of the FF 0A 00 resource header }
begin
  if Length(ASource) = 0 then Exit(False);
  if ASource[0] = ResHdr1 then Exit(True);
  Result:= (Length(ASource) >= Length(Tpf0Sig)) and CompareMem(@ASource[0], @Tpf0Sig[0], Length(Tpf0Sig));
end;

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
    // 149 EX2 (F5): one dfm_objects row per object block, source order.
    DfmObjects   : TList<TDfmObjectRow>      ;
    // 151 Y2: dfm_properties rows; nil (not collected) unless
    // ExtractDfmPropertyRowsFromBytes creates it, so TDFMParser.Parse costs nothing more.
    DfmProps     : TList<TDfmPropertyRow>    ;
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
  DfmObjects   := TList<TDfmObjectRow    >.Create;
end;

destructor TDfmState.Destroy;
begin
  Symbols.Free;
  References.Free;
  Literals.Free;
  EventBindings.Free;
  DfmObjects.Free;
  DfmProps.Free;
  inherited;  // dl:ok inherited-bare@246d -- destructor: the only ancestor is TObject
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
  Sym.ParentId:= if AParentSymbolIdx >= 0 then AParentSymbolIdx else -1;
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

{ 149 EX2 (F5): one dfm_objects row for the object block ANode. AName / AClass are
  the strings its symbol was emitted with (contract with lane DF); the parent's name
  is the last segment of AParentQName ('' for the root), the depth the number of
  segments above it. }
procedure EmitDfmObject(const AState: TDfmState; const ANode: TTSNode; const AName, AClass, AParentQName, AQName: string;
  ASymbolIdx: Integer);
var
  Row     : TDfmObjectRow;
  KindNode: TTSNode;
  K       : Integer;
begin
  Row:= Default(TDfmObjectRow);
  Row.Name      := AName;
  Row.ClassName := AClass;
  K:= LastDelimiter('.', AParentQName);
  Row.ParentName:= Copy(AParentQName, K + 1, MaxInt);
  Row.Depth     := 0;
  for K:= 1 to Length(AQName) do
    if AQName[K] = '.' then Inc(Row.Depth);
  KindNode:= ANode.ChildByField('kind');
  Row.ObjKind   := if KindNode.IsNull then 'object' else LowerCase(NodeText(KindNode, AState.Source));
  Row.SymbolIdx := ASymbolIdx;
  Row.StartLine := Integer(ANode.StartPoint.row   ) + 1;
  Row.StartCol  := Integer(ANode.StartPoint.column) + 1;
  Row.EndLine   := Integer(ANode.EndPoint  .row   ) + 1;
  Row.EndCol    := Integer(ANode.EndPoint  .column) + 1;
  AState.DfmObjects.Add(Row);
end;

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
      Result:= Result + StringReplace(Raw, '''''', '''', [rfReplaceAll]);  // dl:ok concat-in-loop@e758 -- one DFM string atom per iteration, a handful of short pieces, never a hot path
    end
    else if Atom.NodeType = 'char_code' then
      Result:= Result + ' ';  // dl:ok concat-in-loop@9c4f -- one char_code atom per iteration, same bounded loop
  end;
end;

const
  DfmBmpMax        = $FFFF;   { last code point that is one UTF-16 unit }
  DfmCodePointMax  = $10FFFF; { last Unicode code point }
  DfmSuppBase      = $10000;  { first supplementary code point }
  DfmHiSurrogate   = $D800;
  DfmLoSurrogate   = $DC00;
  DfmSurrogateBits = 10;
  DfmSurrogateMask = $3FF;

{ 151 Y2: TDfmPropertyRow.ValueKind of a value node. }
function DfmPropValueKind(const AValue: TTSNode): string;
var
  T: string;
begin
  if AValue.IsNull then Exit('other');
  T:= AValue.NodeType;
  if T = 'number' then
  begin
    if AValue.NamedChildCount > 0 then T:= AValue.NamedChild(0).NodeType;
    Exit(if (T = 'float') or (T = 'datetime_literal') then 'float' else 'integer');
  end;
  Result:= if T = 'string' then 'string'
           else if (T = 'boolean') or (T = 'identifier_value') then 'ident'
           else if T = 'set'         then 'set'
           else if T = 'list'        then 'list'
           else if T = 'items'       then 'collection'
           else if T = 'binary_blob' then 'binary'
           else 'other';
end;

{ 151 Y2: a DFM string value as the STORED value: quoted atoms unescaped
  ('' -> '), a #nnn atom as the character nnn (the IDE writes UTF-16 units; a
  value above $FFFF becomes a surrogate pair), '+' continuations joined. Unlike
  DfmDecodeString (the FTS literal, #nnn as a space). }
function DfmPropDecodeString(const ANode: TTSNode; const ASource: TBytes): string;
var
  i   : Integer;
  Atom: TTSNode;
  Raw : string ;
  Code: Integer;
  Sb  : TStringBuilder;
begin
  Sb:= TStringBuilder.Create;
  try
    for i:= 0 to ANode.NamedChildCount - 1 do
    begin
      Atom:= ANode.NamedChild(i);
      Raw := NodeText(Atom, ASource);
      if Atom.NodeType = 'quoted_string' then
      begin
        if (Length(Raw) >= 2) and (Raw[1] = '''') and (Raw[Length(Raw)] = '''') then Raw:= Copy(Raw, 2, Length(Raw) - 2);
        Sb.Append(StringReplace(Raw, '''''', '''', [rfReplaceAll]));
      end
      else if (Atom.NodeType = 'char_code') and TryStrToInt(Copy(Raw, 2, MaxInt), Code)
              and (Code >= 0) and (Code <= DfmCodePointMax) then
      begin
        if Code <= DfmBmpMax then Sb.Append(Char(Code))
        else
        begin
          Dec(Code, DfmSuppBase);
          Sb.Append(Char(DfmHiSurrogate + (Code shr DfmSurrogateBits)));
          Sb.Append(Char(DfmLoSurrogate + (Code and DfmSurrogateMask)));
        end;
      end;
    end;
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end;
end;

{ 151 Y2: a dfm_properties row without its position (AddDfmPropRow sets that). }
function DfmPropRow(AObjOrd, AParent, ADepth: Integer; const AName, AKind, AText: string): TDfmPropertyRow;
begin
  Result:= Default(TDfmPropertyRow);
  Result.ObjectOrdinal:= AObjOrd;
  Result.Parent       := AParent;
  Result.Depth        := ADepth;
  Result.Name         := AName;
  Result.ValueKind    := AKind;
  Result.ValueText    := AText;
end;

{ 151 Y2: appends ARow spanning AFirst's start to ALast's end; returns its index
  (= ordinal). }
function AddDfmPropRow(const AState: TDfmState; const AFirst, ALast: TTSNode; ARow: TDfmPropertyRow): Integer;
var
  Row: TDfmPropertyRow;
begin
  Row:= ARow;
  Row.StartLine    := Integer(AFirst.StartPoint.row   ) + 1;
  Row.StartCol     := Integer(AFirst.StartPoint.column) + 1;
  Row.EndLine      := Integer(ALast .EndPoint  .row   ) + 1;
  Row.EndCol       := Integer(ALast .EndPoint  .column) + 1;
  AState.DfmProps.Add(Row);
  Result:= AState.DfmProps.Count - 1;
end;

procedure EmitDfmPropValue(const AState: TDfmState; const ARange: TTSNode; const AName: string; const AValue: TTSNode;
  AObjOrd, AParent, ADepth: Integer); forward;

{ 151 Y2: the item rows of a collection value (`< item .. end item .. end >`). The
  grammar's _item is hidden, so an item is the span from its anonymous `item`
  token to its `end` token; its properties are the named children in between. }
procedure EmitDfmItems(const AState: TDfmState; const AItems: TTSNode; AObjOrd, AParent, ADepth: Integer);
var
  i       : Integer;
  ItemIdx : Integer;
  C       : TTSNode;
  NameNode: TTSNode;
  Row     : TDfmPropertyRow;
begin
  ItemIdx:= -1;
  for i:= 0 to AItems.ChildCount - 1 do
  begin
    C:= AItems.Child(i);
    if C.IsNamed then
    begin
      if (C.NodeType = 'property') and (ItemIdx >= 0) then
      begin
        NameNode:= C.ChildByField('name');
        if not NameNode.IsNull then
          EmitDfmPropValue(AState, C, NodeText(NameNode, AState.Source), C.ChildByField('value'), AObjOrd, ItemIdx, ADepth + 1);
      end;
    end
    else if SameText(C.NodeType, 'item') then
      ItemIdx:= AddDfmPropRow(AState, C, C, DfmPropRow(AObjOrd, AParent, ADepth, 'item', 'item', ''))
    else if SameText(C.NodeType, 'end') and (ItemIdx >= 0) then
    begin
      Row:= AState.DfmProps[ItemIdx];
      Row.EndLine:= Integer(C.EndPoint.row   ) + 1;
      Row.EndCol := Integer(C.EndPoint.column) + 1;
      AState.DfmProps[ItemIdx]:= Row;
      ItemIdx:= -1;
    end;
  end;
end;

{ 151 Y2: one row for the value AValue (a property when ARange is the property
  node, a list element when ARange = AValue), then its children: list elements
  (Name '') or collection items. Comments inside a list are not elements. }
procedure EmitDfmPropValue(const AState: TDfmState; const ARange: TTSNode; const AName: string; const AValue: TTSNode;
  AObjOrd, AParent, ADepth: Integer);
var
  Kind: string ;
  Txt : string ;
  Idx : Integer;
  i   : Integer;
  El  : TTSNode;
begin
  Kind:= DfmPropValueKind(AValue);
  Txt := if Kind = 'string' then DfmPropDecodeString(AValue, AState.Source)
         else if AValue.IsNull or (Kind = 'list') or (Kind = 'collection') or (Kind = 'binary') then ''
         else StringReplace(StringReplace(NodeText(AValue, AState.Source), #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]);
  Idx:= AddDfmPropRow(AState, ARange, ARange, DfmPropRow(AObjOrd, AParent, ADepth, AName, Kind, Txt));
  if Kind = 'list' then
    for i:= 0 to AValue.NamedChildCount - 1 do
    begin
      El:= AValue.NamedChild(i);
      if El.NodeType <> 'comment' then EmitDfmPropValue(AState, El, '', El, AObjOrd, Idx, ADepth + 1);
    end
  else if Kind = 'collection' then
    EmitDfmItems(AState, AValue, AObjOrd, Idx, ADepth + 1);
end;

procedure WalkProperty(const ANode: TTSNode; const AState: TDfmState; const AObjectName: string; AObjOrd: Integer);
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
  if AState.DfmProps <> nil then EmitDfmPropValue(AState, ANode, PropName, ValueNode, AObjOrd, -1, 0); { 151 Y2 }
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
  // v22: ...and EVERY other value kind, not only strings. Until now a DFM
  // property was searchable only when its value happened to be quoted, so
  // `query --text clBtnFace --source dfm` and `--text akLeft` returned NOTHING
  // while `Caption = 'x'` was found -- a gap that reads as "the text index is
  // broken" rather than "this value kind was never emitted".
  //
  // VALUE NODE TYPES, MEASURED with tools\dumpdfm (2026-09-09) rather than
  // guessed -- the plan listed them as UNMEASURED and they had to be dumped:
  //   Left = 8            -> number      (child: integer)
  //   Visible = False     -> boolean     (child: false/true)
  //   Color = clBtnFace   -> identifier_value
  //   Anchors = [akLeft]  -> set
  //   Caption = 'Hello'   -> string      (already handled, above)
  //   Picture.Data = {..} -> binary_blob  <- SKIPPED, see below
  //
  // binary_blob IS ITS OWN NODE TYPE, which is what makes the blob skip exact
  // instead of a size heuristic. Emitting those would put every glyph and
  // embedded image in the corpus into string_literals and hand the FTS index
  // pages of hex to tokenise, for content no one will ever search by name.
  if (not ValueNode.IsNull) and (ValueNode.NodeType <> 'string')
     and (ValueNode.NodeType <> 'binary_blob') then
  begin
    var Lit: TStringLiteral; Lit:= Default(TStringLiteral);
    Lit.Source   := 'dfm';
    Lit.Kind     := 'dfm-prop';
    Lit.OwnerName:= PropName;
    Lit.Text     := CollapseDfmWs(NodeText(ValueNode, AState.Source));
    { A cap, because a `set` or an identifier list has no natural bound and one
      pathological property must not be able to bloat the text index. 256 is the
      plan's figure; every value kind measured above is far below it, so the cap
      is a backstop rather than a routine truncation. Truncated rather than
      dropped: a searchable prefix beats an absent row. }
    if Length(Lit.Text) > MaxDfmLiteralText then Lit.Text:= Copy(Lit.Text, 1, MaxDfmLiteralText);
    if Lit.Text <> '' then
    begin
      Lit.StartLine:= Integer(ValueNode.StartPoint.row   ) + 1;
      Lit.StartCol := Integer(ValueNode.StartPoint.column) + 1;
      Lit.EndLine  := Integer(ValueNode.EndPoint  .row   ) + 1;
      Lit.EndCol   := Integer(ValueNode.EndPoint  .column) + 1;
      AState.Literals.Add(Lit);
    end;
  end
  else if (not ValueNode.IsNull) and (ValueNode.NodeType = 'string') then
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
  ObjOrd   : Integer    ;
  i        : Integer    ;
begin
  NameNode := ANode.ChildByField('name' );
  ClassNode:= ANode.ChildByField('class');
  if NameNode.IsNull then Exit;
  ObjName:= NodeText(NameNode, AState.Source);
  if ObjName = '' then Exit;
  ObjClass:= '';
  if not ClassNode.IsNull then ObjClass:= NodeText(ClassNode, AState.Source);
  QName:= if AParentQualifiedName <> '' then AParentQualifiedName + '.' + ObjName else ObjName;
  Signature:= ObjClass;
  Kind:= if AIsRoot then skForm else skComponent;
  Idx:= AState.Emit(Kind, ObjName, QName, Signature, AParentSymbolIdx, ANode);
  EmitDfmObject(AState, ANode, ObjName, ObjClass, AParentQualifiedName, QName, Idx); { 149 EX2 (F5) }
  ObjOrd:= AState.DfmObjects.Count - 1; { 151 Y2: this block's dfm_objects ordinal, before the children add theirs }

  { THE TYPE ON THE `object` LINE IS ITS OWN TOKEN CLASS, so `query --text
    "TOvcTable" --source dfm` can answer "which forms hold a component of this
    type, and how many". Until 2026-09-08 the DFM text index carried property
    VALUES only (`dfm-prop`), so that question returned 0 against a form holding
    28 such blocks -- and the only way to answer it was to read the .dfm as
    text, which is what the index exists to replace. It is the FIRST question
    asked before a component conversion.

    Emitted as `dfm-type` rather than folded into `dfm-prop` so the two stay
    separable: a caller can ask for types alone instead of substring-matching a
    property value that happens to contain a class name. The class name is
    already captured as the symbol's Signature above; this makes it SEARCHABLE
    rather than only reachable once you know which symbol to ask about. }
  if (not ClassNode.IsNull) and (ObjClass <> '') then
  begin
    var TypeLit: TStringLiteral; TypeLit:= Default(TStringLiteral);
    TypeLit.Source   := 'dfm';
    TypeLit.Kind     := 'dfm-type';
    TypeLit.OwnerName:= ObjName;
    TypeLit.Text     := ObjClass;
    TypeLit.StartLine:= Integer(ClassNode.StartPoint.row   ) + 1;
    TypeLit.StartCol := Integer(ClassNode.StartPoint.column) + 1;
    TypeLit.EndLine  := Integer(ClassNode.EndPoint  .row   ) + 1;
    TypeLit.EndCol   := Integer(ClassNode.EndPoint  .column) + 1;
    AState.Literals.Add(TypeLit);
  end;

  for i:= 0 to ANode.NamedChildCount - 1 do
  begin
    ChildNode:= ANode.NamedChild(i);
    if ChildNode.NodeType      = 'object' then WalkObject(ChildNode, AState, Idx, QName, False)
    else if ChildNode.NodeType = 'property' then WalkProperty(ChildNode, AState, ObjName, ObjOrd);
  end;
end; // procedure

{ Parses ASource (UTF-8, already transcoded) with AParser, whose Language the
  caller has set. The ONE copy of the tree-sitter read callback, shared by
  ExtractDfmEventBindings and TDFMParser.Parse (150 DF2: was duplicated, lint
  duplicate-code). Returns the tree; the caller owns and frees it. }
function ParseDfmSource(const AParser: TTSParser; const ASource: TBytes): TTSTree;
var
  Source: TBytes;
begin
  Source:= ASource;
  Result:= AParser.Parse(
    function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
    var Remaining: Integer;
    begin
      Remaining:= Length(Source) - Integer(AByteIndex);
      if Remaining <= 0 then
      begin
        ABytesRead:= 0;
        SetLength(Result, 0);
        Exit;
      end;
      SetLength(Result, Remaining);
      Move(Source[AByteIndex], Result[0], Remaining);
      ABytesRead:= Remaining;
    end, TTSInputEncoding.TSInputEncodingUTF8);
end;
function ExtractDfmEventBindings(const ASource: TBytes): TArray<TDfmEventBinding>;
var
  Source: TBytes   ;
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
  if IsBinaryDfmBytes(ASource) then Exit;
  Source:= EnsureUtf8Bytes(ASource);

  Parser:= TTSParser.Create;
  try
    Parser.Language:= tree_sitter_dfm;
    Tree:= ParseDfmSource(Parser, Source);
    try
      State:= TDfmState.Create(Source);
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

function ExtractDfmPropertyRowsFromBytes(const ASource: TBytes): TArray<TDfmPropertyRow>;
var
  Source: TBytes   ;
  Parser: TTSParser;
  Tree  : TTSTree  ;
  State : TDfmState;
  Root  : TTSNode  ;
  i     : Integer  ;
begin
  Result:= nil;
  if IsBinaryDfmBytes(ASource) then Exit; { the text grammar cannot read a binary .dfm (no dfm_objects either) }
  Source:= EnsureUtf8Bytes(ASource);
  Parser:= TTSParser.Create;
  try
    Parser.Language:= tree_sitter_dfm;
    Tree:= ParseDfmSource(Parser, Source);
    try
      State:= TDfmState.Create(Source);
      try
        State.DfmProps:= TList<TDfmPropertyRow>.Create;
        Root:= Tree.RootNode;
        for i:= 0 to Root.NamedChildCount - 1 do
          if Root.NamedChild(i).NodeType = 'object' then WalkObject(Root.NamedChild(i), State, -1, '', True);
        Result:= State.DfmProps.ToArray;
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
  if ADepth > MaxParseErrorDepth then Exit;
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
  if IsBinaryDfmBytes(ASource) then
  begin
    Result.Diagnostics:= [AFilePath + ': binary DFM (TPF0) -- save as Text DFM in the IDE to index this file'];
    Exit;
  end;
  Source:= ASource;
  Tree  := nil;
  State := nil;
  Parser:= TTSParser.Create;
  try
    Parser.Language:= FLanguage;
    Tree:= ParseDfmSource(Parser, Source);
    State:= TDfmState.Create(Source);
    Root:= Tree.RootNode;
    if Root.HasError then CollectParseErrors(Root, AFilePath, Result.Diagnostics, MaxParseDiagnostics, 0);
    // source_file -> [object ...]. Top-level objects are forms.
    for i:= 0 to Root.NamedChildCount - 1 do
    begin
      Child:= Root.NamedChild(i);
      if Child.NodeType = 'object' then WalkObject(Child, State, -1, '', True);
    end;
    Result.Symbols   := State.Symbols   .ToArray;
    Result.References:= State.References.ToArray;
    Result.Literals  := State.Literals  .ToArray;
    Result.DfmObjects:= State.DfmObjects.ToArray; { 149 EX2 (F5) }
    { 150 Y2: the navigation tree forms-csv / menu-tree read (dfm_nav_nodes / dfm_nav_props). }
    ScanDfmNav(DfmNavLinesFromBytes(Source), Result.DfmNavNodes, Result.DfmNavProps);
  finally
    State.Free;
    Tree.Free;
    Parser.Free;
  end; // try
end; // function

end.
