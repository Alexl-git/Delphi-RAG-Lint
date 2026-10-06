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
  , System.Generics.Collections
  ;

const
  /// <summary>The .dfm beside a unit's .pas.</summary>
  DFM_EXT = '.dfm';
  /// <summary>The first four bytes of a BINARY .dfm; such a file has no text to scan.</summary>
  BINARY_DFM_SIGNATURE = 'TPF0';
  /// <summary>Longest ancestor chain the walk follows; a cycle stops earlier.</summary>
  MAX_CHAIN_DEPTH = 32;
  /// <summary>TInstanceVerdict.DeclaringUnit of an asOutside verdict whose chain named
  /// no ancestor class at all (the unit's own class records none). Not a class name:
  /// OutsideNote words this case without it.</summary>
  OUTSIDE_NO_ANCESTOR = '(no ancestor class)';

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

  /// <summary>What the project index says about one class.</summary>
  TClassInfo = record
    /// <summary>Exactly one unit of the project index declares the class.</summary>
    Found      : Boolean;
    /// <summary>The index could not be asked (engine failure); unknown, not absent.</summary>
    Failed     : Boolean;
    /// <summary>The declaring unit's .pas (full path); '' unless Found.</summary>
    PasPath    : string;
    /// <summary>The class's first ancestor as written ('TDataModule'); '' when none.</summary>
    ParentClass: string;
  end;

  /// <summary>Asks the project index about a class (TEngineAdapter.LookupClass in the
  /// editor, a fake in the tests).</summary>
  TClassLookup = reference to function(const AClassName: string): TClassInfo;

  /// <summary>Reads a text file; False when it does not exist or cannot be read.</summary>
  TDfmTextReader = reference to function(const APath: string; out AText: string): Boolean;

  /// <summary>The declaring ancestor's state for one inherited instance (spec Terms).</summary>
  /// <remarks>asUnconverted: the ancestor's object still has the instance's (From)
  /// type. asConverted: the declaring object's type is no longer the From type (the
  /// block's To type, normally). asOutside: the chain left the project index (a
  /// library ancestor, or an ambiguous class) before any .dfm opened the object with
  /// `object`.</remarks>
  TAncestorState = (asUnconverted, asConverted, asOutside);

  /// <summary>One ancestor unit whose .dfm opens an instance with the From type.</summary>
  TChainUnit = record
    /// <summary>The ancestor's .pas.</summary>
    PasPath: string;
    /// <summary>1 = the walk's first class; larger = further up the chain.</summary>
    Depth  : Integer;
  end;

  /// <summary>The verdict on one inherited instance.</summary>
  TInstanceVerdict = record
    /// <summary>The instance as scanned.</summary>
    Instance     : TInheritedInstance;
    /// <summary>The declaring ancestor's state.</summary>
    State        : TAncestorState;
    /// <summary>The declaring unit's name ('Base'); for asOutside the class where the
    /// chain left the index ('TDataModule'), or OUTSIDE_NO_ANCESTOR when the chain
    /// named no ancestor class at all.</summary>
    DeclaringUnit: string;
    /// <summary>The declaring unit's .pas; '' for asOutside.</summary>
    DeclaringPas : string;
    /// <summary>Every ancestor unit (declaring or intermediate) whose .dfm still opens
    /// the instance with the From type -- the units to convert first.</summary>
    Chain        : TArray<TChainUnit>;
  end;

  /// <summary>One listed unit's C8 analysis.</summary>
  TUnitInheritance = record
    /// <summary>The listed .pas.</summary>
    UnitPas : string;
    /// <summary>False = nothing to say: no checked From type, no (text) .dfm, the
    /// unit's own class not in the index, or the index could not answer.</summary>
    Known   : Boolean;
    /// <summary>'' or why the index could not answer (Known is then False).</summary>
    Error   : string;
    /// <summary>One verdict per inherited instance of a checked From type.</summary>
    Verdicts: TArray<TInstanceVerdict>;
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
function ScanDfmInheritance(const AText: string): TDfmInheritance;

/// <summary>PURE: how a .dfm opens the object named AName, at any depth, OUTSIDE
/// every inline block (a frame's children belong to the frame's own .dfm).</summary>
/// <param name="AText">The whole .dfm as text.</param>
/// <param name="AName">Instance name, matched case-insensitively.</param>
/// <param name="AOpener">Receives the opener of the first match.</param>
/// <param name="ATypeName">Receives the class of the first match.</param>
/// <returns>False when the .dfm does not open AName (or is binary).</returns>
function FindDfmObject(const AText, AName: string; out AOpener: TDfmOpener; out ATypeName: string): Boolean;

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
function IsFromType(const AType: string; const APairs: TArray<TTypePair>): Boolean;

/// <summary>PURE: a unit's name from its path ('C:\x\PathToData.pas' -> 'PathToData').</summary>
/// <param name="APasPath">A .pas path.</param>
/// <returns>The file name without its extension.</returns>
function UnitNameOf(const APasPath: string): string;

/// <summary>PURE: walks one instance's ancestor chain to its declaring ancestor (spec E2).</summary>
/// <param name="AInst">The instance.</param>
/// <param name="AStartClass">The first class whose .dfm is read: the form's PARENT
/// class for a form-owned instance, the frame class itself for a frame child.</param>
/// <param name="ALookup">The project index.</param>
/// <param name="AReader">The file system.</param>
/// <returns>The verdict. When the form chain does not declare the instance and it sits
/// in an inherited block, the block's own class is walked next (a frame placed on an
/// ancestor form). A lookup that Failed yields asOutside with DeclaringUnit '' -- the
/// caller (AnalyzeUnit) turns that into Known = False, never into a report.</returns>
function ResolveInstance(const AInst: TInheritedInstance; const AStartClass: string; const ALookup: TClassLookup; const AReader: TDfmTextReader): TInstanceVerdict;

/// <summary>PURE: the C8 analysis of one listed unit (spec E1-E3).</summary>
/// <param name="AUnitPas">The listed .pas; its .dfm is ChangeFileExt(AUnitPas, DFM_EXT).</param>
/// <param name="APairs">The checked books' pairs; empty = nothing is recorded (E3).</param>
/// <param name="ALookup">The project index.</param>
/// <param name="AReader">The file system.</param>
/// <returns>Known = False when there is nothing to say (see TUnitInheritance.Known);
/// otherwise one verdict per `inherited` instance whose class is a From type. `inline`
/// instances are the unit's OWN frames and are not verdicts; their children are.</returns>
function AnalyzeUnit(const AUnitPas: string; const APairs: TArray<TTypePair>; const ALookup: TClassLookup; const AReader: TDfmTextReader): TUnitInheritance;  // dl:ok unused-public-symbol@fe67 -- REVIEWED 2026-10-05 called by the model tests (inherit.walk.*) only until the C8 Convert-tab tasks wire it into the editor; drop this marker when they do

/// <summary>PURE: the spec E8 note for one asOutside verdict.</summary>
/// <param name="AVerdict">A verdict from ResolveInstance / AnalyzeUnit.</param>
/// <returns>'' unless AVerdict.State = asOutside; 'inherits from &lt;Class&gt;, which is
/// not in this project's index -- convert it from its own project' when the chain left
/// the index at a named class; 'inherits &lt;Instance&gt; from an ancestor that is not in
/// this project's index -- convert it from its own project' when it named no ancestor
/// class at all (DeclaringUnit = OUTSIDE_NO_ANCESTOR).</returns>
function OutsideNote(const AVerdict: TInstanceVerdict): string;  // dl:ok unused-public-symbol@a346 -- REVIEWED 2026-10-05 called by the model tests (inherit.note.*) only until the C8 row-note task wires it into the editor; drop this marker when it does

/// <summary>Wraps ALookup with a per-class cache (key: the upper-cased class name).</summary>
/// <param name="AInner">The real lookup.</param>
/// <param name="ACache">Owned by the caller; clear it whenever the index changes.</param>
/// <returns>A lookup that asks AInner once per class; a Failed answer is NOT cached.</returns>
function CachingLookup(const AInner: TClassLookup; ACache: TDictionary<string, TClassInfo>): TClassLookup;  // dl:ok unused-public-symbol@867b -- REVIEWED 2026-10-05 called by the model tests (inherit.cache.*) only until the C8 Convert-tab tasks wire it into the editor; drop this marker when they do

/// <summary>A TDfmTextReader over the real file system (TFile.ReadAllText).</summary>
/// <returns>A reader that answers False for a missing or unreadable file.</returns>
function DiskTextReader: TDfmTextReader;  // dl:ok unused-public-symbol@8af4 -- REVIEWED 2026-10-05 wired into the editor by the C8 Convert-tab tasks; drop this marker when they do

implementation

uses
  System.IOUtils
  , System.StrUtils
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
  NOTE_OUTSIDE = 'inherits from %s, which is not in this project''s index -- convert it from its own project';
  NOTE_OUTSIDE_NO_ANCESTOR = 'inherits %s from an ancestor that is not in this project''s index -- convert it from its own project';

type
  // How one WalkChain ended.
  TWalkEnd = (weDeclared, weLeftIndex, weNotFound, weFailed);

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

function UnitNameOf(const APasPath: string): string;
begin
  Result:= ChangeFileExt(ExtractFileName(APasPath), '');
end;

function ChainUnitOf(const APasPath: string; ADepth: Integer): TChainUnit;
begin
  Result.PasPath:= APasPath;
  Result.Depth  := ADepth;
end;

// How APasPath's .dfm opens AName; False when it has no text .dfm or does not open it.
function DfmOpens(const APasPath, AName: string; const AReader: TDfmTextReader; out AOpener: TDfmOpener; out AType: string): Boolean;
var
  LText: string;
begin
  AOpener:= doObject;
  AType  := '';
  Result := AReader(ChangeFileExt(APasPath, DFM_EXT), LText) and FindDfmObject(LText, AName, AOpener, AType);
end;

// Follows the class chain from AStartClass until a .dfm opens AInst with `object`
// (weDeclared, AVerdict filled), a class is not in the index (weLeftIndex), the
// index cannot answer (weFailed), or the chain ends / cycles / runs past
// MAX_CHAIN_DEPTH (weNotFound). ALastClass is the last class asked about.
function WalkChain(const AInst: TInheritedInstance; const AStartClass: string; const ALookup: TClassLookup;
  const AReader: TDfmTextReader; out AVerdict: TInstanceVerdict; out ALastClass: string): TWalkEnd;
var
  Cls    : string;
  Info   : TClassInfo;
  Seen   : TArray<string>;
  Opener : TDfmOpener;
  ObjType: string;
  Depth  : Integer;
  Same   : Boolean;
begin
  AVerdict:= Default(TInstanceVerdict);
  AVerdict.Instance:= AInst;
  ALastClass:= '';
  Cls  := AStartClass;
  Depth:= 0;
  Seen := nil;
  while (Cls <> '') and (Depth < MAX_CHAIN_DEPTH) and not MatchText(Cls, Seen) do
  begin
    Seen      := Seen + [Cls];
    ALastClass:= Cls;
    Inc(Depth);
    Info:= ALookup(Cls);
    if Info.Failed then
      Exit(weFailed);
    if not Info.Found then
      Exit(weLeftIndex);
    if DfmOpens(Info.PasPath, AInst.Name, AReader, Opener, ObjType) then
    begin
      Same:= SameText(BareType(ObjType), BareType(AInst.TypeName));
      if Same then
        AVerdict.Chain:= AVerdict.Chain + [ChainUnitOf(Info.PasPath, Depth)];
      if Opener = doObject then
      begin
        AVerdict.DeclaringPas := Info.PasPath;
        AVerdict.DeclaringUnit:= UnitNameOf(Info.PasPath);
        AVerdict.State        := if Same then asUnconverted else asConverted;
        Exit(weDeclared);
      end;
    end;
    Cls:= Info.ParentClass;
  end;
  Result:= weNotFound;
end;

function ResolveInstance(const AInst: TInheritedInstance; const AStartClass: string; const ALookup: TClassLookup; const AReader: TDfmTextReader): TInstanceVerdict;
var
  LEnd     : TWalkEnd;
  LLast    : string;
  LFallback: TInstanceVerdict;
  LIgnored : string;
begin
  LEnd:= WalkChain(AInst, AStartClass, ALookup, AReader, Result, LLast);
  if LEnd = weDeclared then
    Exit;
  if LEnd <> weFailed then
  begin
    // A child of an inherited FRAME is declared in the frame's own .dfm, which the
    // form chain never reads (FindDfmObject skips inline blocks).
    LEnd:= if AInst.ParentType = '' then weNotFound else WalkChain(AInst, AInst.ParentType, ALookup, AReader, LFallback, LIgnored);
    if LEnd = weDeclared then
      Exit(LFallback);
  end;
  Result.Chain        := nil;
  Result.State        := asOutside;
  Result.DeclaringPas := '';
  // weFailed: DeclaringUnit '' tells AnalyzeUnit the index did not answer.
  if LEnd = weFailed then
    Result.DeclaringUnit:= ''
  else
    Result.DeclaringUnit:= if LLast <> '' then LLast else OUTSIDE_NO_ANCESTOR;
end;

function AnalyzeUnit(const AUnitPas: string; const APairs: TArray<TTypePair>; const ALookup: TClassLookup; const AReader: TDfmTextReader): TUnitInheritance;
var
  LText   : string;
  LScan   : TDfmInheritance;
  LOwn    : TClassInfo;
  LStart  : string;
  LVerdict: TInstanceVerdict;
  LWanted : TArray<TInheritedInstance>;
begin
  Result:= Default(TUnitInheritance);
  Result.UnitPas:= AUnitPas;
  // E3: no checked From type, no .dfm, a binary .dfm or no header -- nothing to say.
  if (Length(APairs) > 0) and AReader(ChangeFileExt(AUnitPas, DFM_EXT), LText) then
    LScan:= ScanDfmInheritance(LText)
  else
    LScan:= Default(TDfmInheritance);
  if LScan.IsBinary or (LScan.RootClass = '') then
    Exit;
  LWanted:= nil;
  for var LInst: TInheritedInstance in LScan.Instances do
    if (LInst.Opener = doInherited) and IsFromType(LInst.TypeName, APairs) then
      LWanted:= LWanted + [LInst];
  if Length(LWanted) = 0 then
  begin
    Result.Known:= True; // E3: known, and nothing to record
    Exit;
  end;
  LOwn:= ALookup(LScan.RootClass);
  if LOwn.Failed then
  begin
    Result.Error:= 'the project index could not be asked about ' + LScan.RootClass;
    Exit;
  end;
  if not LOwn.Found then
    Exit; // the unit itself is not indexed: its row already says so
  for var LInst: TInheritedInstance in LWanted do
  begin
    LStart  := if LInst.FrameClass <> '' then LInst.FrameClass else LOwn.ParentClass;
    LVerdict:= ResolveInstance(LInst, LStart, ALookup, AReader);
    if (LVerdict.State = asOutside) and (LVerdict.DeclaringUnit = '') then
    begin
      Result.Error   := 'the project index could not be asked about the ancestors of ' + LScan.RootClass;
      Result.Verdicts:= nil;
      Exit; // unknown is never reported as outside
    end;
    Result.Verdicts:= Result.Verdicts + [LVerdict];
  end;
  Result.Known:= True;
end;

function OutsideNote(const AVerdict: TInstanceVerdict): string;
begin
  if AVerdict.State <> asOutside then
    Result:= ''
  else if AVerdict.DeclaringUnit = OUTSIDE_NO_ANCESTOR then
    Result:= Format(NOTE_OUTSIDE_NO_ANCESTOR, [AVerdict.Instance.Name])
  else
    Result:= Format(NOTE_OUTSIDE, [AVerdict.DeclaringUnit]);
end;

function CachingLookup(const AInner: TClassLookup; ACache: TDictionary<string, TClassInfo>): TClassLookup;
begin
  Result:= function(const AClassName: string): TClassInfo
    begin
      if ACache.TryGetValue(UpperCase(AClassName), Result) then
        Exit;
      Result:= AInner(AClassName);
      if not Result.Failed then
        ACache.AddOrSetValue(UpperCase(AClassName), Result);
    end;
end;

function DiskTextReader: TDfmTextReader;
begin
  Result:= function(const APath: string; out AText: string): Boolean
    begin
      AText := '';
      Result:= TFile.Exists(APath);
      if not Result then
        Exit;
      try
        AText:= TFile.ReadAllText(APath);
      except  // an unreadable .dfm reads as "no .dfm" (spec E3: show nothing); the analysis runs on drops and must never raise
        on Exception do
          Result:= False;
      end; // try
    end;
end;

end.
