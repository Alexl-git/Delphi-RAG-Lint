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
    rnkMigrate,    // #migrate [Class:][obj.]old -> new [, unit ...]
    rnkNote,       // #note text
    rnkPcre,       // raw <pcre> -> <pcre> escape-hatch line
    rnkUnknown     // anything else (kept verbatim, never dropped)
  );

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

    // rnkMigrate / rnkPcre / rnkNote / rnkComment keep their content in Raw only
    // (Migrate/PCRE are rarely grid-edited; the directive tabs edit Raw text).
    NoteText: string;      // rnkNote payload (after '#note ')

    function Emit: string;
  end;

  /// <summary>Ordered, loss-less model of a whole .rules file. Nodes are kept in
  /// file order; helpers surface the #convert blocks and their #link rows for the
  /// grid without disturbing that order.</summary>
  TRuleBook = class
  private
    FNodes: TObjectList<TRuleNode>;
    function ParseLine(const ALine: string): TRuleNode;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    procedure LoadFromString(const AText: string);
    function  SaveToString: string;

    /// <summary>Every node, in file order.</summary>
    property Nodes: TObjectList<TRuleNode> read FNodes;

    // --- convenience for the UI (do not reorder the underlying list) ---

    /// <summary>Indexes of all rnkConvert header nodes, in order.</summary>
    function ConvertHeaders: TArray<Integer>;

    /// <summary>The #link nodes that belong to the #convert block starting at
    /// AHeaderIdx (i.e. up to the next #convert or EOF).</summary>
    function LinksForBlock(AHeaderIdx: Integer): TArray<TRuleNode>;

    /// <summary>All nodes (any kind) inside the block starting at AHeaderIdx.</summary>
    function NodesInBlock(AHeaderIdx: Integer): TArray<TRuleNode>;

    /// <summary>Append a node; returns it.</summary>
    function Add(ANode: TRuleNode): TRuleNode;
  end;

const
  ARROW_MIGRATE = ' -> ';
  ARROW_LINK    = ' <- ';

implementation

{ ---- small helpers ---- }

function StripComment(const S: string): Boolean; inline;
begin
  Result := S.StartsWith('//') or S.StartsWith(';');
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
    rnkNote:
      Result := Format('#note %s', [NoteText]);
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
