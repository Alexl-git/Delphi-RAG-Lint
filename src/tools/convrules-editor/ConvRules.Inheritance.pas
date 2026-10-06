unit ConvRules.Inheritance;

{ C8 (spec 2026-10-05-c8-inherited-instances-design.md), editor half: which objects
  in a unit's .dfm are INHERITED / INLINE instances of a checked book's From type,
  which ancestor declares each one and whether that ancestor is converted, and the
  Convert tab's texts and list edits that follow. Pure: the project index and the
  file system come in as function references, so ConvRulesModelTests pins every
  rule with fixture text and a fake index. }

interface

uses
  System.SysUtils
  ;

const
  /// <summary>The .dfm beside a unit's .pas.</summary>
  DFM_EXT = '.dfm';
  /// <summary>The first four bytes of a BINARY .dfm; such a file has no text to scan.</summary>
  BINARY_DFM_SIGNATURE = 'TPF0';

type
  /// <summary>The keyword that opens a .dfm block.</summary>
  TDfmOpener = (doObject, doInherited, doInline);

  /// <summary>One #convert block of a checked book, bare class names ('TLabel', not
  /// 'Vcl.StdCtrls.TLabel').</summary>
  TTypePair = record
    /// <summary>The block's From type.</summary>
    FromType: string;
    /// <summary>The block's To type; '' for a From-only stub.</summary>
    ToType  : string;
  end;

  /// <summary>One object a .dfm opens with `inherited` or `inline` (spec E1).</summary>
  TInheritedInstance = record
    /// <summary>The instance name ('tblFtrs').</summary>
    Name      : string;
    /// <summary>The class as written in the .dfm, without a '[n]' suffix.</summary>
    TypeName  : string;
    /// <summary>1-based .dfm line of the header.</summary>
    Line      : Integer;
    /// <summary>doInherited or doInline.</summary>
    Opener    : TDfmOpener;
    /// <summary>The class of the innermost ENCLOSING `inline` block; '' when the
    /// object belongs to the form (or data module) itself.</summary>
    FrameClass: string;
    /// <summary>The class of the immediately enclosing block; '' for a top-level object
    /// (a direct child of the root) -- ResolveInstance's frame fallback keys on it.</summary>
    ParentType: string;
  end;

  /// <summary>What one .dfm says about inheritance.</summary>
  TDfmInheritance = record
    /// <summary>The root block's class; '' when the text has no header.</summary>
    RootClass: string;
    /// <summary>True for a binary .dfm: nothing was scanned.</summary>
    IsBinary : Boolean;
    /// <summary>Every inherited / inline object below the root, in file order.</summary>
    Instances: TArray<TInheritedInstance>;
  end;

/// <summary>PURE: lists the inherited / inline objects of a text .dfm.</summary>
/// <param name="AText">The whole .dfm as text.</param>
/// <returns>RootClass and the instances; IsBinary and no instances for a binary
/// .dfm; an empty record for '' or text with no header.</returns>
/// <remarks>Depth-tracked header walk (ParseBlockHeader is the one header parser).
/// A property value opening '<', '(' or '{' is skipped to its balanced terminator,
/// judged on StripQuoted text, so a collection's item/end never closes a component
/// and a quoted '>' never ends a list. A value starts a skip only on a line whose left
/// of '=' is a property name (IsPropName), so a string continuation line holding '='
/// and '(' never does. Anonymous blocks are not listed.</remarks>
function ScanDfmInheritance(const AText: string): TDfmInheritance;  // dl:ok unused-public-symbol@5b6d -- REVIEWED 2026-10-05 called by the model tests (inherit.*) only until the C8 Convert-tab tasks wire it into the editor; drop this marker when they do

/// <summary>PURE: how a .dfm opens the object named AName, at any depth, OUTSIDE
/// every inline block (a frame's children belong to the frame's own .dfm).</summary>
/// <param name="AText">The whole .dfm as text.</param>
/// <param name="AName">Instance name, matched case-insensitively.</param>
/// <param name="AOpener">Receives the opener of the first match.</param>
/// <param name="ATypeName">Receives the class of the first match.</param>
/// <returns>False when the .dfm does not open AName (or is binary).</returns>
function FindDfmObject(const AText, AName: string; out AOpener: TDfmOpener; out ATypeName: string): Boolean;  // dl:ok unused-public-symbol@8bcd -- REVIEWED 2026-10-05 called by the model tests (inherit.*) only until the C8 Convert-tab tasks wire it into the editor; drop this marker when they do

/// <summary>PURE: the last dotted segment of a class name ('Vcl.StdCtrls.TLabel' -> 'TLabel').</summary>
/// <param name="AType">A bare or unit-qualified class name.</param>
/// <returns>The bare name; '' for ''.</returns>
function BareType(const AType: string): string;

/// <summary>PURE: the #convert pairs of a rule book, bare names, book order.</summary>
/// <param name="ARulesText">The .rules text.</param>
/// <returns>One pair per #convert header that names a From type.</returns>
function TypePairsOfText(const ARulesText: string): TArray<TTypePair>;  // dl:ok unused-public-symbol@e472 -- REVIEWED 2026-10-05 called by the model tests (inherit.*) only until the C8 Convert-tab tasks wire it into the editor; drop this marker when they do

/// <summary>PURE: True when AType (bare or qualified) is the From type of one of APairs.</summary>
/// <param name="AType">A class name from a .dfm.</param>
/// <param name="APairs">The checked books' pairs.</param>
/// <returns>Case-insensitive match on the bare names.</returns>
function IsFromType(const AType: string; const APairs: TArray<TTypePair>): Boolean;  // dl:ok unused-public-symbol@d9ad -- REVIEWED 2026-10-05 called by the model tests (inherit.*) only until the C8 Convert-tab tasks wire it into the editor; drop this marker when they do

implementation

uses
  System.Generics.Collections
  , ConvRules.BlockFile
  , ConvRules.Model
  , ConvRules.Usage
  ;

const
  KW_END       = 'end';
  KW_INLINE    = 'inline';
  KW_INHERITED = 'inherited';
  OPEN_LIST    = '<';
  CLOSE_LIST   = '>';
  OPEN_PARENS  = '(';
  CLOSE_PARENS = ')';
  OPEN_BLOB    = '{';
  CLOSE_BLOB   = '}';
  NO_CHAR      = #0;

type
  // One block header as the walk meets it.
  THeader = record
    Line      : Integer;
    Opener    : TDfmOpener;
    Name      : string;
    TypeName  : string;
    Depth     : Integer; // 0 = the root
    FrameClass: string;  // innermost enclosing inline block's class; '' when none
    ParentType: string;  // immediately enclosing block's class; '' for the root
  end;
  THeaderProc = reference to procedure(const AHeader: THeader);

function OpenerOf(const AKeyword: string): TDfmOpener;
begin
  if SameText(AKeyword, KW_INLINE) then
    Result:= doInline
  else if SameText(AKeyword, KW_INHERITED) then
    Result:= doInherited
  else
    Result:= doObject;
end;

function CloserOf(AOpen: Char): Char;
begin
  case AOpen of
    OPEN_LIST  : Result:= CLOSE_LIST;
    OPEN_PARENS: Result:= CLOSE_PARENS;
    OPEN_BLOB  : Result:= CLOSE_BLOB;
    else         Result:= NO_CHAR;
  end; // case
end;

function CountOf(const AText: string; AChar: Char): Integer;
begin
  Result:= 0;
  for var LCh: Char in AText do
    if LCh = AChar then
      Inc(Result);
end;

// Calls AOnHeader for every block header of a text .dfm, in file order.
procedure WalkDfmHeaders(const AText: string; const AOnHeader: THeaderProc);
var
  Lines    : TArray<TRawLine>;
  Stack    : TList<THeader>; // the open blocks, innermost last
  Cur      : string;
  Val      : string;
  Cls      : string;
  Inst     : string;
  H        : THeader;
  SkipOpen : Char;
  SkipClose: Char;
  SkipDepth: Integer;
  EqPos    : Integer;
begin
  Lines:= SplitRawLines(AText);
  Stack:= TList<THeader>.Create;
  try
    SkipOpen := NO_CHAR;
    SkipClose:= NO_CHAR;
    SkipDepth:= 0;
    for var I: Integer:= 0 to High(Lines) do
    begin
      Cur:= Trim(Lines[I].Text);
      if Cur = '' then
        Continue;
      if SkipDepth > 0 then
      begin
        Val:= StripQuoted(Cur);
        SkipDepth:= SkipDepth + CountOf(Val, SkipOpen) - CountOf(Val, SkipClose);
        Continue;
      end;
      if ParseBlockHeader(Cur, Cls, Inst) then
      begin
        H:= Default(THeader);
        H.Line    := I + 1;
        H.Opener  := OpenerOf(FirstToken(Cur));
        H.Name    := Inst;
        H.TypeName:= Cls;
        H.Depth   := Stack.Count;
        if Stack.Count > 0 then
        begin
          H.ParentType:= Stack.Last.TypeName;
          H.FrameClass:= if Stack.Last.Opener = doInline then Stack.Last.TypeName else Stack.Last.FrameClass;
        end;
        AOnHeader(H);
        Stack.Add(H);
        Continue;
      end;
      if SameText(FirstToken(Cur), KW_END) then
      begin
        if Stack.Count > 0 then
          Stack.Delete(Stack.Count - 1);
        Continue;
      end;
      // Judged on the quote-stripped line, and only when the left of '=' is a property
      // name: a string continuation line ('abc = (def' +) is no assignment and must not
      // open a list skip that would swallow every header after it.
      Val:= StripQuoted(Cur);
      EqPos:= Pos('=', Val);
      if (EqPos = 0) or not IsPropName(Trim(Copy(Val, 1, EqPos - 1))) then
        Continue;
      Val:= Trim(Copy(Val, EqPos + 1, MaxInt));
      if Val = '' then
        Continue;
      SkipOpen := Val[1];
      SkipClose:= CloserOf(SkipOpen);
      if SkipClose = NO_CHAR then
        Continue;
      SkipDepth:= CountOf(Val, SkipOpen) - CountOf(Val, SkipClose);
    end; // for
  finally
    Stack.Free;
  end; // try
end;

function ScanDfmInheritance(const AText: string): TDfmInheritance;
var
  LScan: TDfmInheritance;
begin
  LScan:= Default(TDfmInheritance);
  if AText.StartsWith(BINARY_DFM_SIGNATURE) then
  begin
    LScan.IsBinary:= True;
    Exit(LScan);
  end;
  WalkDfmHeaders(AText,
    procedure(const AHeader: THeader)
    var
      LItem: TInheritedInstance;
    begin
      if AHeader.Depth = 0 then
      begin
        if LScan.RootClass = '' then
          LScan.RootClass:= AHeader.TypeName;
        Exit;
      end;
      if (AHeader.Opener = doObject) or (AHeader.Name = '') then
        Exit;
      LItem:= Default(TInheritedInstance);
      LItem.Name      := AHeader.Name;
      LItem.TypeName  := AHeader.TypeName;
      LItem.Line      := AHeader.Line;
      LItem.Opener    := AHeader.Opener;
      LItem.FrameClass:= AHeader.FrameClass;
      LItem.ParentType:= if AHeader.Depth = 1 then '' else AHeader.ParentType;
      LScan.Instances := LScan.Instances + [LItem];
    end);
  Result:= LScan;
end;

function FindDfmObject(const AText, AName: string; out AOpener: TDfmOpener; out ATypeName: string): Boolean;
var
  LFound : Boolean;
  LOpener: TDfmOpener;
  LType  : string;
begin
  LFound := False;
  LOpener:= doObject;
  LType  := '';
  if not AText.StartsWith(BINARY_DFM_SIGNATURE) then
    WalkDfmHeaders(AText,
      procedure(const AHeader: THeader)
      begin
        if LFound or (AHeader.Depth = 0) or (AHeader.FrameClass <> '') or not SameText(AHeader.Name, AName) then
          Exit;
        LFound := True;
        LOpener:= AHeader.Opener;
        LType  := AHeader.TypeName;
      end);
  AOpener  := LOpener;
  ATypeName:= LType;
  Result   := LFound;
end;

function BareType(const AType: string): string;
var
  LDot: Integer;
begin
  LDot:= AType.LastIndexOf('.');
  Result:= if LDot < 0 then AType else AType.Substring(LDot + 1);
end;

function TypePairsOfText(const ARulesText: string): TArray<TTypePair>;
var
  Book: TRuleBook;
  Pair: TTypePair;
begin
  Result:= nil;
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString(ARulesText);
    for var LIdx: Integer in Book.ConvertHeaders do
    begin
      Pair.FromType:= BareType(Trim(Book.Nodes[LIdx].FromType));
      Pair.ToType  := BareType(Trim(Book.Nodes[LIdx].ToType));
      if Pair.FromType <> '' then
        Result:= Result + [Pair];
    end;
  finally
    Book.Free;
  end; // try
end;

function IsFromType(const AType: string; const APairs: TArray<TTypePair>): Boolean;
begin
  for var LPair: TTypePair in APairs do
    if SameText(BareType(AType), LPair.FromType) then
      Exit(True);
  Result:= False;
end;

end.
