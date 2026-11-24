unit DRagLint.FieldRepo.DfmWrite;

{ drag-lint 1.54 -- lane TT-DFMWRITE: the byte-level editors of the repository -> DFM text engine (design
  2026-11-22-field-repository-v2-design.md section 9): a text DFM and the published field list of its unit. Both
  record edits against the bytes they were created from; every byte outside an edit is copied unchanged, whatever its
  encoding, line end or indentation. Generated text is 7-bit ASCII and is produced by the RTL itself. Nothing here
  reads or writes a file. }

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  /// <summary>Raised when a DFM or unit cannot be edited safely; nothing has been changed then.</summary>
  EDfmWriteError = class(Exception);

  /// <summary>One edit: replace Len bytes at Pos by Text (7-bit ASCII).</summary>
  TDfmwEdit = record
    /// <summary>0-based byte offset into the original bytes.</summary>
    Pos: Integer;
    /// <summary>Number of original bytes replaced; 0 = insertion.</summary>
    Len: Integer;
    /// <summary>The new text.</summary>
    Text: string;
  end;

  /// <summary>One property of a DFM object (0-based byte offsets, ends exclusive).</summary>
  TDfmwProp = record
    /// <summary>Property name as written (dotted for a sub-property).</summary>
    Name: string;
    /// <summary>Start of the name.</summary>
    Start: Integer;
    /// <summary>The byte after the `=`.</summary>
    EqualEnd: Integer;
    /// <summary>The value's bytes.</summary>
    ValueStart: Integer;
    ValueEnd: Integer;
  end;

  /// <summary>One `object` / `inherited` / `inline` block.</summary>
  TDfmwObject = record
    /// <summary>object, inherited or inline (lower case).</summary>
    Kind: string;
    /// <summary>Component name; '' when the header has none.</summary>
    Name: string;
    /// <summary>Class name.</summary>
    ObjClass: string;
    /// <summary>Index of the enclosing object, -1 for the root.</summary>
    Parent: Integer;
    /// <summary>Start of the header word and end of the header.</summary>
    Start: Integer;
    HeaderEnd: Integer;
    /// <summary>Start of the closing `end` and the byte after it.</summary>
    EndStart: Integer;
    Finish: Integer;
    /// <summary>Own properties in file order (those of child objects and collection items excluded).</summary>
    Props: TArray<TDfmwProp>;
  end;

  /// <summary>One string literal of a DFM property value.</summary>
  TDfmwString = record
    /// <summary>Index of its object in Objects.</summary>
    ObjectIndex: Integer;
    /// <summary>The object's property; the collection property for a string of an item.</summary>
    Prop: string;
    /// <summary>The property the string belongs to: of the collection item, else the same as Prop.</summary>
    ItemProp: string;
    /// <summary>The decoded string.</summary>
    Text: string;
  end;

  /// <summary>Byte buffer with recorded edits.</summary>
  /// <remarks>Not thread-safe. The edits never overlap: Output raises otherwise.</remarks>
  TDfmwBuffer = class
  strict private
    FBytes: TBytes;
    FFileName: string;
    FEdits: TArray<TDfmwEdit>;
    function SortedEdits: TArray<TDfmwEdit>;
  strict protected
    procedure Fail(const pMessage: string);
    procedure Edit(pPos, pLen: Integer; const pText: string);
    function LineStart(pPos: Integer): Integer;
    function LineEnd(pPos: Integer): Integer;
    function IsBlank(pFrom, pTo: Integer): Boolean;
    procedure CheckWholeLine(pFrom, pTo: Integer; const pWhat: string);
    function EolAt(pPos: Integer): string;
    function IndentAt(pPos: Integer): string;
    function Slice(pFrom, pTo: Integer): string;
    function BomLength: Integer;
    property Bytes: TBytes read FBytes;
  public
    /// <summary>Takes a reference to the bytes; they are never modified.</summary>
    /// <param name="pBytes">The file's bytes as read from disk.</param>
    /// <param name="pFileName">Name used in messages.</param>
    /// <exception cref="EDfmWriteError">The bytes are UTF-16.</exception>
    constructor Create(const pBytes: TBytes; const pFileName: string);
    /// <summary>The bytes with the recorded edits applied; the original bytes when there are none.</summary>
    /// <returns>New bytes.</returns>
    /// <exception cref="EDfmWriteError">Two edits overlap.</exception>
    function Output: TBytes;
    /// <summary>Forgets the recorded edits.</summary>
    procedure ClearEdits;
  end;

  /// <summary>A text DFM.</summary>
  TDfmDocument = class(TDfmwBuffer)
  strict private
    FObjects: TArray<TDfmwObject>;
    FUtf8: Boolean;
    FPos: Integer;
    procedure Parse;
    procedure SkipBlanks;
    function At(pChar: Char): Boolean;
    function ReadWord: string;
    procedure ReadHeader(const pKind: string; pStart, pParent: Integer);
    procedure ReadProp(const pName: string; pStart, pOwner: Integer);
    procedure SkipValue;
    procedure SkipQuoted;
    procedure SkipList(pClose: Char);
    procedure CollectStrings(pObject, pProp: Integer; pList: TList<TDfmwString>);
    function InsertPosition(pObject: Integer; const pName: string; const pOrder: TArray<string>): Integer;
    function ChildInsertPosition(pParent: Integer; const pSiblings: TArray<string>): Integer;
  public
    /// <summary>Parses a text DFM.</summary>
    /// <param name="pBytes">The file's bytes.</param>
    /// <param name="pFileName">Name used in messages.</param>
    /// <exception cref="EDfmWriteError">A binary DFM, a text the RTL cannot convert to binary, or one this reader does
    /// not understand.</exception>
    constructor Create(const pBytes: TBytes; const pFileName: string);
    /// <summary>Finds a component.</summary>
    /// <param name="pName">Component name (case-insensitive).</param>
    /// <param name="pParentName">Name of the enclosing object, '' = any.</param>
    /// <returns>Its index in Objects, -1 = none.</returns>
    /// <exception cref="EDfmWriteError">More than one component matches (an inline frame may repeat a name).</exception>
    function FindObject(const pName, pParentName: string): Integer;
    /// <summary>Text of a property value: the decoded string of a string literal, else the value as written.</summary>
    /// <param name="pObject">Index in Objects.</param>
    /// <param name="pName">Property name (case-insensitive).</param>
    /// <param name="pText">Receives the text; '' when absent.</param>
    /// <returns>True when the object's block states the property.</returns>
    function TryProp(pObject: Integer; const pName: string; out pText: string): Boolean;
    /// <summary>Records: give a property a value (added when the block does not state it).</summary>
    /// <param name="pObject">Index in Objects.</param>
    /// <param name="pName">Property name.</param>
    /// <param name="pLiteral">DFM text of the value, lines separated by CRLF, as DfmStringLiteral returns it.</param>
    /// <param name="pOrder">Property names in streaming order; an added property goes where the IDE would write it, a
    /// name not in the list after all others.</param>
    /// <exception cref="EDfmWriteError">The neighbouring text is not one property per line.</exception>
    procedure SetProp(pObject: Integer; const pName, pLiteral: string; const pOrder: TArray<string>);
    /// <summary>Records: remove a property's line(s); nothing when the block does not state it.</summary>
    /// <param name="pObject">Index in Objects.</param>
    /// <param name="pName">Property name.</param>
    /// <exception cref="EDfmWriteError">The property shares its line with other text.</exception>
    procedure RemoveProp(pObject: Integer; const pName: string);
    /// <summary>Records: add a child object.</summary>
    /// <param name="pParent">Index of the parent in Objects.</param>
    /// <param name="pBlock">Lines of the block, indented relative to the block (DfmBlockOfStream).</param>
    /// <param name="pSiblings">Component names; the block goes after the last child among them, else before the first
    /// child, else before the parent's `end`.</param>
    /// <exception cref="EDfmWriteError">The neighbouring text is not line-structured.</exception>
    procedure InsertChild(pParent: Integer; const pBlock, pSiblings: TArray<string>);
    /// <summary>Records: remove an object with everything in it.</summary>
    /// <param name="pObject">Index in Objects.</param>
    /// <exception cref="EDfmWriteError">Its first or last line holds other text.</exception>
    procedure RemoveObject(pObject: Integer);
    /// <summary>Properties (collection items included) whose value names a component outside a string.</summary>
    /// <param name="pName">Component name.</param>
    /// <returns>`Component.Property` per reference, the component's own properties excluded.</returns>
    function ReferencesTo(const pName: string): TArray<string>;
    /// <summary>Every string of every property (collection items and string lists included; a string list gives one
    /// entry per line).</summary>
    /// <returns>The strings in file order; binary data is not searched.</returns>
    function Strings: TArray<TDfmwString>;
    /// <summary>Every object, parents before children, in file order.</summary>
    property Objects: TArray<TDfmwObject> read FObjects;
  end;

  /// <summary>One identifier, symbol or string literal of a unit.</summary>
  TDfmwToken = record
    /// <summary>The text as written.</summary>
    Text: string;
    /// <summary>0-based byte offset; Pos + Len = end.</summary>
    Pos: Integer;
    Len: Integer;
  end;

  /// <summary>A published field declaration `Name: TClass;`.</summary>
  TDfmwDecl = record
    /// <summary>Field name and class.</summary>
    Name: string;
    DeclClass: string;
    /// <summary>First byte of the declaration and the byte after its `;`.</summary>
    Start: Integer;
    Finish: Integer;
    /// <summary>True for a name of a list `A, B: T;`.</summary>
    Grouped: Boolean;
  end;

  /// <summary>The unit of a form: only its component declarations are edited.</summary>
  TDfmUnitDocument = class(TDfmwBuffer)
  strict private
    FTokens: TArray<TDfmwToken>;
    FComments: TArray<TDfmwToken>; // directives included
    FConditionals: TArray<TDfmwToken>; // Text = IFDEF, ELSE, ENDIF, ...
    function DirectiveWord(pStart: Integer): string;
    function ConditionsAt(pPos: Integer): string;
    function IsSafePlace(pHeader, pStop, pPos: Integer): Boolean;
    function ReadSection(const pClass: string; out pHeader, pStop: Integer): TArray<TDfmwDecl>;
    procedure Tokenize;
    function SkipComment(var pPos: Integer): Boolean;
    function SkipString(pPos: Integer): Integer;
    function SkipWord(pPos: Integer): Integer;
    function FindClassHeader(const pClass: string): Integer;
    function AfterAncestors(pToken: Integer): Integer;
    function ReadDecl(var pToken: Integer; var pDecls: TArray<TDfmwDecl>): Boolean;
    procedure CheckLineOfItsOwn(pStart, pFinish: Integer; const pName: string);
  public
    /// <summary>Reads the tokens of a unit (comments, directives and strings are told apart).</summary>
    /// <param name="pBytes">The file's bytes.</param>
    /// <param name="pFileName">Name used in messages.</param>
    /// <exception cref="EDfmWriteError">The bytes are UTF-16.</exception>
    constructor Create(const pBytes: TBytes; const pFileName: string);
    /// <summary>Component declarations of a class: the fields before its first method or other visibility.</summary>
    /// <param name="pClass">Class name.</param>
    /// <returns>The declarations in order.</returns>
    /// <exception cref="EDfmWriteError">The unit does not declare the class, or declares it more than once (conditional
    /// compilation).</exception>
    function Declarations(const pClass: string): TArray<TDfmwDecl>;
    /// <summary>True when the interface section uses one of the units.</summary>
    /// <param name="pUnits">Unit names (case-insensitive).</param>
    /// <returns>True when found.</returns>
    function UsesAny(const pUnits: TArray<string>): Boolean;
    /// <summary>How many times a token occurs in the code (comments excluded).</summary>
    /// <param name="pText">An identifier or a string literal with its quotes (case-insensitive).</param>
    /// <returns>The number of tokens.</returns>
    function Mentions(const pText: string): Integer;
    /// <summary>True when a string literal of the code is the name, or has it as one entry of a list `A;B`.</summary>
    /// <param name="pName">A field name (case-insensitive).</param>
    /// <returns>True when found.</returns>
    function NamesInString(const pName: string): Boolean;
    /// <summary>Records: declare a component.</summary>
    /// <param name="pClass">The form class.</param>
    /// <param name="pName">Component name.</param>
    /// <param name="pFieldClass">Component class.</param>
    /// <param name="pAfter">Component names; the line goes after the last declaration among them, else after the last
    /// declaration, else after the class header. A place that a conditional directive compiles away while the rest of
    /// the published section stays, or one inside a comment, is passed over.</param>
    /// <exception cref="EDfmWriteError">The class is missing or declared more than once, the neighbouring line holds
    /// other code, or every place is inside a conditional.</exception>
    procedure AddField(const pClass, pName, pFieldClass: string; const pAfter: TArray<string>);
    /// <summary>Records: remove a component's declaration.</summary>
    /// <param name="pClass">The form class.</param>
    /// <param name="pName">Component name; nothing happens when it is not declared.</param>
    /// <exception cref="EDfmWriteError">The declaration shares its line or its type with another one.</exception>
    procedure RemoveField(const pClass, pName: string);
  end;

/// <summary>The bytes of a text DFM as a binary DFM, converted by the RTL: proof that Delphi can read the text.</summary>
/// <param name="pText">Text DFM bytes.</param>
/// <returns>Binary DFM bytes.</returns>
/// <exception cref="EDfmWriteError">The RTL refuses the text; its message is kept.</exception>
function DfmTextToBinary(const pText: TBytes): TBytes;

/// <summary>A DFM string literal as the IDE writes it (quotes, #nnn, continuation lines).</summary>
/// <param name="pValue">The string.</param>
/// <returns>7-bit ASCII, everything the RTL writes after the `=`; continuation lines are separated by CRLF and indented
/// relative to the property's object.</returns>
function DfmStringLiteral(const pValue: string): string;

/// <summary>What a DFM value stands for: the string of a string literal, else the value without blanks around it.</summary>
/// <param name="pLiteral">A value as SetProp takes it.</param>
/// <returns>The text TryProp gives for it.</returns>
function DfmLiteralText(const pLiteral: string): string;

/// <summary>The text block of a component as the RTL writes it.</summary>
/// <param name="pBinary">A component stream (TStream.WriteComponent).</param>
/// <returns>Lines without line breaks, from the `object` line to its `end`.</returns>
function DfmBlockOfStream(const pBinary: TBytes): TArray<string>;

/// <summary>Index of a declaration.</summary>
/// <param name="pDecls">Declarations.</param>
/// <param name="pName">Field name (case-insensitive).</param>
/// <returns>The index, -1 = none.</returns>
function IndexOfDecl(const pDecls: TArray<TDfmwDecl>; const pName: string): Integer;

implementation

uses
  System.Classes,
  System.StrUtils;

const
  TAB = 9;
  LF = 10;
  CR = 13;
  QUOTE = 39; // apostrophe
  FIRST_NON_ASCII = $80;
  LAST_BLANK = 32;
  BYTE_MASK = $FF;
  LAST_ASCII = #$7E;
  UTF16_BOM_LENGTH = 2;
  UTF16_FIRST = $FE; // FE FF and FF FE are the two UTF-16 marks
  NAIVE_CHUNK = 48; // characters per line of the literal handed to the RTL (TParser has a line limit)
  MULTI_LINE_QUOTES = 3;
  STEP = '  '; // one nesting level of a DFM
  CRLF = #13#10;
  WORD_END = 'end';
  WORD_IMPLEMENTATION = 'implementation';
  RESOURCE_BYTE = $FF;
  UTF8_BOM: array[0..2] of Byte = ($EF, $BB, $BF);
  BINARY_SIGNATURE: array[0..3] of Byte = (Ord('T'), Ord('P'), Ord('F'), Ord('0'));
  BLOCK_KINDS: array[0..2] of string = ('object', 'inherited', 'inline');
  PROBE_PROP = 'P =';
  PROBE_HEAD = 'object A: TB' + CRLF + '  ' + PROBE_PROP + ' ';
  PROBE_TAIL = CRLF + WORD_END + CRLF;
  REFERENCE_BREAKS: array[0..11] of Char = (' ', '.', '=', '(', ')', '[', ']', '<', '>', ',', #13, #10);
  DIRECTIVE_MARK = '$';
  PAREN_COMMENT_LENGTH = 2; // (* and //
  CONDITIONAL_OPENS: array[0..3] of string = ('IF', 'IFDEF', 'IFNDEF', 'IFOPT');
  CONDITIONAL_BRANCHES: array[0..1] of string = ('ELSE', 'ELSEIF');
  CONDITIONAL_CLOSES: array[0..1] of string = ('ENDIF', 'IFEND');
  MEMBER_STOPS: array[0..17] of string = ('private', 'protected', 'public', 'strict', WORD_END, 'procedure', 'function',
    'constructor', 'destructor', 'property', 'class', 'const', 'type', 'var', '[', 'automated', 'operator', 'threadvar');

{ ---- RTL helpers ---- }

function DfmTextToBinary(const pText: TBytes): TBytes;
var
  VIn, VOut: TBytesStream;
begin
  VIn := TBytesStream.Create(pText);
  VOut := TBytesStream.Create;
  try
    try
      ObjectTextToBinary(VIn, VOut);
    except
      on E: Exception do
        raise EDfmWriteError.Create('Delphi cannot read the DFM text: ' + E.Message);
    end;
    Result := Copy(VOut.Bytes, 0, VOut.Size);
  finally
    VOut.Free;
    VIn.Free;
  end;
end;

function BinaryToText(const pBinary: TBytes): string;
var
  VIn, VOut: TBytesStream;
begin
  VIn := TBytesStream.Create(pBinary);
  VOut := TBytesStream.Create;
  try
    ObjectBinaryToText(VIn, VOut);
    Result := TEncoding.UTF8.GetString(VOut.Bytes, 0, VOut.Size);
  finally
    VOut.Free;
    VIn.Free;
  end;
end;

function DfmBlockOfStream(const pBinary: TBytes): TArray<string>;
begin
  Result := TrimRight(BinaryToText(pBinary)).Split([CRLF]);
end;

function DfmStringLiteral(const pValue: string): string;
var
  VI: Integer;
  VText: TStringBuilder;
begin
  VText := TStringBuilder.Create(PROBE_HEAD);
  try
    if pValue = '' then
      VText.Append('''''');
    for VI := 1 to Length(pValue) do
    begin
      if (VI > 1) and (VI mod NAIVE_CHUNK = 1) then
        VText.Append(' +').Append(CRLF);
      VText.Append('#').Append(Ord(pValue[VI]));
    end;
    VText.Append(PROBE_TAIL);
    Result := BinaryToText(DfmTextToBinary(TEncoding.ASCII.GetBytes(VText.ToString)));
  finally
    VText.Free;
  end;
  Result := Result.Substring(Result.IndexOf(PROBE_PROP) + Length(PROBE_PROP));
  Result := TrimRight(Result.Substring(0, Result.LastIndexOf(WORD_END)));
end;

function IndexOfDecl(const pDecls: TArray<TDfmwDecl>; const pName: string): Integer;
var
  VI: Integer;
begin
  Result := -1;
  for VI := 0 to High(pDecls) do
    if SameText(pDecls[VI].Name, pName) then
      Exit(VI);
end;

function StartsWithBytes(const pBytes: TBytes; const pStart: array of Byte): Boolean;
var
  VI: Integer;
begin
  Result := Length(pBytes) >= Length(pStart);
  if Result then
    for VI := 0 to High(pStart) do  // dl:ok index-possibly-out-of-range@b945 -- REVIEWED 2026-11-23 TT-DFMWRITE: Result is True only when pBytes is at least as long as pStart
      Result := Result and (pBytes[VI] = pStart[VI]);
end;

{ TDfmwBuffer }

constructor TDfmwBuffer.Create(const pBytes: TBytes; const pFileName: string);
begin
  inherited Create;
  FBytes := pBytes;
  FFileName := pFileName;
  if (Length(pBytes) >= UTF16_BOM_LENGTH) and (pBytes[0] >= UTF16_FIRST) and (pBytes[1] >= UTF16_FIRST) then
    Fail('UTF-16 text is not edited');
end;

procedure TDfmwBuffer.Fail(const pMessage: string);
begin
  raise EDfmWriteError.Create(FFileName + ': ' + pMessage);
end;

procedure TDfmwBuffer.ClearEdits;
begin
  FEdits := nil;
end;

procedure TDfmwBuffer.Edit(pPos, pLen: Integer; const pText: string);
var
  VEdit: TDfmwEdit;
  VC: Char;
begin
  for VC in pText do
    if VC > LAST_ASCII then
      Fail('the new text is not ASCII: ' + Trim(pText));
  VEdit.Pos := pPos;
  VEdit.Len := pLen;
  VEdit.Text := pText;
  FEdits := FEdits + [VEdit];
end;

{ By position; an insertion before a replacement at the same place, insertions in the order they were recorded. }
function TDfmwBuffer.SortedEdits: TArray<TDfmwEdit>;
var
  VI, VJ: Integer;
  VEdit: TDfmwEdit;
begin
  Result := Copy(FEdits);
  for VI := 1 to High(Result) do
  begin
    VEdit := Result[VI];
    VJ := VI - 1;
    while (VJ >= 0) and ((Result[VJ].Pos > VEdit.Pos)
      or ((Result[VJ].Pos = VEdit.Pos) and (Result[VJ].Len > 0) and (VEdit.Len = 0))) do
    begin
      Result[VJ + 1] := Result[VJ];
      Dec(VJ);
    end;
    Result[VJ + 1] := VEdit;
  end;
end;

function TDfmwBuffer.Output: TBytes;
var
  VEdit: TDfmwEdit;
  VDone: Integer;
  VOut: TBytesStream;
  VText: TBytes;
begin
  if Length(FEdits) = 0 then
    Exit(FBytes);
  VDone := 0;
  VOut := TBytesStream.Create;
  try
    for VEdit in SortedEdits do
    begin
      if VEdit.Pos < VDone then
        Fail('two changes edit the same text');
      VOut.WriteBuffer(FBytes, VDone, VEdit.Pos - VDone);
      VText := TEncoding.ASCII.GetBytes(VEdit.Text);
      VOut.WriteBuffer(VText, Length(VText));
      VDone := VEdit.Pos + VEdit.Len;
    end;
    VOut.WriteBuffer(FBytes, VDone, Length(FBytes) - VDone);
    Result := Copy(VOut.Bytes, 0, VOut.Size);
  finally
    VOut.Free;
  end;
end;

function TDfmwBuffer.BomLength: Integer;
begin
  Result := if StartsWithBytes(FBytes, UTF8_BOM) then Length(UTF8_BOM) else 0;
end;

function TDfmwBuffer.LineStart(pPos: Integer): Integer;
begin
  Result := pPos;
  while (Result > BomLength) and (FBytes[Result - 1] not in [LF, CR]) do
    Dec(Result);
end;

{ The byte after the line end of the line pPos is on. }
function TDfmwBuffer.LineEnd(pPos: Integer): Integer;
begin
  Result := pPos;
  while (Result < Length(FBytes)) and (FBytes[Result] not in [LF, CR]) do
    Inc(Result);
  if (Result < Length(FBytes)) and (FBytes[Result] = CR) then
    Inc(Result);
  if (Result < Length(FBytes)) and (FBytes[Result] = LF) then
    Inc(Result);
end;

function TDfmwBuffer.IsBlank(pFrom, pTo: Integer): Boolean;
var
  VI: Integer;
begin
  Result := True;
  for VI := pFrom to pTo - 1 do
    if FBytes[VI] > LAST_BLANK then
      Exit(False);
end;

{ Raises unless the text pFrom..pTo has its lines to itself and the last of them has a line end. }
procedure TDfmwBuffer.CheckWholeLine(pFrom, pTo: Integer; const pWhat: string);
begin
  if not (IsBlank(LineStart(pFrom), pFrom) and IsBlank(pTo, LineEnd(pTo))) then
    Fail(pWhat + ' shares its line with other text');
  if EolAt(pTo) = '' then
    Fail(pWhat + ' is on a line without a line end');
end;

{ The line end of the line pPos is on; '' at the end of the file. }
function TDfmwBuffer.EolAt(pPos: Integer): string;
var
  VI: Integer;
begin
  Result := '';
  for VI := LineEnd(pPos) - 1 downto pPos do
    if FBytes[VI] in [LF, CR] then
      Result := Char(FBytes[VI]) + Result
    else
      Break;
end;

function TDfmwBuffer.IndentAt(pPos: Integer): string;
var
  VI, VStart: Integer;
begin
  VStart := LineStart(pPos);
  Result := StringOfChar(' ', pPos - VStart);
  for VI := VStart to pPos - 1 do
    if FBytes[VI] = TAB then
      Result[VI - VStart + 1] := #9;
end;
{ Bytes as text, one character per byte: offsets stay valid, only ASCII parts mean something. }
function TDfmwBuffer.Slice(pFrom, pTo: Integer): string;
var
  VI: Integer;
begin
  SetLength(Result, pTo - pFrom);
  for VI := pFrom to pTo - 1 do
    Result[VI - pFrom + 1] := Char(FBytes[VI]);
end;

{ ---- DFM ---- }

function IsBinaryDfm(const pBytes: TBytes): Boolean;
begin
  Result := StartsWithBytes(pBytes, [RESOURCE_BYTE]) or StartsWithBytes(pBytes, BINARY_SIGNATURE);
end;

{ The bracket that closes one; #0 for any other character. }
function CloserOf(pOpener: Char): Char;
begin
  case pOpener of
    '(': Result := ')';
    '[': Result := ']';
    '<': Result := '>';
    '{': Result := '}';
  else
    Result := #0;
  end;
end;
function IsWordByte(pByte: Byte): Boolean;
begin
  Result := (pByte >= FIRST_NON_ASCII) or CharInSet(Char(pByte), ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

{ TDfmDocument }

constructor TDfmDocument.Create(const pBytes: TBytes; const pFileName: string);
begin
  if IsBinaryDfm(pBytes) then
    raise EDfmWriteError.Create(pFileName + ': a binary DFM is not written (make it text first: convert -i -t <file>)');
  inherited Create(pBytes, pFileName);
  FUtf8 := BomLength > 0; // as TParser: without a BOM the text is ANSI
  try
    DfmTextToBinary(pBytes);
  except
    on E: EDfmWriteError do
      Fail(E.Message);
  end;
  Parse;
end;

procedure TDfmDocument.SkipBlanks;
begin
  while (FPos < Length(Bytes)) and (Bytes[FPos] <= LAST_BLANK) do
    Inc(FPos);
end;

function TDfmDocument.At(pChar: Char): Boolean;
begin
  Result := (FPos < Length(Bytes)) and (Bytes[FPos] = Ord(pChar));
end;

{ A dotted identifier or a number; '' when the next byte starts none. }
function TDfmDocument.ReadWord: string;
var
  VStart: Integer;
begin
  VStart := FPos;
  while (FPos < Length(Bytes)) and (IsWordByte(Bytes[FPos]) or At('.')) do
    Inc(FPos);
  Result := Slice(VStart, FPos);
end;

{ A string value: quoted runs, #nnn and ` + ` continuations. }
procedure TDfmDocument.SkipQuoted;
var
  VAfter: Integer;
begin
  while FPos < Length(Bytes) do
    if At('''') then
    begin
      repeat
        Inc(FPos);
        if (FPos >= Length(Bytes)) or (Bytes[FPos] in [LF, CR]) then
          Fail('unterminated string');
      until At('''');
      Inc(FPos);
    end
    else if At('#') then
    begin
      Inc(FPos);
      ReadWord;
    end
    else
    begin
      VAfter := FPos;
      SkipBlanks;
      if not At('+') then
      begin
        FPos := VAfter;
        Exit;
      end;
      Inc(FPos);
      SkipBlanks;
    end;
end;

{ From after the opening bracket to the byte after the closing one. }
procedure TDfmDocument.SkipList(pClose: Char);
var
  VC: Char;
begin
  while FPos < Length(Bytes) do
  begin
    if At('''') or At('#') then
    begin
      SkipQuoted;
      Continue;
    end;
    VC := Char(Bytes[FPos]);
    Inc(FPos);
    if VC = pClose then
      Exit;
    if (pClose <> '}') and (CloserOf(VC) <> #0) then
      SkipList(CloserOf(VC));
  end;
  Fail('unterminated value');
end;

procedure TDfmDocument.SkipValue;
var
  VC: Char;
begin
  if FPos >= Length(Bytes) then
    Fail('a property without a value');
  VC := Char(Bytes[FPos]);
  if At('''') or At('#') then
    SkipQuoted
  else if CloserOf(VC) <> #0 then
  begin
    Inc(FPos);
    SkipList(CloserOf(VC));
  end
  else
    while (FPos < Length(Bytes)) and (Bytes[FPos] > LAST_BLANK) do
      Inc(FPos);
end;

procedure TDfmDocument.ReadHeader(const pKind: string; pStart, pParent: Integer);
var
  VObject: TDfmwObject;
begin
  VObject := Default(TDfmwObject);
  VObject.Kind := LowerCase(pKind);
  VObject.Parent := pParent;
  VObject.Start := pStart;
  VObject.ObjClass := ReadWord;
  VObject.HeaderEnd := FPos;
  SkipBlanks;
  if At(':') then
  begin
    Inc(FPos);
    SkipBlanks;
    VObject.Name := VObject.ObjClass;
    VObject.ObjClass := ReadWord;
    VObject.HeaderEnd := FPos;
    SkipBlanks;
  end;
  if At('[') then
  begin
    Inc(FPos);
    SkipList(']');
    VObject.HeaderEnd := FPos;
  end;
  FObjects := FObjects + [VObject];
end;

procedure TDfmDocument.ReadProp(const pName: string; pStart, pOwner: Integer);
var
  VProp: TDfmwProp;
begin
  if (pName = '') or (pOwner < 0) or (not At('=')) then
    Fail('unexpected text at byte ' + IntToStr(pStart));
  Inc(FPos);
  VProp.Name := pName;
  VProp.Start := pStart;
  VProp.EqualEnd := FPos;
  SkipBlanks;
  VProp.ValueStart := FPos;
  SkipValue;
  VProp.ValueEnd := FPos;
  FObjects[pOwner].Props := FObjects[pOwner].Props + [VProp];  // dl:ok index-possibly-out-of-range@9422 -- REVIEWED 2026-11-23 TT-DFMWRITE: Fail raises for pOwner below 0; the caller passes an index into FObjects
end;

procedure TDfmDocument.Parse;
var
  VWord: string;
  VStart, VOwner: Integer;
begin
  FPos := BomLength;
  VOwner := -1;
  SkipBlanks;
  while FPos < Length(Bytes) do
  begin
    VStart := FPos;
    VWord := ReadWord;
    SkipBlanks;
    if At('=') or ((VOwner < 0) and (Length(FObjects) > 0)) then
      ReadProp(VWord, VStart, VOwner)
    else if MatchText(VWord, BLOCK_KINDS) then
    begin
      ReadHeader(VWord, VStart, VOwner);
      VOwner := High(FObjects);  // dl:ok index-possibly-out-of-range@9a95 -- REVIEWED 2026-11-23 TT-DFMWRITE: VOwner is -1 or an index into FObjects, tested in the same condition
    end
    else if SameText(VWord, WORD_END) and (VOwner >= 0) then
    begin
      FObjects[VOwner].EndStart := VStart;
      FObjects[VOwner].Finish := VStart + Length(WORD_END);
      VOwner := FObjects[VOwner].Parent;
    end
    else
      ReadProp(VWord, VStart, VOwner);
    SkipBlanks;
  end;
  if (VOwner >= 0) or (Length(FObjects) = 0) then
    Fail('not a complete DFM');
end;

function TDfmDocument.FindObject(const pName, pParentName: string): Integer;
var
  VI: Integer;
begin
  Result := -1;
  for VI := 0 to High(FObjects) do
    if SameText(FObjects[VI].Name, pName) and ((pParentName = '')
      or ((FObjects[VI].Parent >= 0) and SameText(FObjects[FObjects[VI].Parent].Name, pParentName))) then
    begin
      if Result >= 0 then
        Fail('more than one component ' + pName);
      Result := VI;
    end;
end;

function IndexOfProp(const pObject: TDfmwObject; const pName: string): Integer;
var
  VI: Integer;
begin
  Result := -1;
  for VI := 0 to High(pObject.Props) do
    if SameText(pObject.Props[VI].Name, pName) then
      Exit(VI);
end;

{ Text of a quoted run; pRaw has one character per byte. }
function DecodeRun(const pRaw: string; pUtf8: Boolean): string;
var
  VI: Integer;
  VBytes: TBytes;
begin
  SetLength(VBytes, Length(pRaw));
  for VI := 1 to Length(pRaw) do
    VBytes[VI - 1] := Byte(Ord(pRaw[VI]) and BYTE_MASK);
  Result := if pUtf8 then TEncoding.UTF8.GetString(VBytes) else TEncoding.ANSI.GetString(VBytes);
end;

{ The string a literal stands for; pSource has one character per byte. }
function DecodeLiteral(const pSource: string; pUtf8: Boolean): string;
var
  VI, VStart: Integer;
  VText: TStringBuilder;
begin
  VText := TStringBuilder.Create;
  try
    VI := 1;
    while VI <= Length(pSource) do
    begin
      VStart := VI;
      Inc(VI);
      if pSource[VStart] = '#' then
      begin
        while (VI <= Length(pSource)) and CharInSet(pSource[VI], ['0'..'9', '$', 'A'..'F', 'a'..'f']) do
          Inc(VI);
        VText.Append(Char(StrToInt(Copy(pSource, VStart + 1, VI - VStart - 1))));
      end
      else if pSource[VStart] = '''' then
      begin
        VI := Pos('''', pSource, VI);
        VText.Append(DecodeRun(Copy(pSource, VStart + 1, VI - VStart - 1), pUtf8));
        Inc(VI);
        if (VI <= Length(pSource)) and (pSource[VI] = '''') then
          VText.Append(''''); // a doubled quote: the next run starts with it
      end;
    end;
    Result := VText.ToString;
  finally
    VText.Free;
  end;
end;

function IsStringLiteral(const pText: string): Boolean;
begin
  Result := (pText <> '') and CharInSet(pText[1], ['''', '#']);
end;

function DfmLiteralText(const pLiteral: string): string;
begin
  Result := Trim(pLiteral);
  if IsStringLiteral(Result) then
    Result := DecodeLiteral(Result, False);
end;

function TDfmDocument.TryProp(pObject: Integer; const pName: string; out pText: string): Boolean;
var
  VIdx: Integer;
begin
  pText := '';
  VIdx := IndexOfProp(FObjects[pObject], pName);  // dl:ok index-possibly-out-of-range@ee4a -- REVIEWED 2026-11-23 TT-DFMWRITE: an index into Objects from FindObject, documented; ApplyItem refuses -1
  Result := VIdx >= 0;
  if not Result then
    Exit;
  pText := Slice(FObjects[pObject].Props[VIdx].ValueStart, FObjects[pObject].Props[VIdx].ValueEnd);
  if IsStringLiteral(pText) then
    pText := DecodeLiteral(pText, FUtf8);
end;

function StreamRank(const pName: string; const pOrder: TArray<string>): Integer;
begin
  Result := IndexText(pName, pOrder);
  if Result < 0 then
    Result := MaxInt;
end;

{ Start of the line before which a new property goes. }
function TDfmDocument.InsertPosition(pObject: Integer; const pName: string; const pOrder: TArray<string>): Integer;
var
  VProp: TDfmwProp;
  VAfterStart, VAfterEnd, VRank: Integer;
begin
  VAfterStart := FObjects[pObject].Start;
  VAfterEnd := FObjects[pObject].HeaderEnd;
  VRank := StreamRank(pName, pOrder);
  for VProp in FObjects[pObject].Props do
    if StreamRank(VProp.Name, pOrder) <= VRank then
    begin
      VAfterStart := VProp.Start;
      VAfterEnd := VProp.ValueEnd;
    end;
  CheckWholeLine(VAfterStart, VAfterEnd, 'the text before ' + pName);
  Result := LineEnd(VAfterEnd);
end;

procedure TDfmDocument.SetProp(pObject: Integer; const pName, pLiteral: string; const pOrder: TArray<string>);
var
  VIdx: Integer;
  VProp: TDfmwProp;
  VEol, VText, VIndent: string;
begin
  VEol := EolAt(FObjects[pObject].HeaderEnd);  // dl:ok index-possibly-out-of-range@66a5 -- REVIEWED 2026-11-23 TT-DFMWRITE: an index into Objects from FindObject, documented; ApplyItem refuses -1
  VIndent := IndentAt(FObjects[pObject].Start);
  VText := pLiteral.Replace(CRLF, VEol + VIndent);
  if not (VText.StartsWith(' ') or VText.StartsWith(VEol)) then
    VText := ' ' + VText;
  VIdx := IndexOfProp(FObjects[pObject], pName);
  if VIdx < 0 then
    Edit(InsertPosition(pObject, pName, pOrder), 0, VIndent + STEP + pName + ' =' + VText + VEol)
  else
  begin
    VProp := FObjects[pObject].Props[VIdx];
    Edit(VProp.EqualEnd, VProp.ValueEnd - VProp.EqualEnd, VText);
  end;
end;

procedure TDfmDocument.RemoveProp(pObject: Integer; const pName: string);
var
  VIdx, VStart: Integer;
  VProp: TDfmwProp;
begin
  VIdx := IndexOfProp(FObjects[pObject], pName);  // dl:ok index-possibly-out-of-range@ee4a -- REVIEWED 2026-11-23 TT-DFMWRITE: an index into Objects from FindObject, documented; ApplyItem refuses -1
  if VIdx < 0 then
    Exit;
  VProp := FObjects[pObject].Props[VIdx];
  CheckWholeLine(VProp.Start, VProp.ValueEnd, pName);
  VStart := LineStart(VProp.Start);
  Edit(VStart, LineEnd(VProp.ValueEnd) - VStart, '');
end;

{ Start of the line before which a new child goes. }
function TDfmDocument.ChildInsertPosition(pParent: Integer; const pSiblings: TArray<string>): Integer;
var
  VI, VLast, VNext: Integer;
begin
  VLast := -1;
  VNext := FObjects[pParent].EndStart;
  for VI := High(FObjects) downto pParent + 1 do
    if FObjects[VI].Parent = pParent then
    begin
      VNext := FObjects[VI].Start;
      if (VLast < 0) and MatchText(FObjects[VI].Name, pSiblings) then
        VLast := VI;
    end;
  if VLast >= 0 then
  begin
    CheckWholeLine(FObjects[VLast].EndStart, FObjects[VLast].Finish, 'the end of ' + FObjects[VLast].Name);
    Exit(LineEnd(FObjects[VLast].Finish));
  end;
  Result := LineStart(VNext);
  if not IsBlank(Result, VNext) then
    Fail('the text of ' + FObjects[pParent].Name + ' is not one item per line');
end;

procedure TDfmDocument.InsertChild(pParent: Integer; const pBlock, pSiblings: TArray<string>);
var
  VLine, VText, VIndent, VEol: string;
begin
  VText := '';
  VEol := EolAt(FObjects[pParent].HeaderEnd);  // dl:ok index-possibly-out-of-range@eec8 -- REVIEWED 2026-11-23 TT-DFMWRITE: an index into Objects from FindObject, documented; ApplyItem refuses -1
  if VEol = '' then
    Fail('no line end after the header of ' + FObjects[pParent].Name);
  VIndent := IndentAt(FObjects[pParent].Start) + STEP;
  for VLine in pBlock do
    VText := VText + VIndent + VLine + VEol;
  Edit(ChildInsertPosition(pParent, pSiblings), 0, VText);
end;

procedure TDfmDocument.RemoveObject(pObject: Integer);
var
  VStart: Integer;
begin
  CheckWholeLine(FObjects[pObject].EndStart, FObjects[pObject].Finish, 'the end of ' + FObjects[pObject].Name);  // dl:ok index-possibly-out-of-range@68ce -- REVIEWED 2026-11-23 TT-DFMWRITE: an index into Objects from FindObject, documented; ApplyItem refuses -1
  VStart := LineStart(FObjects[pObject].Start);
  if not IsBlank(VStart, FObjects[pObject].Start) then
    Fail(FObjects[pObject].Name + ' shares its line with other text');
  Edit(VStart, LineEnd(FObjects[pObject].Finish) - VStart, '');
end;

function TDfmDocument.ReferencesTo(const pName: string): TArray<string>;
var
  VObject: TDfmwObject;
  VProp: TDfmwProp;
  VValue: string;
begin
  Result := nil;
  for VObject in FObjects do
    if not SameText(VObject.Name, pName) then
      for VProp in VObject.Props do
      begin
        VValue := Slice(VProp.ValueStart, VProp.ValueEnd);
        if ContainsText(VValue, pName) and MatchText(pName, VValue.Split(REFERENCE_BREAKS)) then
          Result := Result + [VObject.Name + '.' + VProp.Name];
      end;
end;

{ The strings of one property; a word before `=` names the property of a collection item. }
procedure TDfmDocument.CollectStrings(pObject, pProp: Integer; pList: TList<TDfmwString>);
var
  VProp: TDfmwProp;
  VString: TDfmwString;
  VStart: Integer;
  VWord: string;
begin
  VProp := FObjects[pObject].Props[pProp];
  VString.ObjectIndex := pObject;
  VString.Prop := VProp.Name;
  VString.ItemProp := VProp.Name;
  FPos := VProp.ValueStart;
  while FPos < VProp.ValueEnd do
  begin
    VStart := FPos;
    VWord := ReadWord;
    if At('''') or At('#') then
    begin
      VStart := FPos;
      SkipQuoted;
      VString.Text := DecodeLiteral(Slice(VStart, FPos), FUtf8);
      pList.Add(VString);
    end
    else if VWord <> '' then
    begin
      SkipBlanks;
      if At('=') then
        VString.ItemProp := VWord;
    end
    else if FPos = VStart then
      Inc(FPos);
  end;
end;

function TDfmDocument.Strings: TArray<TDfmwString>;
var
  VI, VJ: Integer;
  VList: TList<TDfmwString>;
begin
  VList := TList<TDfmwString>.Create;
  try
    for VI := 0 to High(FObjects) do
      for VJ := 0 to High(FObjects[VI].Props) do
        if Bytes[FObjects[VI].Props[VJ].ValueStart] <> Ord('{') then
          CollectStrings(VI, VJ, VList);
    Result := VList.ToArray;
  finally
    VList.Free;
  end;
end;

{ TDfmUnitDocument }

constructor TDfmUnitDocument.Create(const pBytes: TBytes; const pFileName: string);
begin
  inherited Create(pBytes, pFileName);
  Tokenize;
end;

{ Moves pPos over a comment or directive that starts there. }
function TDfmUnitDocument.SkipComment(var pPos: Integer): Boolean;
var
  VTwo: string;
begin
  VTwo := Slice(pPos, if pPos + 1 < Length(Bytes) then pPos + 2 else pPos + 1);
  Result := VTwo.StartsWith('{') or (VTwo = '(*') or (VTwo = '//');
  if not Result then
    Exit;
  if VTwo = '//' then
    pPos := LineEnd(pPos)
  else if VTwo = '(*' then
  begin
    Inc(pPos, Length(VTwo));
    while (pPos + 1 < Length(Bytes)) and (Slice(pPos, pPos + 2) <> '*)') do
      Inc(pPos);
    Inc(pPos, Length(VTwo));
  end
  else
  begin
    while (pPos < Length(Bytes)) and (Bytes[pPos] <> Ord('}')) do
      Inc(pPos);
    Inc(pPos);
  end;
end;

{ IFDEF of the directive that starts at pStart; '' for a comment. }
function TDfmUnitDocument.DirectiveWord(pStart: Integer): string;
var
  VWord: Integer;
begin
  Result := '';
  VWord := pStart + (if Bytes[pStart] = Ord('{') then 1 else PAREN_COMMENT_LENGTH);
  if (Bytes[pStart] <> Ord('/')) and (VWord < Length(Bytes)) and (Bytes[VWord] = Ord(DIRECTIVE_MARK)) then
    Result := Slice(VWord + 1, SkipWord(VWord + 1));
end;
{ The conditional branches that are open at a position, one `start:branch` each. }
function TDfmUnitDocument.ConditionsAt(pPos: Integer): string;
var
  VComment: TDfmwToken;
  VOpen: TArray<string>;
begin
  VOpen := nil;
  for VComment in FConditionals do
    if VComment.Pos >= pPos then
      Break
    else if MatchText(VComment.Text, CONDITIONAL_OPENS) then
      VOpen := VOpen + [IntToStr(VComment.Pos)]
    else if Length(VOpen) = 0 then
      Continue
    else if MatchText(VComment.Text, CONDITIONAL_BRANCHES) then
      VOpen[High(VOpen)] := VOpen[High(VOpen)] + ':' + IntToStr(VComment.Pos)
    else if MatchText(VComment.Text, CONDITIONAL_CLOSES) then
      SetLength(VOpen, High(VOpen));
  Result := string.Join(' ', VOpen);
end;

{ True when a line at pPos is compiled whenever the class header and the end of its published section are. }
function TDfmUnitDocument.IsSafePlace(pHeader, pStop, pPos: Integer): Boolean;
var
  VComment: TDfmwToken;
  VHeader: string;
begin
  for VComment in FComments do
    if (VComment.Pos < pPos) and (pPos < VComment.Pos + VComment.Len) then
      Exit(False);
  VHeader := ConditionsAt(pHeader);
  Result := (ConditionsAt(pPos) = VHeader) and (ConditionsAt(pStop) = VHeader);
end;

{ The byte after the string literal at pPos (a multi-line literal starts with three or more quotes at a line end). }
function TDfmUnitDocument.SkipString(pPos: Integer): Integer;
var
  VQuotes: Integer;
begin
  VQuotes := 0;
  while (pPos + VQuotes < Length(Bytes)) and (Bytes[pPos + VQuotes] = QUOTE) do
    Inc(VQuotes);
  if (VQuotes >= MULTI_LINE_QUOTES) and Odd(VQuotes) and IsBlank(pPos + VQuotes, LineEnd(pPos)) then
  begin
    Result := LineEnd(pPos);
    while (Result < Length(Bytes)) and (not Slice(Result, LineEnd(Result)).TrimLeft.StartsWith(StringOfChar('''', VQuotes))) do
      Result := LineEnd(Result);
    while (Result < Length(Bytes)) and (Bytes[Result] <> QUOTE) do
      Inc(Result);
    Exit(Result + VQuotes);
  end;
  Result := pPos + 1;
  while (Result < Length(Bytes)) and (Bytes[Result] not in [QUOTE, LF, CR]) do
    Inc(Result);
  Inc(Result);
end;

{ The byte after the identifier or number at pPos, or after one symbol. }
function TDfmUnitDocument.SkipWord(pPos: Integer): Integer;
begin
  Result := pPos;
  while (Result < Length(Bytes)) and IsWordByte(Bytes[Result]) do
    Inc(Result);
  if Result = pPos then
    Inc(Result);
end;

procedure TDfmUnitDocument.Tokenize;
var
  VPos, VStart: Integer;
  VTokens, VComments: TList<TDfmwToken>;
  VToken: TDfmwToken;
begin
  VTokens := TList<TDfmwToken>.Create;
  VComments := TList<TDfmwToken>.Create;
  try
    VPos := BomLength;
    while VPos < Length(Bytes) do
    begin
      VStart := VPos;
      if Bytes[VPos] <= LAST_BLANK then
        Inc(VPos)
      else if SkipComment(VPos) then
      begin
        VToken.Pos := VStart;
        VToken.Len := VPos - VStart;
        VToken.Text := DirectiveWord(VStart);
        VComments.Add(VToken);
        if MatchText(VToken.Text, CONDITIONAL_OPENS) or MatchText(VToken.Text, CONDITIONAL_BRANCHES) or MatchText(VToken.Text, CONDITIONAL_CLOSES) then
          FConditionals := FConditionals + [VToken];
      end
      else
      begin
        VToken.Pos := VPos;
        VPos := if Bytes[VPos] = QUOTE then SkipString(VPos) else SkipWord(VPos);
        if VPos > Length(Bytes) then
          VPos := Length(Bytes);
        VToken.Len := VPos - VToken.Pos;
        VToken.Text := Slice(VToken.Pos, VPos);
        VTokens.Add(VToken);
      end;
    end;
    FTokens := VTokens.ToArray;
    FComments := VComments.ToArray;
  finally
    VComments.Free;
    VTokens.Free;
  end;
end;

{ Index of the `class` token of the class's full declaration, -1 = none. Raises for a second one. }
function TDfmUnitDocument.FindClassHeader(const pClass: string): Integer;
var
  VI: Integer;
begin
  Result := -1;
  for VI := 1 to High(FTokens) - 2 do
    if (FTokens[VI].Text = '=') and SameText(FTokens[VI - 1].Text, pClass) and SameText(FTokens[VI + 1].Text, 'class')
      and (FTokens[VI + 2].Text <> ';') then
    begin
      if Result >= 0 then
        Fail('class ' + pClass + ' is declared more than once (conditional compilation?)');
      Result := VI + 1;
    end;
end;

{ First token after `class`, `class(TForm, IFoo)` or `class sealed (...)`. }
function TDfmUnitDocument.AfterAncestors(pToken: Integer): Integer;
begin
  Result := pToken + 1;
  while (Result <= High(FTokens)) and MatchText(FTokens[Result].Text, ['sealed', 'abstract']) do
    Inc(Result);
  if (Result <= High(FTokens)) and (FTokens[Result].Text = '(') then
  begin
    while (Result <= High(FTokens)) and (FTokens[Result].Text <> ')') do
      Inc(Result);
    Inc(Result);
  end;
end;

{ One `A, B: TType;` at pToken; False at the end of the tokens. }
function TDfmUnitDocument.ReadDecl(var pToken: Integer; var pDecls: TArray<TDfmwDecl>): Boolean;
var
  VFirst, VColon, VI: Integer;
  VDecl: TDfmwDecl;
begin
  VFirst := pToken;
  while (pToken <= High(FTokens)) and (FTokens[pToken].Text <> ':') and (FTokens[pToken].Text <> ';') do
    Inc(pToken);
  VColon := pToken;  // dl:ok index-possibly-out-of-range@4f96 -- REVIEWED 2026-11-23 TT-DFMWRITE: the loop above bounds it: the routine exits when pToken is past High(FTokens), VColon is not above pToken
  VDecl := Default(TDfmwDecl);
  VDecl.Grouped := VColon > VFirst + 1;
  while (pToken <= High(FTokens)) and (FTokens[pToken].Text <> ';') do
    Inc(pToken);  // dl:ok index-possibly-out-of-range@8cb3 -- REVIEWED 2026-11-23 TT-DFMWRITE: the loop above bounds it: the routine exits when pToken is past High(FTokens), VColon is not above pToken
  Result := pToken <= High(FTokens);
  if not Result then
    Exit;
  VDecl.DeclClass := Slice(FTokens[VColon].Pos + 1, FTokens[pToken].Pos).Trim;
  VDecl.Start := FTokens[VFirst].Pos;
  VDecl.Finish := FTokens[pToken].Pos + 1;
  for VI := VFirst to VColon - 1 do
    if FTokens[VI].Text <> ',' then
    begin
      VDecl.Name := FTokens[VI].Text;
      pDecls := pDecls + [VDecl];
    end;
  Inc(pToken);
end;

{ The component declarations; pHeader = index of the `class` token, pStop = position of the first token after them. }
function TDfmUnitDocument.ReadSection(const pClass: string; out pHeader, pStop: Integer): TArray<TDfmwDecl>;
var
  VI: Integer;
begin
  Result := nil;
  pStop := Length(Bytes);
  pHeader := FindClassHeader(pClass);
  if pHeader < 0 then
    Fail('class ' + pClass + ' is not declared in the unit');
  VI := AfterAncestors(pHeader);
  if VI > High(FTokens) then
    Fail('class ' + pClass + ' is not complete');
  while (VI <= High(FTokens)) and (not MatchText(FTokens[VI].Text, MEMBER_STOPS)) do
    if SameText(FTokens[VI].Text, 'published') then
      Inc(VI)
    else if not ReadDecl(VI, Result) then
      Exit;
  if VI <= High(FTokens) then
    pStop := FTokens[VI].Pos;
end;

function TDfmUnitDocument.Declarations(const pClass: string): TArray<TDfmwDecl>;
var
  VHeader, VStop: Integer;
begin
  Result := ReadSection(pClass, VHeader, VStop);
end;

function TDfmUnitDocument.UsesAny(const pUnits: TArray<string>): Boolean;
var
  VToken: TDfmwToken;
  VNameStart: Integer;
begin
  Result := False;
  VNameStart := -1; // -1 = before the uses clause
  for VToken in FTokens do
    if SameText(VToken.Text, WORD_IMPLEMENTATION) then
      Exit
    else if VNameStart < 0 then
      VNameStart := if SameText(VToken.Text, 'uses') then VToken.Pos + VToken.Len else -1
    else if (VToken.Text = ',') or (VToken.Text = ';') then
    begin
      Result := MatchText(Slice(VNameStart, VToken.Pos).Trim, pUnits);
      if Result or (VToken.Text = ';') then
        Exit;
      VNameStart := VToken.Pos + VToken.Len;
    end;
end;

function TDfmUnitDocument.NamesInString(const pName: string): Boolean;
var
  VToken: TDfmwToken;
  VEntry: string;
begin
  Result := False;
  for VToken in FTokens do
    if VToken.Text.StartsWith('''') then
      for VEntry in VToken.Text.DeQuotedString.Split([';']) do
        if SameText(Trim(VEntry), pName) then
          Exit(True);
end;

function TDfmUnitDocument.Mentions(const pText: string): Integer;
var
  VToken: TDfmwToken;
begin
  Result := 0;
  for VToken in FTokens do
    if SameText(VToken.Text, pText) then
      Inc(Result);
end;

{ Raises when other code is on the lines of pStart..pFinish; a comment after it may be. }
procedure TDfmUnitDocument.CheckLineOfItsOwn(pStart, pFinish: Integer; const pName: string);
var
  VToken: TDfmwToken;
begin
  for VToken in FTokens do
    if ((VToken.Pos >= pFinish) and (VToken.Pos < LineEnd(pFinish))) or ((VToken.Pos < pStart) and (VToken.Pos >= LineStart(pStart))) then
      Fail('the declaration before ' + pName + ' shares its line with other code');
  if EolAt(pFinish) = '' then
    Fail('the declaration before ' + pName + ' is on a line without a line end');
end;

procedure TDfmUnitDocument.AddField(const pClass, pName, pFieldClass: string; const pAfter: TArray<string>);
var
  VDecls: TArray<TDfmwDecl>;
  VI, VPass, VHeader, VStop, VStart, VFinish: Integer;
  VIndent: string;
begin
  VDecls := ReadSection(pClass, VHeader, VStop);
  { the class header, when no declaration is a safe neighbour }
  VStart := FTokens[VHeader - 2].Pos;
  VI := AfterAncestors(VHeader) - 1;  // dl:ok index-possibly-out-of-range@d63d -- REVIEWED 2026-11-23 DFMWFIX: ReadSection raises when AfterAncestors is past the last token
  VFinish := FTokens[VI].Pos + FTokens[VI].Len;
  VIndent := if Length(VDecls) = 0 then IndentAt(VStart) + STEP else IndentAt(VDecls[0].Start);
  { the last named declaration wins over the last of all }
  for VPass := 0 to 1 do
    for VI := 0 to High(VDecls) do
      if ((VPass = 0) or MatchText(VDecls[VI].Name, pAfter)) and IsSafePlace(FTokens[VHeader].Pos, VStop, LineEnd(VDecls[VI].Finish)) then
      begin
        VStart := VDecls[VI].Start;
        VFinish := VDecls[VI].Finish;
        VIndent := IndentAt(VStart);
      end;
  if not IsSafePlace(FTokens[VHeader].Pos, VStop, LineEnd(VFinish)) then
    Fail('no place to declare ' + pName + ' that is outside a conditional ($IF..$ENDIF) or comment of ' + pClass);
  CheckLineOfItsOwn(VStart, VFinish, pName);
  Edit(LineEnd(VFinish), 0, VIndent + pName + ': ' + pFieldClass + ';' + EolAt(VFinish));
end;
procedure TDfmUnitDocument.RemoveField(const pClass, pName: string);
var
  VDecls: TArray<TDfmwDecl>;
  VIdx, VStart: Integer;
begin
  VDecls := Declarations(pClass);
  VIdx := IndexOfDecl(VDecls, pName);
  if VIdx < 0 then
    Exit;
  if VDecls[VIdx].Grouped then
    Fail('the declaration of ' + pName + ' shares its type with other fields');
  CheckWholeLine(VDecls[VIdx].Start, VDecls[VIdx].Finish, 'the declaration of ' + pName);
  VStart := LineStart(VDecls[VIdx].Start);
  Edit(VStart, LineEnd(VDecls[VIdx].Finish) - VStart, '');
end;

end.
