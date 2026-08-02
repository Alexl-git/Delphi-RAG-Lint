unit ConvRules.Engine;

{ Engine adapter: the ONLY boundary between the editor and drag-lint.

  All semantic knowledge (property trees, scaffold drafts, validation) comes from
  shelling the drag-lint CLI and parsing its output. The editor never parses DFMs
  or Pascal itself. Two layers:

    - PURE parsers (ParseProptreeJson, ...) -- testable against captured fixtures,
      no process spawn.
    - I/O wrappers (RunProptree, RunScaffold, RunValidate) -- spawn drag-lint and
      feed the output to the pure parsers.

  Keeping the parsers pure means the JSON handling is unit-tested without needing
  the exe or an index at test time. }

interface

uses
  System.SysUtils
  , System.Classes
  , System.JSON
  , System.Generics.Collections
  ;

const
  /// <summary>Watchdog for ONE drag-lint invocation, in milliseconds. On expiry
  /// RunCapture terminates the child and returns 3.</summary>
  /// <remarks>A guard against a pathological (effectively unbounded) walk hanging
  /// the editor's main thread -- NOT a latency budget, so it is set well above
  /// every legitimate call rather than close to one. It was 30000, which was below
  /// legitimate work on TWO different paths. Measured 2026-07-29 against
  /// library-Win64 + ORM3, per verb:
  ///   ValidateText  (convert-validate)                      29.83 s  &lt;-- slowest
  ///   GetProptree   (no --min-visibility, --refs-as-leaves)   7.82 s
  ///   GetProptree   (--min-visibility published, refs)        6.96 s
  ///   ListDescendantsOf / ListProjectUnits                &lt;= 0.50 s
  /// So a 30 s bound sat essentially ON TOP of ValidateText, and the pre-fix
  /// proptree call (20.11 s warm here, 74-79 s recorded on a colder index) could
  /// exceed it outright -- the editor reported a timeout for work that would have
  /// succeeded. 180 s is ~6x the slowest call above.</remarks>
  /// <remarks>CONDITION, since this bound does not cover everything: Scaffold
  /// (convert-scaffold) measured 346 s for one Vcl.StdCtrls.TButton -&gt;
  /// cxButtons.TcxButton scaffold, emitting 6.7 MB, and WOULD time out here. That
  /// is currently harmless only because Scaffold has no caller in the editor. Give
  /// it one and this bound must be revisited -- or better, find out why it is 44x
  /// the equivalent proptree call (convert-scaffold takes no --refs-as-leaves, so
  /// it is likely expanding component references the way proptree used to).
  /// Note also that RunCapture drains on the calling thread, so this bound is also
  /// the longest the UI can be frozen.</remarks>
  ENGINE_TIMEOUT_MS = 180000;

type
  /// <summary>One flattened property leaf from `proptree --format json`
  /// (schema proptree/1).</summary>
  TPropLeaf = record
    Path       : string;   // dotted path, e.g. 'Style.Font.Size'
    TypeName   : string;   // declared type, e.g. 'Integer'
    DeclaredIn : string;   // owning unit.class, e.g. 'Vcl.Graphics.TFont'
    Kind       : string;   // 'scalar' | 'class' | 'unknown'
    IsClassType: Boolean;  // recursion descended into it
    // proptree/2 (engine schema v17): assignability of this leaf as a TARGET.
    IsWritable : Boolean;  // False = read-only (ro prop / typed const): not a valid target
    Visibility : string;   // 'published' | 'public' | ... ('' when absent)
    MemberKind : string;   // 'property' | 'field'  ('property' when absent)
  end;

  TProptree = record
    Qname    : string;
    RootType : string;
    Truncated: Boolean;
    Leaves   : TArray<TPropLeaf>;
  end;

  /// <summary>Result of running convert-validate: OK plus an optional first-error
  /// line (as the CLI reports it, e.g. "line 4: link ToPath not found ...").</summary>
  TValidateResult = record
    OK       : Boolean;
    FirstError: string;  // '' when OK
  end;

/// <summary>PURE: parse `proptree/1` JSON into a TProptree. Raises on malformed
/// JSON; returns an empty Leaves array when the "properties" array is absent.</summary>
function ParseProptreeJson(const AJson: string): TProptree;

type
  /// <summary>One row of `drag-lint query --name X --json` -- the fields this
  /// editor needs out of the engine's symbol record.</summary>
  /// <remarks>Measured against the shipped exe on 2026-07-30: the payload is a
  /// BARE top-level JSON array of these records (there is no enclosing "results"
  /// object), and the declaration line is spelled "start_line", NOT "line".</remarks>
  TQuerySymbol = record
    Kind         : string;   // 'class'|'record'|'interface'|'enum'|'type'|'field'|'local_var'|...
    Name         : string;   // bare identifier
    QualifiedName: string;   // e.g. 'System.Classes.TAlignment'
    FilePath     : string;   // absolute path of the declaring file
    StartLine    : Integer;  // 1-based first line of the declaration ("start_line")
    EndLine      : Integer;  // 1-based last  line of the declaration ("end_line")
  end;

/// <summary>PURE: parse the JSON array `query --json` prints into symbol rows.</summary>
/// <param name="AJson">Raw captured output. A "(loaded defaults ...)" note before or
/// after the array is tolerated: RunCapture merges the child's stderr into stdout,
/// and the exe writes that note to stderr on every call.</param>
/// <returns>One entry per array element. [] when the text contains no JSON array --
/// garbage in, empty out. Never raises.</returns>
function ParseQuerySymbols(const AJson: string): TArray<TQuerySymbol>;

/// <summary>PURE: pick the row that actually IS AWantedName.</summary>
/// <param name="ASyms">Rows as returned by ParseQuerySymbols.</param>
/// <param name="AWantedName">Bare ('TAlignment') or unit-qualified
/// ('Abcbtn.TabcButtonStyle'). The part after the last dot is compared to each
/// row's Name; a qualified request must additionally match QualifiedName.</param>
/// <param name="ASym">The chosen row. Untouched (Default) when the result is False.</param>
/// <param name="AAmbiguity">How many exact-name rows shared the WINNING tier. 1 means
/// the answer was forced; &gt; 1 means ASym is one of several equally-ranked candidates
/// and was picked only by the engine's row order. 0 when the result is False. The
/// caller MUST surface a value &gt; 1 -- see the remarks.</param>
/// <returns>False when no row carries that exact name.</returns>
/// <remarks>`--name` is a SUBSTRING match, so the reply routinely contains unrelated
/// symbols: `--name TNotifyEvent` returns local variables called ANotifyEvent and
/// nothing named TNotifyEvent at all, and `--name TThread` returns an unrelated FIELD
/// named TThread BEFORE System.Classes.TThread. Taking the first row is therefore
/// wrong.</remarks>
/// <remarks>Ranking, best first: a CONCRETE declaration (class/record/interface/enum),
/// then kind='type' (an alias, set or subrange), then anything else. So the enum
/// System.UITypes.TFontPitch beats the alias Vcl.Graphics.TFontPitch that merely points
/// at it, whichever order the engine happened to list them in -- and it is the enum row
/// that EnumMembersOf can actually read members out of.</remarks>
/// <remarks>Ranking CANNOT settle a tie inside a tier, and ties are common rather than
/// exotic: `--name TAlignment` returns THREE tier-0 rows -- System.Classes.TAlignment
/// (enum), a record nested in a DevExpress RichEdit dialog form, and an enum nested in
/// dxSplashForms -- all `section=interface` with `usable_from_other_units=true`, so no
/// row attribute separates them either. The right one wins only because System.Classes
/// was indexed first, which is exactly the ordering assumption the tiering exists to
/// remove. Rather than guess harder, this reports HOW MANY tied via AAmbiguity so the
/// caller can turn a silent wrong jump into a visible choice. Pass a qualified name to
/// force the issue.</remarks>
function SelectQuerySymbol(const ASyms: TArray<TQuerySymbol>;
  const AWantedName: string; out ASym: TQuerySymbol;
  out AAmbiguity: Integer): Boolean;

/// <summary>PURE: the declaration site of AWantedName in `query --json` output.</summary>
/// <param name="AJson">Raw captured output (stderr preamble tolerated).</param>
/// <param name="AWantedName">The type the caller asked about; see SelectQuerySymbol
/// for how a row is matched and ranked.</param>
/// <param name="AFile">Absolute path of the declaring file; '' when False.</param>
/// <param name="ALine">1-based declaration line, read from "start_line". 0 when False.
/// CLAMPED to a minimum of 1 on success: the wire contract says a missing or garbled
/// line is to be treated as 1, so a chosen row whose "start_line" is absent or &lt; 1
/// still resolves -- to line 1 of the right file, never to line 0.</param>
/// <param name="AAmbiguity">How many rows tied at the winning tier; see
/// SelectQuerySymbol. 1 = forced, &gt; 1 = the caller must say so, 0 when False.</param>
/// <returns>False for garbage, for an empty array (the real zero-hit reply), for a
/// chosen row with no "file", and -- importantly -- when every row is only a SUBSTRING
/// match on the requested name.</returns>
function ParseQueryLocation(const AJson, AWantedName: string; out AFile: string;
  out ALine: Integer; out AAmbiguity: Integer): Boolean;

/// <summary>PURE: the member identifiers of an enum, read from its DECLARATION
/// SOURCE TEXT.</summary>
/// <param name="ADeclText">The source lines start_line..end_line of an enum row --
/// e.g. 'TAlignment = (taLeftJustify, taRightJustify, taCenter);'.</param>
/// <param name="AMembers">Members in declaration order; [] when False.</param>
/// <returns>False when ADeclText is not an enum declaration (no '=' immediately
/// followed by a '(' -- which is what rejects 'TFoo = class(TBar)') or when the
/// list is empty.</returns>
/// <remarks>The source text is the ONLY place these live: an enum row in the index
/// carries no members field, `query --qname` returns just the enum itself, and
/// `surface --qname` refuses anything that is not a class/record/interface. Members
/// ARE indexed individually as kind='enum_value' rows, but there is no
/// children-of-a-parent query to reach them.</remarks>
/// <remarks>Brace comments and compiler directives are stripped, so a declaration
/// guarded by $IFDEF yields the members of BOTH arms; duplicates are removed
/// case-insensitively, keeping first appearance. An explicit ordinal ('a = 1')
/// contributes the identifier only.</remarks>
function ParseEnumMembers(const ADeclText: string; out AMembers: TArray<string>): Boolean;

type
  /// <summary>Adapter over a drag-lint executable + a set of index DBs.</summary>
  TEngineAdapter = class
  private
    FExePath: string;
    FDbList : TArray<string>;
    function RunCapture(const AArgs: string; out AOutput: string): Integer;
    /// <summary>`query --name AName --json` -> raw output, or '' + a reason.
    /// AName must be BARE: a dotted name matches nothing.</summary>
    function QueryJsonFor(const AName: string; out AJson, AError: string): Boolean;
    function DbArgsFor(const ADbs: TArray<string>): string; overload;
    function DbArgs: string; overload;
    /// <summary>The .pas file that declares unit AUnit, via `query --name AUnit
    /// --json` (the kind=unit row's "file"). '' if the unit is not indexed.</summary>
    function ResolveUnitFile(const AUnit: string): string;
    /// <summary>Qualify a bare class name to its unit-qualified form (TcxButton ->
    /// cxButtons.TcxButton) via `query --name`, which is what `proptree --qname`
    /// requires. Discards the tie count; see the overload below.</summary>
    function ResolveClassQName(const AName: string): string; overload;

    /// <summary>As above, reporting how many CLASS rows carried EXACTLY this
    /// name.</summary>
    /// <param name="AName">Bare class name. Returned unchanged (with AAmbiguity 0)
    /// when it already contains a '.', when it is empty, or when no class row
    /// carries it.</param>
    /// <param name="AAmbiguity">1 when exactly one class is named AName. &gt; 1 when
    /// several are and the result is one of them, picked only by the engine's row
    /// order -- the caller must SAY SO. 0 when nothing resolved.</param>
    /// <returns>The chosen row's qualified_name, or AName unchanged.</returns>
    /// <remarks>Selection goes through the same ParseQuerySymbols/SelectQuerySymbol
    /// pair the go-to-definition path uses, narrowed to kind='class' first (proptree
    /// wants the class, and a same-named enum or record would otherwise win the tier-0
    /// tie). The rows are pre-filtered rather than ranked because `--name` is a
    /// SUBSTRING match: measured against library-Win64 on 2026-08-02, `--name TLabel`
    /// returns 34 rows of which most are kind='component' DFM instances. Ties between
    /// frameworks are the normal case, not the exotic one -- TEdit has two classes
    /// (FMX.Edit and Vcl.StdCtrls) and TButton four -- so the count is what turns a
    /// silent FMX property tree into a visible one.</remarks>
    function ResolveClassQName(const AName: string;
      out AAmbiguity: Integer): string; overload;
  public
    constructor Create(const AExePath: string; const ADbList: TArray<string>);

    /// <summary>Replace the adapter's default DB list (used by proptree /
    /// scaffold / validate / class-name resolution). Called when the editor's
    /// FROM or TO platform changes so type resolution targets the new
    /// libraries.</summary>
    procedure SetDbs(const ADbs: TArray<string>);
    /// <summary>The adapter's current default DB list (read-only view).</summary>
    function DbList: TArray<string>;

    /// <summary>proptree --qname X [--min-visibility V] --refs-as-leaves --format
    /// json. AMinVisibility ('published'|'public'|'') selects the target surface
    /// (engine schema v17); '' emits every leaf. Returns False + empty tree if the
    /// type does not resolve (exit 1), the exe/db is unusable (exit 2), or the call
    /// exceeded ENGINE_TIMEOUT_MS (exit 3).</summary>
    /// <param name="AQname">Bare ('TcxButton') or unit-qualified
    /// ('cxButtons.TcxButton'); a bare name is qualified first via
    /// ResolveClassQName.</param>
    /// <param name="ANote">'' unless a BARE name matched several classes, in which
    /// case it says how many and which one was used -- e.g. 'TEdit: 2 classes carry
    /// that name; used FMX.Edit.TEdit.'. The tree that comes back is then only one of
    /// the candidates, so the caller MUST show this even though the call succeeded.
    /// Never a reason to treat the result as a failure.</param>
    /// <remarks>--refs-as-leaves is ALWAYS passed, so a TComponent-typed property
    /// appears as a single leaf and is NOT recursed into. Callers therefore do not
    /// see paths through a component reference (no 'Action.Owner.Name'); those are
    /// references, not owned sub-objects, and are not assignable targets. Leaves
    /// through owned TPersistent sub-objects ('Colors.Button.FormattedText.*') are
    /// still returned in full. ATree.Truncated reports the engine's own cap and is
    /// True even for a bounded call on a large DevExpress control.</remarks>
    function GetProptree(const AQname: string; out ATree: TProptree;
      out AError: string; out ANote: string;
      const AMinVisibility: string = ''): Boolean;

    /// <summary>The unit that declares ATypeName, derived by resolving it to its
    /// unit-qualified form (ResolveClassQName) and taking the part before the LAST
    /// dot (so 'Vcl.Graphics.TFont' -> 'Vcl.Graphics', 'cxButtons.TcxButton' ->
    /// 'cxButtons'). '' when the type does not resolve (no dot in the qname). Used
    /// by the editor's "derive units from conversions".</summary>
    function DeclaringUnitOf(const ATypeName: string): string;

    /// <summary>List every class that transitively descends from AAncestor (e.g.
    /// 'TControl' -> all visual controls: TEdit, TLabel, TcxTextEdit, ...), deduped
    /// + sorted. Backed by the `query descendants --of &lt;A>` verb. Returns False +
    /// AError on failure.</summary>
    function ListDescendantsOf(const AAncestor: string; out ANames: TArray<string>;
      out AError: string): Boolean; overload;

    /// <summary>As ListDescendantsOf, but queries an EXPLICIT db set (ADbs) instead
    /// of the adapter's default, so each picker side can scope to its own platform
    /// library. Names from all listed DBs are merged + deduped, so listing several
    /// DBs can only add names, never remove them.</summary>
    function ListDescendantsOf(const AAncestor: string; const ADbs: TArray<string>;
      out ANames: TArray<string>; out AError: string): Boolean; overload;

    /// <summary>List indexed project unit names (kind=unit), sorted. Backed by
    /// `query find --no-docs --kind unit`. Returns False + AError on failure.</summary>
    function ListProjectUnits(out ANames: TArray<string>; out AError: string): Boolean;

    /// <summary>The distinct component TYPES placed on AUnit's form, read from the
    /// unit's companion .dfm (`object &lt;Name&gt;: &lt;TType&gt;` lines) -- the
    /// authoritative list of what the designer actually dropped on the form. Used
    /// to pre-fill the grid's From column from a project unit. AControlSet is
    /// accepted for signature compatibility but NOT used to filter: a real DFM
    /// component (Orpheus TOvc*, Raize TRz*, DevExpress Tcx*) is kept even when its
    /// ancestry to TComponent is unresolved in the library index. Returns [] (not
    /// an error) when the unit has no .dfm or is not indexed.</summary>
    function ListControlTypesInUnit(const AUnit: string;
      const AControlSet: TArray<string>; out ATypes: TArray<string>;
      out AError: string): Boolean;

    /// <summary>Where AType is declared: `query --name AType --json`, narrowed to an
    /// exact-name, type-like row (see SelectQuerySymbol -- `--name` is a substring
    /// match, so the first row is regularly the wrong symbol).</summary>
    /// <param name="AType">Bare ('TabcButtonStyle') or unit-qualified type name, as it
    /// appears in a grid/pool cell.</param>
    /// <param name="AFile">Absolute path of the declaring file; '' when False.</param>
    /// <param name="ALine">1-based declaration line; 0 when False. Clamped to a
    /// minimum of 1 on success -- see ParseQueryLocation.</param>
    /// <param name="AError">Why it failed; '' on success.</param>
    /// <returns>False when the type is not in the configured indexes, when the exe or
    /// a DB is unusable, or when the call exceeded ENGINE_TIMEOUT_MS.</returns>
    /// <remarks>Exit 1 from the engine means "no hits", NOT a broken call -- it is
    /// reported as a not-indexed message, not an engine failure. Method-pointer types
    /// (TNotifyEvent and friends) are among the things the index does not carry, so a
    /// perfectly ordinary event property resolves to nothing here.</remarks>
    /// <remarks>This overload DISCARDS the ambiguity count, so it cannot tell the user
    /// that several equally-ranked declarations shared the name. Any caller with a
    /// status bar should use the overload below.</remarks>
    function ResolveTypeLocation(const AType: string; out AFile: string;
      out ALine: Integer; out AError: string): Boolean; overload;

    /// <summary>As above, but also reports how many equally-ranked declarations carried
    /// the name.</summary>
    /// <param name="AType">Bare or unit-qualified type name.</param>
    /// <param name="AFile">Absolute path of the declaring file; '' when False.</param>
    /// <param name="ALine">1-based declaration line; 0 when False.</param>
    /// <param name="AError">Why it failed; '' on success.</param>
    /// <param name="AAmbiguity">1 when the answer was forced. &gt; 1 when AFile is one
    /// of several tied candidates, chosen only by the engine's row order -- the caller
    /// must SAY SO rather than present it as the answer. 0 when False.</param>
    /// <returns>As the overload above.</returns>
    /// <remarks>Ties are ordinary, not exotic: `TAlignment` has three (an RTL enum and
    /// two types nested in DevExpress form classes) and `TColor` has two
    /// (Vcl.Graphics and Spring.Logging). See SelectQuerySymbol for why no row
    /// attribute can separate them.</remarks>
    function ResolveTypeLocation(const AType: string; out AFile: string;
      out ALine: Integer; out AError: string;
      out AAmbiguity: Integer): Boolean; overload;

    /// <summary>The member identifiers of AType when it is an enum.</summary>
    /// <param name="AType">Bare or unit-qualified type name.</param>
    /// <param name="AMembers">Members in declaration order; [] when False.</param>
    /// <param name="AError">Why it failed; '' on success.</param>
    /// <returns>False when AType is not indexed, is not an enum, or its declaring
    /// file is not readable from this machine.</returns>
    /// <remarks>Two steps, because the index has no members field and no
    /// children-of query: resolve the enum row to file + start_line..end_line, then
    /// READ those source lines and hand them to ParseEnumMembers. That makes this the
    /// one adapter verb that needs the library SOURCE on disk, not just the DB.</remarks>
    /// <remarks>This overload DISCARDS the ambiguity count, so it cannot tell the user
    /// that the members came from one of several equally-ranked declarations sharing
    /// the name. Any caller that keeps the list around -- and validates literals or
    /// exhaustiveness against it -- should use the overload below.</remarks>
    function EnumMembersOf(const AType: string; out AMembers: TArray<string>;
      out AError: string): Boolean; overload;

    /// <summary>As above, but also reports how many equally-ranked declarations carried
    /// the name.</summary>
    /// <param name="AType">Bare or unit-qualified type name.</param>
    /// <param name="AMembers">Members in declaration order; [] when False.</param>
    /// <param name="AError">Why it failed; '' on success.</param>
    /// <param name="AAmbiguity">1 when the answer was forced. &gt; 1 when AMembers came
    /// from one of several tied declarations, chosen only by the engine's row order --
    /// the caller must SAY SO rather than present the list as authoritative. 0 when
    /// False.</param>
    /// <returns>As the overload above.</returns>
    /// <remarks>Ties are ordinary, not exotic -- see ResolveTypeLocation. A tied enum
    /// matters more than a tied jump: the wrong member list turns every literal check
    /// and the exhaustiveness pass into confident nonsense.</remarks>
    function EnumMembersOf(const AType: string; out AMembers: TArray<string>;
      out AError: string; out AAmbiguity: Integer): Boolean; overload;

    /// <summary>convert-scaffold --from F --to T. Returns the raw .rules text the
    /// scaffolder emits (to be loaded into a TRuleBook), or '' + AError on failure.</summary>
    function Scaffold(const AFrom, ATo: string; out ARules: string;
      out AError: string): Boolean;

    /// <summary>convert-validate --rules FILE [--from F --to T]. Writes ARulesText
    /// to a temp file, validates, returns the parsed outcome.</summary>
    function ValidateText(const ARulesText, AFrom, ATo: string): TValidateResult;

    property ExePath: string read FExePath;
  end;

implementation

uses
  System.IOUtils
  {$IFDEF MSWINDOWS}, Winapi.Windows{$ENDIF}
  ;

// Slice the first balanced brace-object out of AText, ignoring any preamble or
// trailing lines the CLI may print around the JSON (e.g. a loaded-defaults note).
// Returns empty if no object is found. A string-literal-aware brace scanner, so
// braces inside JSON string values do not throw off the depth count.
function SliceJsonObject(const AText: string): string;
var
  i, depth, startIdx: Integer;
  inStr: Boolean;
  esc  : Boolean;
begin
  Result := '';
  startIdx := 0; depth := 0; inStr := False; esc := False;
  for i := 1 to Length(AText) do
  begin
    if inStr then
    begin
      if esc then esc := False
      else if AText[i] = '\' then esc := True
      else if AText[i] = '"' then inStr := False;
      Continue;
    end;
    case AText[i] of
      '"': inStr := True;
      '{':
        begin
          if depth = 0 then startIdx := i;
          Inc(depth);
        end;
      '}':
        begin
          Dec(depth);
          if depth = 0 then
            Exit(Copy(AText, startIdx, i - startIdx + 1));
        end;
    end;
  end;
end;

function ParseProptreeJson(const AJson: string): TProptree;
var
  Root : TJSONObject;
  Arr  : TJSONArray ;
  V    : TJSONValue ;
  Obj  : TJSONObject;
  List : TList<TPropLeaf>;
  Leaf : TPropLeaf  ;
  BVal : Boolean    ;
  Sliced: string    ;
begin
  Result := Default(TProptree);
  // Tolerate CLI preamble/trailing noise by extracting just the JSON object.
  Sliced := SliceJsonObject(AJson);
  if Sliced = '' then Sliced := AJson; // fall back to whole text
  Root := TJSONObject.ParseJSONValue(Sliced) as TJSONObject;
  if Root = nil then
    raise Exception.Create('proptree: response is not a JSON object');
  try
    Root.TryGetValue<string>('qname', Result.Qname);
    Root.TryGetValue<string>('root_type', Result.RootType);
    if not Root.TryGetValue<Boolean>('truncated', Result.Truncated) then
      Result.Truncated := False;

    List := TList<TPropLeaf>.Create;
    try
      if Root.TryGetValue<TJSONArray>('properties', Arr) then
        for V in Arr do
          if V is TJSONObject then
          begin
            Obj := V as TJSONObject;
            Leaf := Default(TPropLeaf);
            // proptree/1 back-compat defaults: an OLD exe omits these fields, and the
            // editor must then degrade to "show everything" (writable), never hide all.
            // NB: TryGetValue's 2nd arg is `out` -- it CLEARS the target even when the
            // key is absent, so a non-empty default (member_kind) must be applied ONLY
            // when the read returns False; is_writable is read via BVal so its default
            // survives.
            Leaf.IsWritable := True;
            Obj.TryGetValue<string>('path', Leaf.Path);
            Obj.TryGetValue<string>('type', Leaf.TypeName);
            Obj.TryGetValue<string>('declared_in', Leaf.DeclaredIn);
            Obj.TryGetValue<string>('kind', Leaf.Kind);
            if Obj.TryGetValue<Boolean>('is_class_typed', BVal) then
              Leaf.IsClassType := BVal;
            if Obj.TryGetValue<Boolean>('is_writable', BVal) then
              Leaf.IsWritable := BVal;
            Obj.TryGetValue<string>('visibility', Leaf.Visibility);
            if not Obj.TryGetValue<string>('member_kind', Leaf.MemberKind) then
              Leaf.MemberKind := 'property';
            List.Add(Leaf);
          end;
      Result.Leaves := List.ToArray;
    finally
      List.Free;
    end;
  finally
    Root.Free;
  end;
end;

{ TEngineAdapter }

constructor TEngineAdapter.Create(const AExePath: string; const ADbList: TArray<string>);
begin
  inherited Create;
  FExePath := AExePath;
  FDbList  := ADbList;
end;

procedure TEngineAdapter.SetDbs(const ADbs: TArray<string>);
begin
  FDbList := ADbs;
end;

function TEngineAdapter.DbList: TArray<string>;
begin
  Result := FDbList;
end;

function TEngineAdapter.DbArgsFor(const ADbs: TArray<string>): string;
var
  Db: string;
begin
  Result := '';
  for Db in ADbs do
    if Trim(Db) <> '' then
      Result := Result + Format(' --db "%s"', [Db]);
end;

function TEngineAdapter.DbArgs: string;
begin
  Result := DbArgsFor(FDbList);
end;

{$IFDEF MSWINDOWS}
function TEngineAdapter.RunCapture(const AArgs: string; out AOutput: string): Integer;
var
  SA       : TSecurityAttributes;
  ReadPipe : THandle;
  WritePipe: THandle;
  SI       : TStartupInfoW;
  PI       : TProcessInformation;
  Buf      : array[0..4095] of AnsiChar;
  BytesRead: DWORD;
  ExitCode : DWORD;
  CmdLine  : string;
  CmdW     : array of WideChar;
  SB       : TStringBuilder;
begin
  Result := -1;
  AOutput := '';
  FillChar(SA, SizeOf(SA), 0);
  SA.nLength := SizeOf(SA);
  SA.bInheritHandle := True;
  if not CreatePipe(ReadPipe, WritePipe, @SA, 0) then Exit;
  try
    FillChar(SI, SizeOf(SI), 0);
    SI.cb := SizeOf(SI);
    SI.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    SI.wShowWindow := SW_HIDE;
    SI.hStdOutput := WritePipe;
    SI.hStdError  := WritePipe;
    SI.hStdInput  := GetStdHandle(STD_INPUT_HANDLE);

    CmdLine := Format('"%s" %s', [FExePath, AArgs]);
    SetLength(CmdW, Length(CmdLine) + 1);
    Move(PChar(CmdLine)^, CmdW[0], (Length(CmdLine) + 1) * SizeOf(WideChar));

    FillChar(PI, SizeOf(PI), 0);
    if not CreateProcessW(nil, @CmdW[0], nil, nil, True,
         CREATE_NO_WINDOW, nil, nil, SI, PI) then Exit;
    CloseHandle(WritePipe);
    WritePipe := 0;

    // Bounded, non-blocking drain: poll the pipe so a pathological engine call
    // times out gracefully instead of freezing the editor's main thread on an
    // INFINITE wait. See ENGINE_TIMEOUT_MS for why the bound is where it is.
    var TimedOut: Boolean := False;
    SB := TStringBuilder.Create;
    try
      var Deadline: UInt64 := GetTickCount64 + ENGINE_TIMEOUT_MS;
      var Avail: DWORD := 0;
      repeat
        if PeekNamedPipe(ReadPipe, nil, 0, nil, @Avail, nil) and (Avail > 0) then
        begin
          BytesRead := 0;
          if not ReadFile(ReadPipe, Buf, SizeOf(Buf), BytesRead, nil) or (BytesRead = 0) then Break;
          SB.Append(string(AnsiString(Copy(Buf, 0, BytesRead))));
          Continue;                                // keep draining while bytes are ready
        end;
        if WaitForSingleObject(PI.hProcess, 40) = WAIT_OBJECT_0 then
        begin
          // process exited: drain any final buffered bytes, then stop
          while PeekNamedPipe(ReadPipe, nil, 0, nil, @Avail, nil) and (Avail > 0) do
          begin
            BytesRead := 0;
            if not ReadFile(ReadPipe, Buf, SizeOf(Buf), BytesRead, nil) or (BytesRead = 0) then Break;
            SB.Append(string(AnsiString(Copy(Buf, 0, BytesRead))));
          end;
          Break;
        end;
        if GetTickCount64 >= Deadline then
        begin
          TerminateProcess(PI.hProcess, DWORD(-1));
          WaitForSingleObject(PI.hProcess, 2000);
          TimedOut := True;
          Break;
        end;
      until False;
      AOutput := SB.ToString;
    finally
      SB.Free;
    end;

    if TimedOut then
    begin
      AOutput := AOutput + sLineBreak +
        Format('[timeout: engine call exceeded %d s]', [ENGINE_TIMEOUT_MS div 1000]);
      Result := 3;                                 // distinct code: timed out (not 0/1/2)
    end
    else if GetExitCodeProcess(PI.hProcess, ExitCode) then
      Result := Integer(ExitCode);
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread);
  finally
    if ReadPipe <> 0 then CloseHandle(ReadPipe);
    if WritePipe <> 0 then CloseHandle(WritePipe);
  end;
end;
{$ELSE}
function TEngineAdapter.RunCapture(const AArgs: string; out AOutput: string): Integer;
begin
  // Editor is Windows-only (VCL); non-Windows stub keeps the unit compilable.
  AOutput := '';
  Result := -1;
end;
{$ENDIF}

function TEngineAdapter.GetProptree(const AQname: string; out ATree: TProptree;
  out AError: string; out ANote: string; const AMinVisibility: string): Boolean;
var
  Output: string;
  Code  : Integer;
  QN    : string;
  VisArg: string;
  Ambig : Integer;
begin
  AError := '';
  ANote := '';
  ATree := Default(TProptree);
  // The pickers hand us a BARE class name (TcxButton); proptree --qname needs the
  // unit-qualified form (cxButtons.TcxButton). Qualify it first (no-op if already
  // qualified or not resolvable).
  QN := ResolveClassQName(AQname, Ambig);
  // Several classes carry that bare name -- TEdit, TButton and TLabel all have both an
  // FMX and a VCL declaration -- and only the engine's row order chose between them.
  // Silently returning an FMX property tree for a VCL form is the failure this reports.
  if Ambig > 1 then
    ANote := Format('%s: %d classes carry that name; used %s.', [AQname, Ambig, QN]);
  // Target surface (engine schema v17): --min-visibility published (DFM-streamable
  // props only) or public (adds public props + public fields); '' emits all leaves.
  // --refs-as-leaves IS on main (parsed in DRagLint.CLI.pas) and is passed on every
  // call: a TComponent-typed property is a REFERENCE to another component, not an
  // owned sub-object, so expanding it (Action.Owner.Name, DropDownMenu.Tag) invents
  // targets that cannot be assigned. Leaving such properties unexpanded is both the
  // correct target surface and what bounds the walk. Measured on cxButtons.TcxButton
  // against library-Win64 + ORM3, 3 runs each, 2026-07-29:
  //   --min-visibility published              2936 leaves, mean 18.22 s
  //   ... plus --refs-as-leaves                696 leaves, mean  6.96 s
  //   no --min-visibility                    36795 leaves, mean 20.11 s
  //   ... plus --refs-as-leaves              11692 leaves, mean  7.82 s
  // Name, Tag, Left and Top are present in all four. --min-visibility filters at
  // OUTPUT time and does not shorten the walk (hence ~2 s), whereas
  // --refs-as-leaves prunes the walk itself (~11 s).
  VisArg := '';
  if AMinVisibility <> '' then VisArg := ' --min-visibility ' + AMinVisibility;
  Code := RunCapture(Format('proptree --qname "%s"%s --refs-as-leaves --format json%s',
    [QN, VisArg, DbArgs]), Output);
  if Code = 3 then
  begin
    AError := Format('proptree TIMED OUT for %s after %d s -- the property tree is '
      + 'too large to enumerate. The call already passes --refs-as-leaves, which '
      + 'bounds reference expansion, so a timeout here means the walk is genuinely '
      + 'pathological (or the index is being written by another process). Try a '
      + 'different class, and report the qname.', [AQname, ENGINE_TIMEOUT_MS div 1000]);
    Exit(False);
  end;
  if Code <> 0 then
  begin
    AError := Format('proptree failed (exit %d) for %s. The type may not be indexed, '
      + 'or the index DB may be stale. Output: %s', [Code, AQname, Trim(Output)]);
    Exit(False);
  end;
  try
    ATree := ParseProptreeJson(Output);
    Result := True;
  except
    on E: Exception do
    begin
      AError := 'proptree JSON parse failed: ' + E.Message;
      Result := False;
    end;
  end;
end;

function TEngineAdapter.ListDescendantsOf(const AAncestor: string;
  out ANames: TArray<string>; out AError: string): Boolean;
begin
  Result := ListDescendantsOf(AAncestor, FDbList, ANames, AError);
end;

function TEngineAdapter.ListDescendantsOf(const AAncestor: string;
  const ADbs: TArray<string>; out ANames: TArray<string>; out AError: string): Boolean;
var
  Output: string;
  Code  : Integer;
  SL    : TStringList;
  Seen  : TStringList;
  Ln    : string;
begin
  AError := '';
  SetLength(ANames, 0);
  // `query descendants --of <A>` -> one bare class name per line (plus a possible
  // "(loaded defaults ...)" / "(none)" trailer we skip). Passing several --db
  // unions the results; we dedupe so a class in more than one DB appears once.
  Code := RunCapture(Format('query descendants --of "%s"%s',
    [AAncestor, DbArgsFor(ADbs)]), Output);
  if Code = 2 then
  begin
    AError := Format('query descendants failed (exit %d)', [Code]);
    Exit(False);
  end;
  SL := TStringList.Create;
  Seen := TStringList.Create;
  try
    Seen.Sorted := True; Seen.Duplicates := dupIgnore; Seen.CaseSensitive := False;
    SL.Text := Output;
    for Ln in SL do
    begin
      var T: string := Trim(Ln);
      if T = '' then Continue;
      if T = '(none)' then Continue;
      if Pos('loaded defaults', T) > 0 then Continue;
      // a class name is a single identifier token (no spaces, no ':')
      if (Pos(' ', T) > 0) or (Pos(':', T) > 0) then Continue;
      Seen.Add(T);
    end;
    ANames := Seen.ToStringArray;
    Result := True;
  finally
    Seen.Free;
    SL.Free;
  end;
end;

function TEngineAdapter.ListProjectUnits(out ANames: TArray<string>;
  out AError: string): Boolean;
var
  Output: string;
  Code  : Integer;
  SL    : TStringList;
  Ln    : string;
  Seen  : TStringList;
  p     : Integer;
begin
  AError := '';
  SetLength(ANames, 0);
  // `query find --no-docs --kind unit` -> "UnitName  [unit]  file:line"
  Code := RunCapture(Format('query find --no-docs --kind unit%s', [DbArgs]), Output);
  if Code = 2 then
  begin
    AError := Format('query find (units) failed (exit %d)', [Code]);
    Exit(False);
  end;
  SL := TStringList.Create;
  Seen := TStringList.Create;
  try
    Seen.Sorted := True; Seen.Duplicates := dupIgnore; Seen.CaseSensitive := False;
    SL.Text := Output;
    for Ln in SL do
    begin
      p := Pos('  [unit]', Ln);
      if p <= 0 then Continue;
      var U: string := Trim(Copy(Ln, 1, p - 1));
      if U <> '' then Seen.Add(U);
    end;
    ANames := Seen.ToStringArray;
    Result := True;
  finally
    SL.Free;
    Seen.Free;
  end;
end;

function TEngineAdapter.ResolveUnitFile(const AUnit: string): string;
var
  Output: string;
  Code  : Integer;
  Root  : TJSONValue;
  Arr   : TJSONArray;
  V     : TJSONValue;
  Obj   : TJSONObject;
  Kind, FileP: string;
begin
  Result := '';
  Code := RunCapture(Format('query --name "%s" --json%s', [AUnit, DbArgs]), Output);
  if Code = 2 then Exit;
  // `query --json` prints a JSON array; it may be followed by a "(loaded
  // defaults ...)" trailer, so slice from the first '[' to its matching ']'.
  var lb: Integer := Pos('[', Output);
  var rb: Integer := 0;
  for var i := Length(Output) downto 1 do
    if Output[i] = ']' then begin rb := i; Break; end;
  if (lb <= 0) or (rb <= lb) then Exit;
  Root := TJSONObject.ParseJSONValue(Copy(Output, lb, rb - lb + 1));
  if not (Root is TJSONArray) then begin Root.Free; Exit; end;
  try
    Arr := Root as TJSONArray;
    // Prefer the kind=unit row; fall back to the first row that has a file.
    for V in Arr do
      if V is TJSONObject then
      begin
        Obj := V as TJSONObject;
        Obj.TryGetValue<string>('kind', Kind);
        if SameText(Kind, 'unit') and Obj.TryGetValue<string>('file', FileP) then
          Exit(FileP);
      end;
    for V in Arr do
      if (V is TJSONObject) and (V as TJSONObject).TryGetValue<string>('file', FileP) then
        Exit(FileP);
  finally
    Root.Free;
  end;
end;

function TEngineAdapter.ResolveClassQName(const AName: string): string;
var
  Ambiguity: Integer;
begin
  Result := ResolveClassQName(AName, Ambiguity);
end;

function TEngineAdapter.ResolveClassQName(const AName: string;
  out AAmbiguity: Integer): string;
var
  Json   : string;
  Err    : string;
  Syms   : TArray<TQuerySymbol>;
  Classes: TArray<TQuerySymbol>;
  S      : TQuerySymbol;
  Sym    : TQuerySymbol;
  n      : Integer;
begin
  Result := AName;
  AAmbiguity := 0;
  // Already qualified (has a '.') or empty -> nothing to do.
  if (AName = '') or (Pos('.', AName) > 0) then Exit;
  if not QueryJsonFor(AName, Json, Err) then Exit;   // exit 1 = no hits, not a failure
  Syms := ParseQuerySymbols(Json);
  // Keep only class rows, then let the SHARED selector do the exact-name match and
  // the tie count. Taking "the first kind=class row" without comparing the name is
  // what this replaces: `--name` is a substring match, so that row is regularly a
  // different class whose name merely contains the request.
  SetLength(Classes, Length(Syms));
  n := 0;
  for S in Syms do
    if SameText(S.Kind, 'class') then
    begin
      Classes[n] := S;
      Inc(n);
    end;
  SetLength(Classes, n);
  if not SelectQuerySymbol(Classes, AName, Sym, AAmbiguity) then
  begin
    AAmbiguity := 0;
    Exit;
  end;
  if Sym.QualifiedName <> '' then Result := Sym.QualifiedName
  else AAmbiguity := 0;             // a row with no qualified_name qualifies nothing
end;

function TEngineAdapter.DeclaringUnitOf(const ATypeName: string): string;
var
  QN    : string ;
  DotPos: Integer;
begin
  QN := ResolveClassQName(ATypeName);
  DotPos := QN.LastIndexOf('.');
  if DotPos > 0 then Result := QN.Substring(0, DotPos)
  else Result := '';
end;

function TEngineAdapter.ListControlTypesInUnit(const AUnit: string;
  const AControlSet: TArray<string>; out ATypes: TArray<string>;
  out AError: string): Boolean;
var
  PasFile, DfmFile: string;
  SL  : TStringList;
  Seen: TStringList;
  Ln, T, TypeName: string;
  p, q: Integer;
begin
  // The components on a form are exactly the top-level + nested DFM objects, each
  // declared `object <Name>: <TType>` (or `inline <Name>: <TType>`). Read the
  // unit's companion .dfm and collect the distinct <TType> tokens. This is the
  // authoritative source -- it does not depend on class-ancestry resolution in
  // the library index, so legacy components (Orpheus/Raize/DevExpress) whose
  // ancestry is unresolved are still listed. Best-effort: [] when there is no dfm.
  AError := '';
  SetLength(ATypes, 0);

  PasFile := ResolveUnitFile(AUnit);
  if PasFile = '' then Exit(True);              // unit not indexed -> nothing to fill
  DfmFile := ChangeFileExt(PasFile, '.dfm');
  if not TFile.Exists(DfmFile) then
    DfmFile := ChangeFileExt(PasFile, '.DFM');  // some trees store upper-case ext
  if not TFile.Exists(DfmFile) then Exit(True); // non-form unit -> [] (best-effort)

  SL := TStringList.Create;
  Seen := TStringList.Create;
  try
    Seen.Sorted := True; Seen.Duplicates := dupIgnore; Seen.CaseSensitive := False;
    try
      SL.LoadFromFile(DfmFile);
    except
      on E: Exception do
      begin
        AError := 'could not read ' + DfmFile + ': ' + E.Message;
        Exit(False);
      end;
    end;
    for Ln in SL do
    begin
      T := TrimLeft(Ln);
      // Match a DFM object header: 'object <Name>: <TType>' or 'inline <Name>: <TType>'.
      if T.StartsWith('object ', True) then p := 8
      else if T.StartsWith('inline ', True) then p := 8
      else Continue;
      q := Pos(':', T);
      if q <= p then Continue;
      TypeName := Trim(Copy(T, q + 1, MaxInt));
      // The type token is a bare identifier; strip any trailing '[..]' index and
      // whitespace/comment. Keep only a leading T-prefixed identifier.
      var k: Integer := 1;
      while (k <= Length(TypeName)) and
            (CharInSet(TypeName[k], ['A'..'Z','a'..'z','0'..'9','_'])) do Inc(k);
      TypeName := Copy(TypeName, 1, k - 1);
      if (TypeName <> '') and CharInSet(TypeName[1], ['T','t']) then
        Seen.Add(TypeName);
    end;
    ATypes := Seen.ToStringArray;
    Result := True;
  finally
    SL.Free;
    Seen.Free;
  end;
end;

// Slice the first balanced bracket-ARRAY out of AText. The sibling of
// SliceJsonObject above, for the verbs that print a bare top-level array
// (`query --json`) rather than an object. Same string-literal-aware scan, so a
// '[' inside a JSON string value cannot open a phantom array, and the same
// reason for existing: RunCapture merges the child's stderr into stdout and the
// exe writes "(loaded defaults from ...)" to stderr on every call.
function SliceJsonArray(const AText: string): string;
var
  i, depth, startIdx: Integer;
  inStr: Boolean;
  esc  : Boolean;
begin
  Result := '';
  startIdx := 0; depth := 0; inStr := False; esc := False;
  for i := 1 to Length(AText) do
  begin
    if inStr then
    begin
      if esc then esc := False
      else if AText[i] = '\' then esc := True
      else if AText[i] = '"' then inStr := False;
      Continue;
    end;
    case AText[i] of
      '"': inStr := True;
      '[':
        begin
          if depth = 0 then startIdx := i;
          Inc(depth);
        end;
      ']':
        // depth > 0 guard: a stray ']' in the preamble must not be read as a close.
        if depth > 0 then
        begin
          Dec(depth);
          if depth = 0 then
            Exit(Copy(AText, startIdx, i - startIdx + 1));
        end;
    end;
  end;
end;

function ParseQuerySymbols(const AJson: string): TArray<TQuerySymbol>;
var
  Sliced: string;
  Root  : TJSONValue;
  V     : TJSONValue;
  Obj   : TJSONObject;
  List  : TList<TQuerySymbol>;
  Sym   : TQuerySymbol;
  N     : Integer;
begin
  Result := nil;
  Sliced := SliceJsonArray(AJson);
  if Sliced = '' then Exit;               // no array in the text -> no rows
  try
    Root := TJSONObject.ParseJSONValue(Sliced);
  except
    Root := nil;                          // malformed -> [] , never an exception
  end;
  if not (Root is TJSONArray) then
  begin
    Root.Free;                            // nil-safe
    Exit;
  end;
  List := TList<TQuerySymbol>.Create;
  try
    for V in (Root as TJSONArray) do
      if V is TJSONObject then
      begin
        Obj := V as TJSONObject;
        Sym := Default(TQuerySymbol);
        Obj.TryGetValue<string>('kind', Sym.Kind);
        Obj.TryGetValue<string>('name', Sym.Name);
        Obj.TryGetValue<string>('qualified_name', Sym.QualifiedName);
        Obj.TryGetValue<string>('file', Sym.FilePath);
        // "start_line" / "end_line" -- there is no "line" field.
        if Obj.TryGetValue<Integer>('start_line', N) then Sym.StartLine := N;
        if Obj.TryGetValue<Integer>('end_line', N) then Sym.EndLine := N;
        List.Add(Sym);
      end;
    Result := List.ToArray;
  finally
    List.Free;
    Root.Free;
  end;
end;

// How good an answer a row's kind is to "go to the definition of this TYPE".
// Lower is better.
//   0  a CONCRETE declaration -- the thing itself.
//   1  kind='type', which covers an ALIAS ('Vcl.Graphics.TFontPitch =
//      System.UITypes.TFontPitch') as well as sets and subranges. A real
//      declaration outranks an alias to it: it is what the user wanted to read,
//      and it is the only one EnumMembersOf can read members out of. Both rows
//      genuinely occur for the same name -- TFontPitch and TFontQuality each
//      have an enum in System.UITypes and an alias in Vcl.Graphics -- and the
//      engine's row order between them is not contractual, so ranking rather
//      than order has to decide.
//   2  anything else (property/field/param/local_var). A symbol that merely
//      shares the name is a poor answer, but still better than none.
function TypeKindTier(const AKind: string): Integer;
begin
  if SameText(AKind, 'class') or SameText(AKind, 'record')
     or SameText(AKind, 'interface') or SameText(AKind, 'enum') then Exit(0);
  if SameText(AKind, 'type') then Exit(1);
  Result := 2;
end;

function SelectQuerySymbol(const ASyms: TArray<TQuerySymbol>;
  const AWantedName: string; out ASym: TQuerySymbol;
  out AAmbiguity: Integer): Boolean;
var
  Bare     : string ;
  Qualified: Boolean;
  S        : TQuerySymbol;
  Best     : Integer;
  Tier     : Integer;
  DotPos   : Integer;
begin
  ASym := Default(TQuerySymbol);
  AAmbiguity := 0;
  Result := False;
  if AWantedName = '' then Exit;

  Bare := AWantedName;
  DotPos := LastDelimiter('.', Bare);
  Qualified := DotPos > 0;
  if Qualified then Bare := Copy(Bare, DotPos + 1, MaxInt);

  // Two passes over the same filter. The first finds the best tier present and its
  // first row; the second counts how many rows tied there. Counting cannot be folded
  // into the first pass without knowing the winning tier up front -- and the count is
  // the whole point: it is what stops a tie being reported as a certainty.
  Best := MaxInt;
  for S in ASyms do
  begin
    // Exact name only: `--name` matched a SUBSTRING, so most rows are other symbols.
    if not SameText(S.Name, Bare) then Continue;
    // A qualified request additionally pins the unit/owner, so 'Abcbtn.TabcButtonStyle'
    // cannot be answered by a same-named type from some other unit.
    if Qualified and not SameText(S.QualifiedName, AWantedName) then Continue;
    Tier := TypeKindTier(S.Kind);
    if Tier < Best then
    begin
      Best := Tier;
      ASym := S;          // first row of the best tier seen so far
      Result := True;
    end;
  end;
  if not Result then Exit;

  for S in ASyms do
  begin
    if not SameText(S.Name, Bare) then Continue;
    if Qualified and not SameText(S.QualifiedName, AWantedName) then Continue;
    if TypeKindTier(S.Kind) = Best then Inc(AAmbiguity);
  end;
end;

function ParseQueryLocation(const AJson, AWantedName: string; out AFile: string;
  out ALine: Integer; out AAmbiguity: Integer): Boolean;
var
  Sym: TQuerySymbol;
begin
  AFile := ''; ALine := 0;
  if not SelectQuerySymbol(ParseQuerySymbols(AJson), AWantedName, Sym, AAmbiguity) then
    Exit(False);
  if Sym.FilePath = '' then
  begin
    AAmbiguity := 0;
    Exit(False);                           // a row with no file is not a location
  end;
  AFile := Sym.FilePath;
  // The wire contract says a missing/garbled line is 1, so never emit 0: the file is
  // still the right answer and opening it at the top beats reporting nothing.
  if Sym.StartLine >= 1 then ALine := Sym.StartLine else ALine := 1;
  Result := True;
end;

// Replaces every brace comment / compiler directive, (* *) comment and // line
// comment with a COMMA -- not a space. A comma, because in an enum body the
// removed span is frequently an $IFDEF/$ELSE arm boundary sitting between two
// members that have no comma of their own:
//   RIO_IOCP_COMPLETION = 2 {$ELSE} rnctUnused,
// Blanking that to a space would fuse the two into one element and silently drop
// rnctUnused; a comma separates them, and empty elements are skipped anyway.
function StripEnumNoise(const AText: string): string;
var
  SB  : TStringBuilder;
  i, n: Integer;
begin
  SB := TStringBuilder.Create;
  try
    i := 1; n := Length(AText);
    while i <= n do
    begin
      if AText[i] = '{' then
      begin
        while (i <= n) and (AText[i] <> '}') do Inc(i);
        Inc(i);                                       // past the '}' (or past the end)
        SB.Append(',');
      end
      else if (i < n) and (AText[i] = '(') and (AText[i + 1] = '*') then
      begin
        Inc(i, 2);
        while (i < n) and not ((AText[i] = '*') and (AText[i + 1] = ')')) do Inc(i);
        Inc(i, 2);
        SB.Append(',');
      end
      else if (i < n) and (AText[i] = '/') and (AText[i + 1] = '/') then
      begin
        while (i <= n) and not CharInSet(AText[i], [#13, #10]) do Inc(i);
        SB.Append(',');
      end
      else
      begin
        SB.Append(AText[i]);
        Inc(i);
      end;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// The identifier an enum element starts with: 'RIO_EVENT_COMPLETION = 1' ->
// 'RIO_EVENT_COMPLETION'. '' when the element does not start with one (a bare
// ordinal, or an element left empty by StripEnumNoise).
function LeadingIdentifier(const AText: string): string;
var
  i, n, s: Integer;
begin
  Result := '';
  n := Length(AText);
  i := 1;
  while (i <= n) and CharInSet(AText[i], [#9, #10, #13, ' ']) do Inc(i);
  if (i > n) or not CharInSet(AText[i], ['A'..'Z', 'a'..'z', '_']) then Exit;
  s := i;
  while (i <= n) and CharInSet(AText[i], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(i);
  Result := Copy(AText, s, i - s);
end;

function ParseEnumMembers(const ADeclText: string; out AMembers: TArray<string>): Boolean;
var
  T     : string ;
  i, n  : Integer;
  eq    : Integer;
  depth : Integer;
  Inner : string ;
  Elem  : string ;
  Ident : string ;
  List  : TStringList;
  Seen  : TStringList;
  Start : Integer;
begin
  AMembers := nil;
  Result := False;
  T := StripEnumNoise(ADeclText);

  // An enum body is the '(' that follows the '=' with only whitespace between the
  // two. That single rule is what rejects 'TabcPicBtn = class(TButton)' (the word
  // 'class' sits in between) without needing to know every other type form.
  eq := Pos('=', T);
  if eq <= 0 then Exit;
  n := Length(T);
  i := eq + 1;
  while (i <= n) and CharInSet(T[i], [#9, #10, #13, ' ']) do Inc(i);
  if (i > n) or (T[i] <> '(') then Exit;

  Inc(i);                                     // past the '('
  Start := i;
  depth := 1;
  while i <= n do
  begin
    if T[i] = '(' then Inc(depth)
    else if T[i] = ')' then
    begin
      Dec(depth);
      if depth = 0 then Break;
    end;
    Inc(i);
  end;
  if depth <> 0 then Exit;                    // unbalanced -> not a declaration we understand
  Inner := Copy(T, Start, i - Start);

  List := TStringList.Create;
  Seen := TStringList.Create;
  try
    Seen.Sorted := True; Seen.Duplicates := dupIgnore; Seen.CaseSensitive := False;
    // Split on TOP-LEVEL commas; a nested '(...)' (an ordinal expression) is opaque.
    Elem := '';
    depth := 0;
    for i := 1 to Length(Inner) do
    begin
      if (Inner[i] = ',') and (depth = 0) then
      begin
        Ident := LeadingIdentifier(Elem);
        if (Ident <> '') and (Seen.IndexOf(Ident) < 0) then
        begin
          Seen.Add(Ident);
          List.Add(Ident);
        end;
        Elem := '';
        Continue;
      end;
      if Inner[i] = '(' then Inc(depth)
      else if (Inner[i] = ')') and (depth > 0) then Dec(depth);
      Elem := Elem + Inner[i];
    end;
    Ident := LeadingIdentifier(Elem);         // the last element has no trailing comma
    if (Ident <> '') and (Seen.IndexOf(Ident) < 0) then
    begin
      Seen.Add(Ident);
      List.Add(Ident);
    end;

    AMembers := List.ToStringArray;
    Result := List.Count > 0;
  finally
    Seen.Free;
    List.Free;
  end;
end;

{ Shared front half of ResolveTypeLocation / EnumMembersOf: run `query --name`
  and turn the engine's exit code into either usable JSON or a sentence the
  status bar can show. ANAME must be BARE -- `--name Abcbtn.TabcButtonStyle`
  matches nothing (measured), so the dotted form is stripped by the callers. }
function TEngineAdapter.QueryJsonFor(const AName: string;
  out AJson, AError: string): Boolean;
var
  Code: Integer;
begin
  AError := '';
  Code := RunCapture(Format('query --name "%s" --json%s', [AName, DbArgs]), AJson);
  case Code of
    0: Exit(True);
    // Exit 1 is "zero hits", NOT a broken call -- say so plainly rather than
    // reporting an engine failure for a type that is simply not indexed.
    1: AError := Format('"%s" is not in the current index set. Method-pointer types '
         + '(TNotifyEvent and friends) are among the declarations the index does not '
         + 'carry, and a type from an unindexed library will not be here either.',
         [AName]);
    3: AError := Format('query for "%s" timed out after %d s -- the index may be '
         + 'being written by another process.', [AName, ENGINE_TIMEOUT_MS div 1000]);
  else
    AError := Format('query failed (exit %d) for "%s": %s',
      [Code, AName, Trim(AJson)]);
  end;
  AJson := '';
  Result := False;
end;

{ The bare identifier of a possibly unit-qualified type name. }
function BareTypeName(const AType: string): string;
var
  DotPos: Integer;
begin
  Result := AType;
  DotPos := LastDelimiter('.', Result);
  if DotPos > 0 then Result := Copy(Result, DotPos + 1, MaxInt);
end;

function TEngineAdapter.ResolveTypeLocation(const AType: string; out AFile: string;
  out ALine: Integer; out AError: string): Boolean;
var
  Ambiguity: Integer;
begin
  Result := ResolveTypeLocation(AType, AFile, ALine, AError, Ambiguity);
end;

function TEngineAdapter.ResolveTypeLocation(const AType: string; out AFile: string;
  out ALine: Integer; out AError: string; out AAmbiguity: Integer): Boolean;
var
  Json: string;
begin
  AFile := ''; ALine := 0; AAmbiguity := 0;
  if Trim(AType) = '' then
  begin
    AError := 'No type to resolve.';
    Exit(False);
  end;
  if not QueryJsonFor(BareTypeName(AType), Json, AError) then Exit(False);
  Result := ParseQueryLocation(Json, AType, AFile, ALine, AAmbiguity);
  if not Result then
    AError := Format('No declaration named "%s" came back. `query --name` matches a '
      + 'SUBSTRING, so the index answered with other symbols whose names merely '
      + 'contain it.', [AType]);
end;

function TEngineAdapter.EnumMembersOf(const AType: string;
  out AMembers: TArray<string>; out AError: string): Boolean;
var
  Ambiguity: Integer;
begin
  Result := EnumMembersOf(AType, AMembers, AError, Ambiguity);
end;

function TEngineAdapter.EnumMembersOf(const AType: string;
  out AMembers: TArray<string>; out AError: string;
  out AAmbiguity: Integer): Boolean;
var
  Json : string;
  Sym  : TQuerySymbol;
  SL   : TStringList;
  Decl : string;
  i    : Integer;
begin
  AMembers := nil;
  AAmbiguity := 0;
  if Trim(AType) = '' then
  begin
    AError := 'No type to inspect.';
    Exit(False);
  end;
  if not QueryJsonFor(BareTypeName(AType), Json, AError) then Exit(False);
  if not SelectQuerySymbol(ParseQuerySymbols(Json), AType, Sym, AAmbiguity) then
  begin
    AError := Format('No declaration named "%s" came back.', [AType]);
    Exit(False);
  end;
  if not SameText(Sym.Kind, 'enum') then
  begin
    AError := Format('%s is a %s, not an enum.', [AType, Sym.Kind]);
    AAmbiguity := 0;
    Exit(False);
  end;
  // The index holds no member list and offers no children-of query, so the members
  // have to be read from the declaration the row points at.
  if (Sym.FilePath = '') or not TFile.Exists(Sym.FilePath) then
  begin
    AError := Format('%s is declared in %s, which is not readable from this machine.',
      [AType, Sym.FilePath]);
    AAmbiguity := 0;
    Exit(False);
  end;
  SL := TStringList.Create;
  try
    try
      SL.LoadFromFile(Sym.FilePath);
    except
      on E: Exception do
      begin
        AError := Format('could not read %s: %s', [Sym.FilePath, E.Message]);
        AAmbiguity := 0;
        Exit(False);
      end;
    end;
    if (Sym.StartLine < 1) or (Sym.StartLine > SL.Count) then
    begin
      AError := Format('%s: the index points at %s line %d, which that file does not '
        + 'have -- the index is stale relative to the source.',
        [AType, Sym.FilePath, Sym.StartLine]);
      AAmbiguity := 0;
      Exit(False);
    end;
    Decl := '';
    for i := Sym.StartLine to Sym.EndLine do
    begin
      if i > SL.Count then Break;
      Decl := Decl + SL[i - 1] + sLineBreak;   // SL is 0-based; the index is 1-based
    end;
    Result := ParseEnumMembers(Decl, AMembers);
    if not Result then
    begin
      AError := Format('%s is indexed as an enum, but no members could be read from '
        + '%s lines %d-%d.', [AType, Sym.FilePath, Sym.StartLine, Sym.EndLine]);
      AAmbiguity := 0;
    end;
  finally
    SL.Free;
  end;
end;

function TEngineAdapter.Scaffold(const AFrom, ATo: string; out ARules: string;
  out AError: string): Boolean;
var
  Code: Integer;
begin
  AError := '';
  Code := RunCapture(Format('convert-scaffold --from "%s" --to "%s"%s',
    [AFrom, ATo, DbArgs]), ARules);
  if Code <> 0 then
  begin
    AError := Format('convert-scaffold failed (exit %d): %s', [Code, Trim(ARules)]);
    ARules := '';
    Exit(False);
  end;
  Result := True;
end;

function TEngineAdapter.ValidateText(const ARulesText, AFrom, ATo: string): TValidateResult;
var
  Tmp   : string;
  Output: string;
  Code  : Integer;
  Args  : string;
  SL    : TStringList;
  Ln    : string;
begin
  Result.OK := False;
  Result.FirstError := '';
  Tmp := TPath.Combine(TPath.GetTempPath, 'convrules-validate-' +
    TPath.GetGUIDFileName + '.rules');
  try
    TFile.WriteAllText(Tmp, ARulesText, TEncoding.ASCII);
    Args := Format('convert-validate --rules "%s"', [Tmp]);
    if (AFrom <> '') and (ATo <> '') then
      Args := Args + Format(' --from "%s" --to "%s"', [AFrom, ATo]);
    Args := Args + DbArgs;
    Code := RunCapture(Args, Output);
    Result.OK := Code = 0;
    if not Result.OK then
    begin
      // surface the first non-empty, non-"loaded defaults" line
      SL := TStringList.Create;
      try
        SL.Text := Output;
        for Ln in SL do
          if (Trim(Ln) <> '') and (Pos('loaded defaults', Ln) = 0) then
          begin
            Result.FirstError := Trim(Ln);
            Break;
          end;
      finally
        SL.Free;
      end;
    end;
  finally
    if TFile.Exists(Tmp) then
      try TFile.Delete(Tmp); except end;
  end;
end;

end.
