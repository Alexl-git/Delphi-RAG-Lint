unit ConvRules.Model;

{ Loss-less in-memory model of a drag-lint conversion.rules DSL file.

  The DSL (see docs/CONVERSION-RULES.md) is a line-oriented, reFind-superset
  format. This model parses a file into an ORDERED list of typed nodes -- one per
  physical line -- so it can re-emit the file byte-faithfully except where the
  user edited. Every directive the grammar defines is represented; unknown lines
  are kept verbatim as rnkUnknown so nothing is ever silently dropped.

  Pure and headless: no UI, no file I/O beyond LoadFromString/SaveToString. The
  editor's correctness lives here, so this unit is the DUnitX spec target. }

interface

uses
  System.SysUtils
  , System.Classes
  , System.Generics.Collections
  ;

type
  /// <summary>Kind of one parsed DSL line.</summary>
  TRuleNodeKind = (
    rnkBlank,      // empty / whitespace-only line
    rnkComment,    // '//' or ';' comment line
    rnkConvert,    // #convert From -> To [, unit ...]
    rnkLink,       // #link ToPath <- FromPath [: CastFn]
    rnkDefault,    // #default ToPath = value
    rnkIgnore,     // #ignore FromPath
    rnkRemove,     // #remove property   OR   #remove DFM: property
    rnkUnuse,      // #unuse unit
    rnkUse,        // #use unit  (add a unit to the uses clause)
    rnkUseSwap,    // #useswap Old -> New1[, New2 ...]  (replace a unit)
    rnkMigrate,    // #migrate [Class:][obj.]old -> new [, unit ...]
    rnkNote,       // #note text
    rnkPcre,       // raw <pcre> -> <pcre> escape-hatch line
    rnkMapping,    // #mapping Name from Type to Classes  |  #mapping Name #when/#else -> sets
    rnkApply,      // #apply Name  (pull a #mapping into this #convert block)
    rnkUnknown     // anything else (kept verbatim, never dropped)
  );

  /// <summary>One 'ToPath = Value' assignment from a #mapping clause's set list.</summary>
  /// <remarks>ToPath keeps its dots intact ('Style.ModalResult.Default' stays one path,
  /// it is never split into segments). Value is the verbatim right-hand text with the
  /// surrounding whitespace trimmed; the model does not interpret or type-check it.</remarks>
  TSetPair = record
    /// <summary>Target property path on the converted component (dots preserved).</summary>
    ToPath: string;
    /// <summary>Right-hand value text, trimmed but otherwise verbatim.</summary>
    Value : string;
  end;

  /// <summary>One parsed DSL line. Raw is the verbatim source (minus EOL); the
  /// typed fields carry the parsed parts for the kinds that have them. Emit()
  /// re-serializes from the typed fields when Dirty, else returns Raw unchanged
  /// (byte-faithful round-trip for untouched lines).</summary>
  TRuleNode = class
  public
    Kind : TRuleNodeKind;
    Raw  : string       ;  // verbatim original line (no trailing CR/LF)
    Dirty: Boolean      ;  // set when a typed field was edited -> re-emit from fields

    // rnkConvert
    FromType: string;
    ToType  : string;
    Units   : string;      // comma-joined uses-add list ('' if none)

    // rnkLink
    LinkTo  : string;      // ToPath
    LinkFrom: string;      // FromPath  (may be '???' stub)
    Cast    : string;      // optional CastFn ('' = identity)

    // rnkDefault
    DefTo   : string;      // ToPath
    DefValue: string;      // right-hand value (may be '???')

    // rnkIgnore
    IgnorePath: string;    // FromPath

    // rnkRemove
    RemoveProp  : string;
    RemoveDfmOnly: Boolean; // '#remove DFM: X'

    // rnkUnuse
    UnuseUnit: string;

    // rnkUse
    UseUnit: string;

    // rnkUseSwap
    SwapOld: string;         // the Old unit being replaced
    SwapNew: TArray<string>; // one-or-more New units

    // rnkMigrate / rnkPcre / rnkNote / rnkComment keep their content in Raw only
    // (Migrate/PCRE are rarely grid-edited; the directive tabs edit Raw text).
    NoteText: string;      // rnkNote payload (after '#note ')

    // rnkMapping -- ONE node per physical line; a #mapping with three clauses is
    // three sibling nodes, never a tree. MapFromType <> '' marks the declaration
    // line; otherwise the node is a clause (IsElse tells #when from #else apart).
    /// <summary>The mapping's name, present on the declaration line AND on every
    /// clause line, since the clauses are siblings that only refer back by name.</summary>
    MapName    : string;
    /// <summary>Declaration line only: the source enum type ('' on clause lines).</summary>
    MapFromType: string;
    /// <summary>Declaration line only: the target classes the mapping is narrowed to,
    /// in source order; empty on clause lines.</summary>
    MapToTypes : TArray<string>;
    /// <summary>#when clause only: the left-hand source property path.</summary>
    WhenFrom   : string;
    /// <summary>#when clause only: the enum value the clause fires on.</summary>
    WhenValue  : string;
    /// <summary>True on an '#else' clause, which carries Sets but no WhenFrom/WhenValue.</summary>
    IsElse     : Boolean;
    /// <summary>Clause lines only: the assignments to the right of '->', in source order.</summary>
    Sets       : TArray<TSetPair>;

    // rnkApply
    /// <summary>The name of the #mapping this #apply line pulls into its block.</summary>
    ApplyName  : string;

    function Emit: string;
  end;

  /// <summary>Ordered, loss-less model of a whole .rules file. Nodes are kept in
  /// file order; helpers surface the #convert blocks and their #link rows for the
  /// grid without disturbing that order.</summary>
  TRuleBook = class
  private
    FNodes: TObjectList<TRuleNode>;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>Parse ONE physical line into a fresh, unowned node.</summary>
    /// <param name="ALine">The line without its trailing CR/LF. Any text is legal:
    ///   a line the grammar does not recognise becomes rnkUnknown, never an error.</param>
    /// <returns>A new TRuleNode with Raw set to ALine and Dirty False. The CALLER owns
    ///   it unless it is handed to Add/LoadFromString, which transfer it to the book.</returns>
    /// <remarks>Never raises. Public so the model can be spec'd line-by-line without
    ///   round-tripping a whole file.</remarks>
    function ParseLine(const ALine: string): TRuleNode;

    procedure Clear;
    procedure LoadFromString(const AText: string);
    function  SaveToString: string;

    /// <summary>Every node, in file order.</summary>
    property Nodes: TObjectList<TRuleNode> read FNodes;

    // --- convenience for the UI (do not reorder the underlying list) ---

    /// <summary>Indexes of all rnkConvert header nodes, in order.</summary>
    function ConvertHeaders: TArray<Integer>;

    /// <summary>All unit-directive nodes (#use / #unuse / #useswap) in file order.</summary>
    function UnitNodes: TArray<TRuleNode>;

    /// <summary>The #link nodes that belong to the #convert block starting at
    /// AHeaderIdx (i.e. up to the next #convert or EOF).</summary>
    function LinksForBlock(AHeaderIdx: Integer): TArray<TRuleNode>;

    /// <summary>All nodes (any kind) inside the block starting at AHeaderIdx.</summary>
    function NodesInBlock(AHeaderIdx: Integer): TArray<TRuleNode>;

    /// <summary>Append a node; returns it.</summary>
    function Add(ANode: TRuleNode): TRuleNode;

    /// <summary>The rnkMapping nodes named AName, in file order.</summary>
    /// <param name="AName">Mapping name, compared case-insensitively. '' matches
    /// nothing.</param>
    /// <returns>Borrowed references -- the book still owns them. [] when no mapping
    /// carries the name.</returns>
    function MappingNodesNamed(const AName: string): TArray<TRuleNode>;

    /// <summary>Replace EVERY line of the #mapping named AName with ANew, in one
    /// splice.</summary>
    /// <param name="AName">The mapping being rewritten, compared case-insensitively.
    /// '' does nothing.</param>
    /// <param name="ANew">The mapping's complete replacement lines, in file order.
    /// OWNERSHIP TRANSFERS TO THE BOOK -- the caller must not free them, and must not
    /// pass nodes that are ALREADY in this book (the old ones are freed by the delete
    /// below, so an aliased node would be freed and then re-inserted dangling). []
    /// deletes the mapping outright.</param>
    /// <remarks>WHERE the lines land: on top of the old ones when the mapping already
    /// exists -- so a mapping written inside a #convert block stays in that block --
    /// and otherwise immediately ABOVE the first #convert header, which is file scope,
    /// so every block can apply it. A book with no #convert header at all takes them at
    /// the top. The mapping is rewritten as ONE unit because that is how the mapping
    /// editor hands it back; there is no per-line diff.</remarks>
    /// <remarks>Node ORDER outside the mapping is preserved: the deletes run
    /// descending, so no surviving index shifts under a later delete, and the insert
    /// point is the first freed slot, which nothing before it moved past. Callers
    /// holding an INDEX into Nodes (a selected #convert header, say) must re-derive it
    /// afterwards -- Nodes.IndexOf on the node itself is the safe way.</remarks>
    procedure ReplaceMapping(const AName: string; const ANew: TArray<TRuleNode>);

    /// <summary>PURE: does this block body decide the fate of at least one source
    /// property?</summary>
    /// <param name="ANodes">A #convert block's body nodes, as NodesInBlock returns
    /// them. A nil element is skipped. Passing the header itself does no harm --
    /// rnkConvert is not one of the deciding kinds.</param>
    /// <returns>True when the body contains at least one rnkLink, rnkApply or
    /// rnkIgnore node.</returns>
    /// <remarks>THE single answer to "does this block map anything". Two call sites
    /// used to answer it separately and disagree: SaveCompleteToString rescued
    /// [rnkLink, rnkApply] while the editor's completeness percentage counted
    /// [rnkLink, rnkIgnore]. An #apply-only block -- the very shape #apply exists to
    /// create -- therefore read as 0 % complete while being a finished rule, and an
    /// #ignore-only block read as 100 % complete and was then dropped on save as
    /// "empty".</remarks>
    /// <remarks>Membership is "decides a source property", not "has any content":
    /// #link maps one, #apply hands one or more to a named #mapping, and #ignore
    /// records that one is deliberately NOT mapped -- all three are authored
    /// decisions that are lost if the block is dropped. A #mapping is a DECLARATION
    /// and maps nothing until an #apply names it, so it does not rescue a block;
    /// #note, comments and blanks are annotation. #default and #remove are likewise
    /// left out -- pre-existing behaviour, not revisited here.</remarks>
    class function BlockMapsSomething(const ANodes: TArray<TRuleNode>): Boolean; static;

    /// <summary>Serialize like SaveToString, but DROP every #convert block that maps
    /// nothing (see BlockMapsSomething). Content OUTSIDE any #convert block (leading
    /// comments/blanks) is preserved. Blocks that map something round-trip unchanged.
    /// Reports how many blocks were dropped via ADroppedCount.</summary>
    /// <param name="ADroppedCount">Set to the number of blocks omitted; 0 when none.</param>
    /// <remarks>Annotation-only body nodes do NOT rescue a block: a block whose only
    /// child is a #note (or a comment/blank) still counts as mapping nothing and is
    /// dropped. A #mapping-only, #default-only or #remove-only block is likewise still
    /// dropped -- pre-existing behaviour, deliberately left alone here.</remarks>
    function SaveCompleteToString(out ADroppedCount: Integer): string;
  end;

const
  ARROW_MIGRATE = ' -> ';
  ARROW_LINK    = ' <- ';

/// <summary>Renders one property as a grid/pool cell: 'Path : Type', or the bare
/// Path when the type is blank.</summary>
/// <param name="APath">The flattened dotted property path; returned as-is.</param>
/// <param name="ATypeName">The leaf's type; blank/whitespace suppresses the
///   ' : Type' suffix rather than emitting a dangling separator.</param>
/// <returns>The display text for the cell.</returns>
/// <remarks>Single-sourced so the grid's From column, the grid's To column and the
/// To pool cannot drift apart -- the To column showed a bare path until 2026-07-30
/// while the other two showed a type, which is what made a To leaf's type
/// invisible at the point of assignment. PathOfGridCell/TypeOfCell are the
/// inverse and split on the same ' : ' separator, so any change here must keep
/// that round-trip. Pure: no UI, no I/O.</remarks>
function PropCellText(const APath, ATypeName: string): string;

implementation

function PropCellText(const APath, ATypeName: string): string;
begin
  if Trim(ATypeName) = '' then Result := APath
  else Result := APath + ' : ' + Trim(ATypeName);
end;

{ ---- small helpers ---- }

function StripComment(const S: string): Boolean; inline;
begin
  Result := S.StartsWith('//') or S.StartsWith(';');
end;

{ Split S on TOP-LEVEL commas. A comma nested in (), [] or <>, or inside a quoted
  string, is part of one item and does not separate items -- so a generic target
  class ('Unit.TList<A, B>') stays one entry. Blank items are dropped.
  Tradeoff: '<' is treated as an opener, so an unbalanced '<' would swallow the
  commas after it; generics are far likelier here than a bare '<' in a class name
  or an enum value. }
function SplitTopLevelCommas(const S: string): TArray<string>;
var
  L    : TList<string>;
  i    : Integer      ;
  Depth: Integer      ;
  InStr: Boolean      ;
  Start: Integer      ;
  Item : string       ;
begin
  L := TList<string>.Create;
  try
    Depth := 0;
    InStr := False;
    Start := 1;
    for i := 1 to Length(S) do
    begin
      case S[i] of
        '''': InStr := not InStr;
        '(', '[', '<': if not InStr then Inc(Depth);
        ')', ']', '>': if (not InStr) and (Depth > 0) then Dec(Depth);
        ',':
          if (not InStr) and (Depth = 0) then
          begin
            Item := Trim(Copy(S, Start, i - Start));
            if Item <> '' then L.Add(Item);
            Start := i + 1;
          end;
      end;
    end;
    Item := Trim(Copy(S, Start, MaxInt));
    if Item <> '' then L.Add(Item);
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

{ Parse a #mapping clause's set list -- '<ToPath> = <Value>[, ...]' -- into pairs.
  Each item splits on its FIRST '=' so a value containing '=' survives whole, and
  ToPath keeps its dots ('Style.ModalResult.Default' is one path, never segments).
  An item with no '=' yields a bare ToPath with an empty Value. }
function ParseSetList(const S: string): TArray<TSetPair>;
var
  L   : TList<TSetPair>;
  Item: string         ;
  P   : Integer        ;
  Pair: TSetPair       ;
begin
  L := TList<TSetPair>.Create;
  try
    for Item in SplitTopLevelCommas(S) do
    begin
      P := Pos('=', Item);
      if P > 0 then
      begin
        Pair.ToPath := Trim(Copy(Item, 1, P - 1));
        Pair.Value  := Trim(Copy(Item, P + 1, MaxInt));
      end
      else
      begin
        Pair.ToPath := Item;
        Pair.Value  := '';
      end;
      L.Add(Pair);
    end;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

{ Render a set list in the canonical spacing Emit uses: 'A = 1, B = 2'. Only ever
  reached for a Dirty node -- an untouched line still round-trips from Raw. }
function EmitSetList(const A: TArray<TSetPair>): string;
var
  L : TList<string>;
  Pr: TSetPair     ;
begin
  L := TList<string>.Create;
  try
    for Pr in A do
      if Pr.Value <> '' then L.Add(Pr.ToPath + ' = ' + Pr.Value)
      else                   L.Add(Pr.ToPath);
    Result := string.Join(', ', L.ToArray);
  finally
    L.Free;
  end;
end;

{ TRuleNode }

function TRuleNode.Emit: string;
begin
  // Untouched lines round-trip verbatim.
  if not Dirty then
    Exit(Raw);

  case Kind of
    rnkConvert:
      begin
        Result := Format('#convert %s -> %s', [FromType, ToType]);
        if Units <> '' then Result := Result + ', ' + Units;
      end;
    rnkLink:
      begin
        Result := Format('#link %s <- %s', [LinkTo, LinkFrom]);
        if Cast <> '' then Result := Result + ' : ' + Cast;
      end;
    rnkDefault:
      Result := Format('#default %s = %s', [DefTo, DefValue]);
    rnkIgnore:
      Result := Format('#ignore %s', [IgnorePath]);
    rnkRemove:
      if RemoveDfmOnly then Result := Format('#remove DFM: %s', [RemoveProp])
      else                  Result := Format('#remove %s', [RemoveProp]);
    rnkUnuse:
      Result := Format('#unuse %s', [UnuseUnit]);
    rnkUse:
      Result := Format('#use %s', [UseUnit]);
    rnkUseSwap:
      Result := Format('#useswap %s -> %s', [SwapOld, string.Join(', ', SwapNew)]);
    rnkNote:
      Result := Format('#note %s', [NoteText]);
    rnkMapping:
      // MapFromType marks the declaration line; the clause lines differ only by IsElse.
      if MapFromType <> '' then
        Result := Format('#mapping %s from %s to %s',
                         [MapName, MapFromType, string.Join(', ', MapToTypes)])
      else if IsElse then
        Result := Format('#mapping %s #else -> %s', [MapName, EmitSetList(Sets)])
      else
        Result := Format('#mapping %s #when %s = %s -> %s',
                         [MapName, WhenFrom, WhenValue, EmitSetList(Sets)]);
    rnkApply:
      Result := Format('#apply %s', [ApplyName]);
  else
    // rnkMigrate, rnkPcre, rnkComment, rnkBlank, rnkUnknown: edited via Raw.
    Result := Raw;
  end;
end;

{ TRuleBook }

constructor TRuleBook.Create;
begin
  inherited Create;
  FNodes := TObjectList<TRuleNode>.Create(True);
end;

destructor TRuleBook.Destroy;
begin
  FNodes.Free;
  inherited;
end;

procedure TRuleBook.Clear;
begin
  FNodes.Clear;
end;

function TRuleBook.Add(ANode: TRuleNode): TRuleNode;
begin
  FNodes.Add(ANode);
  Result := ANode;
end;

function TRuleBook.ParseLine(const ALine: string): TRuleNode;
var
  N    : TRuleNode;
  T    : string   ;
  Body : string   ;
  P    : Integer  ;
  CommaP: Integer ;
  ColonP: Integer ;
  Rest : string   ;

  { Split "A -> B" (or "A <- B") once, on the FIRST occurrence of AArrow. }
  function SplitArrow(const S, AArrow: string; out L, R: string): Boolean;
  var Q: Integer;
  begin
    Q := Pos(AArrow, S);
    Result := Q > 0;
    if Result then
    begin
      L := Trim(Copy(S, 1, Q - 1));
      R := Trim(Copy(S, Q + Length(AArrow), MaxInt));
    end;
  end;

  { Split on the FIRST bare '->', with or without the surrounding spaces -- a
    #mapping clause writes '#else -> x', where the arrow has no space to its left. }
  function SplitBareArrow(const S: string; out L, R: string): Boolean;
  var Q: Integer;
  begin
    Q := Pos('->', S);
    Result := Q > 0;
    if Result then
    begin
      L := Trim(Copy(S, 1, Q - 1));
      R := Trim(Copy(S, Q + 2, MaxInt));
    end;
  end;

begin
  N := TRuleNode.Create;
  N.Raw := ALine;
  N.Dirty := False;
  T := Trim(ALine);

  if T = '' then
  begin
    N.Kind := rnkBlank;
    Exit(N);
  end;
  if StripComment(T) then
  begin
    N.Kind := rnkComment;
    Exit(N);
  end;

  if T.StartsWith('#') then
  begin
    // directive: split the leading '#word' from the rest
    P := Pos(' ', T);
    if P = 0 then P := Length(T) + 1;
    var Dir: string := LowerCase(Copy(T, 1, P - 1));
    Body := Trim(Copy(T, P + 1, MaxInt));

    if Dir = '#mapping' then
    begin
      // Three flat sibling line forms, all tied together only by <Name>:
      //   #mapping <Name> from <EnumType> to <Class>[, <Class> ...]   (declaration)
      //   #mapping <Name> #when <Path> = <Value> -> <ToPath> = <V>[, ...]
      //   #mapping <Name> #else -> <ToPath> = <V>[, ...]
      N.Kind := rnkMapping;
      P := Pos(' ', Body);
      if P = 0 then
      begin
        N.MapName := Body; // name only; the tail round-trips from Raw
        Exit(N);
      end;
      N.MapName := Trim(Copy(Body, 1, P - 1));
      Rest := Trim(Copy(Body, P + 1, MaxInt));

      if LowerCase(Rest).StartsWith('#when') then
      begin
        Rest := Trim(Copy(Rest, Length('#when') + 1, MaxInt));
        var Cond, SetsTxt: string;
        // Branch on the result: SplitBareArrow's out-mode string arguments are
        // finalized to '' BEFORE it runs, so on False they are empty, NOT whatever
        // the caller put there. A #when with no '->' must keep its condition.
        if not SplitBareArrow(Rest, Cond, SetsTxt) then
        begin
          Cond    := Rest;
          SetsTxt := '';
        end;
        var EqP: Integer := Pos('=', Cond);
        if EqP > 0 then
        begin
          N.WhenFrom  := Trim(Copy(Cond, 1, EqP - 1));
          N.WhenValue := Trim(Copy(Cond, EqP + 1, MaxInt));
        end
        else
          N.WhenFrom := Cond;
        N.Sets := ParseSetList(SetsTxt);
        Exit(N);
      end;

      if LowerCase(Rest).StartsWith('#else') then
      begin
        N.IsElse := True;
        Rest := Trim(Copy(Rest, Length('#else') + 1, MaxInt));
        var Lhs, SetsTxt: string;
        if SplitBareArrow(Rest, Lhs, SetsTxt) then
          N.Sets := ParseSetList(SetsTxt);
        Exit(N);
      end;

      if LowerCase(Rest).StartsWith('from ') then
      begin
        Rest := Trim(Copy(Rest, Length('from ') + 1, MaxInt));
        var ToP: Integer := Pos(' to ', LowerCase(Rest));
        if ToP > 0 then
        begin
          N.MapFromType := Trim(Copy(Rest, 1, ToP - 1));
          N.MapToTypes  := SplitTopLevelCommas(Copy(Rest, ToP + Length(' to '), MaxInt));
        end
        else
          N.MapFromType := Rest;
      end;
      Exit(N);
    end;

    if Dir = '#apply' then
    begin
      N.Kind := rnkApply;
      N.ApplyName := Body;
      Exit(N);
    end;

    if Dir = '#convert' then
    begin
      N.Kind := rnkConvert;
      // From -> To [, unit ...]
      if SplitArrow(Body, ARROW_MIGRATE, N.FromType, Rest) then
      begin
        CommaP := Pos(',', Rest);
        if CommaP > 0 then
        begin
          N.ToType := Trim(Copy(Rest, 1, CommaP - 1));
          N.Units  := Trim(Copy(Rest, CommaP + 1, MaxInt));
        end
        else
          N.ToType := Trim(Rest);
      end;
      Exit(N);
    end;

    if Dir = '#link' then
    begin
      N.Kind := rnkLink;
      // ToPath <- FromPath [: CastFn]
      if SplitArrow(Body, ARROW_LINK, N.LinkTo, Rest) then
      begin
        // optional trailing ' : CastFn' on the FromPath side
        ColonP := Rest.LastIndexOf(':');
        if ColonP >= 0 then
        begin
          var Tail: string := Trim(Rest.Substring(ColonP + 1));
          // a cast tail is a single bare identifier (no space/dot)
          if (Tail <> '') and (Pos(' ', Tail) = 0) and (Pos('.', Tail) = 0)
             and (Pos('<', Tail) = 0) then
          begin
            N.Cast     := Tail;
            N.LinkFrom := Trim(Rest.Substring(0, ColonP));
          end
          else
            N.LinkFrom := Trim(Rest);
        end
        else
          N.LinkFrom := Trim(Rest);
      end;
      Exit(N);
    end;

    if Dir = '#default' then
    begin
      N.Kind := rnkDefault;
      P := Pos('=', Body);
      if P > 0 then
      begin
        N.DefTo    := Trim(Copy(Body, 1, P - 1));
        N.DefValue := Trim(Copy(Body, P + 1, MaxInt));
      end
      else
        N.DefTo := Trim(Body);
      Exit(N);
    end;

    if Dir = '#ignore' then
    begin
      N.Kind := rnkIgnore;
      N.IgnorePath := Body;
      Exit(N);
    end;

    if Dir = '#remove' then
    begin
      N.Kind := rnkRemove;
      if LowerCase(Body).StartsWith('dfm:') then
      begin
        N.RemoveDfmOnly := True;
        N.RemoveProp := Trim(Copy(Body, Length('dfm:') + 1, MaxInt));
      end
      else
      begin
        N.RemoveDfmOnly := False;
        N.RemoveProp := Body;
      end;
      Exit(N);
    end;

    if Dir = '#unuse' then
    begin
      N.Kind := rnkUnuse;
      N.UnuseUnit := Body;
      Exit(N);
    end;

    if Dir = '#useswap' then
    begin
      // #useswap Old -> New1[, New2 ...]  -- SwapOld=Old, SwapNew=comma list.
      N.Kind := rnkUseSwap;
      if SplitArrow(Body, ARROW_MIGRATE, N.SwapOld, Rest) then
      begin
        var Parts: TArray<string> := Rest.Split([',']);
        var Tmp: TList<string> := TList<string>.Create;
        try
          for var Pt in Parts do
            if Trim(Pt) <> '' then Tmp.Add(Trim(Pt));
          N.SwapNew := Tmp.ToArray;
        finally
          Tmp.Free;
        end;
      end;
      Exit(N);
    end;

    if Dir = '#use' then
    begin
      N.Kind := rnkUse;
      N.UseUnit := Body;
      Exit(N);
    end;

    if Dir = '#migrate' then
    begin
      N.Kind := rnkMigrate; // content edited via Raw
      Exit(N);
    end;

    if Dir = '#note' then
    begin
      N.Kind := rnkNote;
      N.NoteText := Body;
      Exit(N);
    end;

    // unknown '#directive'
    N.Kind := rnkUnknown;
    Exit(N);
  end;

  // Non-'#' line: a raw PCRE find/replace is the only legal non-directive line,
  // recognised by containing the ' -> ' arrow. Anything else is unknown.
  if Pos(ARROW_MIGRATE, T) > 0 then
    N.Kind := rnkPcre
  else
    N.Kind := rnkUnknown;
  Result := N;
end;

procedure TRuleBook.LoadFromString(const AText: string);
var
  SL: TStringList;
  i : Integer   ;
begin
  Clear;
  SL := TStringList.Create;
  try
    // TStringList splits on CRLF/LF/CR uniformly; we re-emit CRLF on save.
    SL.Text := AText;
    for i := 0 to SL.Count - 1 do
      FNodes.Add(ParseLine(SL[i]));
    // TStringList.Text drops a trailing empty line; the model treats the file as
    // its non-terminated lines, which SaveToString re-joins with CRLF + trailing.
  finally
    SL.Free;
  end;
end;

function TRuleBook.SaveToString: string;
var
  SB: TStringBuilder;
  N : TRuleNode     ;
begin
  SB := TStringBuilder.Create;
  try
    for N in FNodes do
    begin
      SB.Append(N.Emit);
      SB.Append(#13#10); // canonical CRLF
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TRuleBook.MappingNodesNamed(const AName: string): TArray<TRuleNode>;
var
  L: TList<TRuleNode>;
  i: Integer         ;
begin
  L := TList<TRuleNode>.Create;
  try
    if AName <> '' then
      for i := 0 to FNodes.Count - 1 do
        if (FNodes[i].Kind = rnkMapping) and SameText(FNodes[i].MapName, AName) then
          L.Add(FNodes[i]);
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

procedure TRuleBook.ReplaceMapping(const AName: string; const ANew: TArray<TRuleNode>);
var
  Idx  : TArray<Integer>;
  InsAt: Integer        ;
  i    : Integer        ;
begin
  if AName = '' then Exit;

  Idx := nil;
  for i := 0 to FNodes.Count - 1 do
    if (FNodes[i].Kind = rnkMapping) and SameText(FNodes[i].MapName, AName) then
      Idx := Idx + [i];

  if Length(Idx) > 0 then
    InsAt := Idx[0]           // still valid after the deletes: it is the FIRST freed
  else                        // slot, and nothing before it moved
  begin
    // A mapping that does not exist yet goes above the first #convert -- file scope,
    // so every block can apply it. Written inside a block it would read as that
    // block's. With no #convert at all, the top of the file is the only file scope.
    InsAt := 0;
    for i := 0 to FNodes.Count - 1 do
      if FNodes[i].Kind = rnkConvert then begin InsAt := i; Break; end;
  end;

  // Descending, so each remaining index in Idx still addresses its own node.
  for i := High(Idx) downto 0 do
    FNodes.Delete(Idx[i]);    // the book owns them, so Delete frees them
  for i := 0 to High(ANew) do
    FNodes.Insert(InsAt + i, ANew[i]);
end;

class function TRuleBook.BlockMapsSomething(const ANodes: TArray<TRuleNode>): Boolean;
var
  N: TRuleNode;
begin
  for N in ANodes do
    if (N <> nil) and (N.Kind in [rnkLink, rnkApply, rnkIgnore]) then Exit(True);
  Result := False;
end;

function TRuleBook.SaveCompleteToString(out ADroppedCount: Integer): string;
var
  SB  : TStringBuilder;
  i   : Integer       ;
  j   : Integer       ;
  Body: TList<TRuleNode>;
begin
  ADroppedCount := 0;
  SB := TStringBuilder.Create;
  Body := TList<TRuleNode>.Create;   // borrowed references; FNodes still owns them
  try
    i := 0;
    while i < FNodes.Count do
    begin
      if FNodes[i].Kind = rnkConvert then
      begin
        // find the block extent [i .. j) up to the next header or EOF
        j := i + 1;
        Body.Clear;
        while (j < FNodes.Count) and (FNodes[j].Kind <> rnkConvert) do
        begin
          Body.Add(FNodes[j]);
          Inc(j);
        end;
        // "Maps something" is NOT decided here -- BlockMapsSomething is the one place
        // that rule is written down, shared with the editor's completeness percentage.
        if BlockMapsSomething(Body.ToArray) then
        begin
          // emit the whole block verbatim (header + its nodes)
          for var k := i to j - 1 do
          begin
            SB.Append(FNodes[k].Emit);
            SB.Append(#13#10);
          end;
        end
        else
          Inc(ADroppedCount); // maps nothing -> scratch, not persisted
        i := j;
      end
      else
      begin
        // content outside any #convert block (leading comments/blanks) -> keep
        SB.Append(FNodes[i].Emit);
        SB.Append(#13#10);
        Inc(i);
      end;
    end;
    Result := SB.ToString;
  finally
    Body.Free;
    SB.Free;
  end;
end;

function TRuleBook.ConvertHeaders: TArray<Integer>;
var
  L: TList<Integer>;
  i: Integer       ;
begin
  L := TList<Integer>.Create;
  try
    for i := 0 to FNodes.Count - 1 do
      if FNodes[i].Kind = rnkConvert then L.Add(i);
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function TRuleBook.UnitNodes: TArray<TRuleNode>;
var
  L: TList<TRuleNode>;
  N: TRuleNode       ;
begin
  L := TList<TRuleNode>.Create;
  try
    for N in FNodes do
      if N.Kind in [rnkUse, rnkUnuse, rnkUseSwap] then L.Add(N);
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function TRuleBook.NodesInBlock(AHeaderIdx: Integer): TArray<TRuleNode>;
var
  L: TList<TRuleNode>;
  i: Integer         ;
begin
  L := TList<TRuleNode>.Create;
  try
    if (AHeaderIdx >= 0) and (AHeaderIdx < FNodes.Count)
       and (FNodes[AHeaderIdx].Kind = rnkConvert) then
    begin
      for i := AHeaderIdx + 1 to FNodes.Count - 1 do
      begin
        if FNodes[i].Kind = rnkConvert then Break; // next block
        L.Add(FNodes[i]);
      end;
    end;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function TRuleBook.LinksForBlock(AHeaderIdx: Integer): TArray<TRuleNode>;
var
  L: TList<TRuleNode>;
  N: TRuleNode       ;
begin
  L := TList<TRuleNode>.Create;
  try
    for N in NodesInBlock(AHeaderIdx) do
      if N.Kind = rnkLink then L.Add(N);
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

end.
