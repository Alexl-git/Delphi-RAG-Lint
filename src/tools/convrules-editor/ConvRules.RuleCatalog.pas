unit ConvRules.RuleCatalog;

{ A catalog of every conversion the rule-book FOLDER already covers: which From
  type, to which To type, in which file, at which line.

  WHY. The form-types panel greys a type we already have a rule for, and the owner
  asked that the answer come from a scanned FOLDER with a rebuildable index rather
  than from whatever books happen to be open. Storing the file and line is what
  later lets a save go back to the book a rule came from.

  WHAT IT IS NOT. This is an INDEX, not a second rule parser. It reuses
  ConvRules.Model's TRuleBook -- the same parser the editor loads books with -- so
  the catalog can never disagree with the editor about what a '#convert' says. The
  only thing this unit adds is the fold across files and the on-disk index.

  VCL-free. The folder scan and the index read/write touch the file system (as
  ConvRules.WorkingSet does); everything else is pure. }

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.StrUtils,
  System.Generics.Collections, System.Generics.Defaults,
  { TRuleBook, for HeaderIndexFor. ConvRules.Model uses only the RTL, so naming it
    here cannot create a cycle. }
  ConvRules.Model;

const
  /// <summary>The index file written into the scanned rules folder.</summary>
  CATALOG_INDEX_FILE = 'convrules-catalog.index';

  /// <summary>First line of the index; a file not starting with this is refused
  /// rather than half-read, so a future v2 cannot be silently misparsed as v1.</summary>
  CATALOG_INDEX_HEADER = '# drag-lint convrules catalog v1';

type
  /// <summary>One '#convert From -> To' the folder already covers.</summary>
  /// <remarks>FromType and ToType are stored EXACTLY as the book spells them,
  /// which is usually unit-qualified ('Bde.DBTables.TTable'). A DFM always writes
  /// the bare name, so match through FindRuleForType rather than comparing these
  /// directly. LineNo is 1-based, for display and for routing a later save back to
  /// the originating book.</remarks>
  TRuleCatalogEntry = record
    FromType: string;
    ToType  : string;
    FilePath: string;
    LineNo  : Integer;
  end;

  TRuleCatalog = TArray<TRuleCatalogEntry>;

  /// <summary>One source type that more than one rule claims to convert.</summary>
  /// <remarks>Entries are every catalog row covering that type, in scan order --
  /// which is also the order FindRuleForType silently picks the first of. Holding
  /// them ALL is the point: the fix is to delete or move one, and you cannot do
  /// that without being told where both are.</remarks>
  TCatalogDuplicate = record
    FromType: string;
    Entries : TRuleCatalog;
  end;

  TCatalogDuplicates = TArray<TCatalogDuplicate>;

  /// <summary>One '#mapping &lt;Name&gt; from &lt;Type&gt; to &lt;Class&gt;' DECLARATION.</summary>
  /// <remarks>A #mapping spans several physical lines: the declaration is followed by
  /// sibling #when/#else CLAUSE lines that repeat the name. Only the declaration is an
  /// entry here -- a clause is a USE of the name, not a second declaration of it, and
  /// counting clauses would report every multi-clause mapping as duplicated inside a
  /// single correct file. LineNo is 1-based, for display and for routing a later save
  /// back to the owning book.</remarks>
  TMappingCatalogEntry = record
    Name    : string;
    FilePath: string;
    LineNo  : Integer;
  end;

  TMappingCatalog = TArray<TMappingCatalogEntry>;

  /// <summary>One mapping name declared by more than one book.</summary>
  TMappingDuplicate = record
    Name   : string;
    Entries: TMappingCatalog;
  end;

  TMappingDuplicates = TArray<TMappingDuplicate>;

/// <summary>PURE: the bare type name of a possibly unit-qualified name.</summary>
/// <param name="AQualified">'Bde.DBTables.TTable' or 'TTable'.</param>
/// <returns>The text after the last dot; the input unchanged when there is none.</returns>
function BareTypeName(const AQualified: string): string;

/// <summary>PURE: every '#convert' in one rule-book text, as catalog entries.</summary>
/// <param name="AText">A .rules book. Text the grammar does not recognise is
/// ignored, never an error.</param>
/// <param name="APath">Recorded verbatim as each entry's FilePath; not read.</param>
/// <returns>One entry per '#convert', in file order.</returns>
/// <remarks>ToType is the TARGET TYPE ONLY. A header may carry extra uses-units
/// after a comma ('-> FireDAC.Comp.Client.TFDTable, FireDAC.Stan.Intf, ...'); those
/// are units to add, not alternative targets, and must not land in ToType.</remarks>
function CatalogFromText(const AText, APath: string): TRuleCatalog;

/// <summary>PURE: concatenates catalogs, preserving order.</summary>
function MergeCatalogs(const AParts: TArray<TRuleCatalog>): TRuleCatalog;

/// <summary>PURE: every source type claimed by more than one rule.</summary>
/// <param name="ACatalog">The scanned catalog.</param>
/// <returns>One entry per duplicated type, in first-appearance order; [] when the
/// corpus holds one rule per type, which is the intended state.</returns>
/// <remarks>THE RULE THIS ENFORCES (owner, 2026-09-08): an atomic rule lives in
/// exactly ONE file, because the same conversion in two places is how two versions
/// of it appear and diverge. Rules may be moved between files freely; they may not
/// be COPIED.
/// <para>Comparison is on the BARE type name, case-insensitively, matching
/// FindRuleForType -- so 'Bde.DBTables.TQuery' in one book and a bare 'TQuery' in
/// another ARE a duplicate, which is exactly the case a qualified-name comparison
/// would miss.</para>
/// <para>This is deliberately NOT folded into FindRuleForType. That function
/// answers "is this type covered", is called once per row while painting, and must
/// stay cheap; this one answers a corpus-health question and is called on rescan.</para></remarks>
function FindDuplicates(const ACatalog: TRuleCatalog): TCatalogDuplicates;

/// <summary>PURE: every '#mapping' DECLARATION in one rule-book text.</summary>
/// <param name="AText">A .rules book. Unrecognised text is ignored, never an error.</param>
/// <param name="APath">Recorded verbatim as each entry's FilePath; not read.</param>
/// <returns>One entry per declaration, in file order. Clause lines yield nothing.</returns>
/// <remarks>Uses the same TRuleBook the editor loads books with, so the catalog cannot
/// disagree with the editor about what a '#mapping' says. The declaration is identified
/// the way the MODEL marks it -- MapFromType &lt;&gt; '' -- never by re-parsing the line.</remarks>
function MappingCatalogFromText(const AText, APath: string): TMappingCatalog;

/// <summary>PURE: every mapping NAME declared more than once.</summary>
/// <param name="ACatalog">The scanned mapping catalog.</param>
/// <returns>One entry per duplicated name, in first-appearance order, each holding ALL
/// its sites in scan order; [] when every name is declared once.</returns>
/// <remarks>The invariant FindDuplicates enforces for types, keyed on the mapping name
/// instead: a name declared in two books is two versions of one mapping waiting to
/// diverge. Case-insensitive, as Pascal is.
/// <para>This is needed BEFORE atomization, not after. Splitting a #convert into its
/// own file separates it from the preamble #mapping its #apply names, and the tempting
/// repair is to copy the declaration across. This makes that visible.</para></remarks>
function FindDuplicateMappings(const ACatalog: TMappingCatalog): TMappingDuplicates;

type
  /// <summary>What CheckApplyIntegrity found in one composed text.</summary>
  TApplyIntegrity = record
    /// <summary>'#apply' names with no '#mapping' DECLARATION in the same text,
    /// in first-appearance order, de-duplicated case-insensitively.</summary>
    Unsatisfied      : TArray<string>;
    /// <summary>Mapping names declared more than once in the text.</summary>
    DuplicateMappings: TMappingDuplicates;
    /// <summary>True when both lists are empty -- the text is safe to hand to
    /// the engine as far as mappings are concerned.</summary>
    /// <returns>True when there is nothing to report.</returns>
    function OK: Boolean;
    /// <summary>One line naming what is wrong, for a status bar.</summary>
    /// <returns>A human-readable summary of both lists; '' when OK.</returns>
    function Summary: string;
  end;

/// <summary>PURE: every '#apply &lt;Name&gt;' in AText must have a matching
/// '#mapping &lt;Name&gt; from ... to ...' declaration in AText, and no name may be
/// declared twice.</summary>
/// <param name="AText">A rule-book text -- in practice a COMPOSED one.</param>
/// <returns>The two lists; see TApplyIntegrity.OK.</returns>
/// <remarks>This runs on the COMPOSED text, not on an authored book, and that is
/// the whole point. A composed job book is generated, disposable output for
/// --rules, so a #mapping carried into it from a source preamble is not a second
/// authored copy and does not breach the one-rule-one-place rule -- but an #apply
/// whose declaration stayed behind in a book that is not in the working set
/// produces a book the engine cannot apply, silently.
/// <para>A #when or #else CLAUSE repeats the name and is NOT a declaration; the
/// model marks the declaration with MapFromType &lt;&gt; '', the same rule
/// ConvRules.Mappings.ValidateMappings uses for mikUndefined, so the two cannot
/// disagree. Names compare case-insensitively, as Pascal does.</para></remarks>
function CheckApplyIntegrity(const AText: string): TApplyIntegrity;

/// <summary>PURE: the node index of the '#convert' header a catalog entry names.</summary>
/// <param name="ABook">The loaded owning book. nil yields -1.</param>
/// <param name="AEntry">A catalog entry; its LineNo is a HINT, its FromType decides.</param>
/// <returns>The 0-based index into ABook.Nodes, or -1 when this book converts no such type.</returns>
/// <remarks>LineNo is deliberately NOT trusted. The catalog is an index and the book
/// moves underneath it -- inserting one comment shifts every recorded line -- so the hint
/// is ACCEPTED ONLY IF the node it names is still an rnkConvert for the same bare type;
/// otherwise the first header converting that type wins. Trusting the number would select
/// a neighbouring rule, which looks plausible and is wrong.
/// <para>An out-of-range LineNo is a stale index, not a fault: it falls back like any
/// other miss and never raises.</para></remarks>
function HeaderIndexFor(ABook: TRuleBook; const AEntry: TRuleCatalogEntry): Integer;

/// <summary>PURE: the file name a NEW single-conversion atom should carry.</summary>
/// <param name="AFrom">The From type, bare or qualified.</param>
/// <param name="ATo">The To type AS WRITTEN ON THE HEADER -- any uses-units after a
/// comma are stripped here, the same way CatalogFromText derives ToType.</param>
/// <returns>'&lt;FromBare&gt;-to-&lt;ToBare&gt;.rules', or '' when either side is empty.</returns>
/// <remarks>THE CONVENTION IS OWNER RULING 1c AND IS NOT SETTLED. It is spelled once,
/// in ATOM_NAME_FMT, so changing it costs one line and cannot drift between callers.
/// <para>Characters illegal in a file name are replaced, never passed through: the
/// result is combined with a folder by the caller, and a name carrying a separator
/// would write outside it.</para></remarks>
function AtomFileNameFor(const AFrom, ATo: string): string;

/// <summary>A path in AFolder for AName that DOES NOT ALREADY EXIST.</summary>
/// <param name="AFolder">Target folder.</param>
/// <param name="AName">Desired file name, typically from AtomFileNameFor.</param>
/// <returns>AFolder\AName when free, else the first free '...-2', '...-3' variant.
/// '' when AName is empty.</returns>
/// <remarks>SAFETY, not convenience. The save path APPENDS to a file that already
/// exists, so handing back an occupied path would graft a new rule silently onto an
/// unrelated atom -- and the one-rule-one-file invariant would be broken by the very
/// command meant to uphold it. The suffix goes before the extension so the file stays
/// a '.rules' and keeps being scanned.</remarks>
function UniqueAtomPath(const AFolder, AName: string): string;

/// <summary>PURE: the first catalog entry converting ATypeName.</summary>
/// <param name="ACatalog">The catalog to search.</param>
/// <param name="ATypeName">A type name, bare or qualified.</param>
/// <param name="AEntry">Receives the matching entry; undefined when False.</param>
/// <returns>True when some book already converts this type.</returns>
/// <remarks>Matches on the BARE name at both ends, because the .dfm side is always
/// bare and the book side is usually qualified. Case-insensitive, as Pascal is.
/// FIRST match wins, so folder order decides which book is reported as the owner
/// when two cover the same type -- the panel shows which one.</remarks>
function FindRuleForType(const ACatalog: TRuleCatalog; const ATypeName: string;
  out AEntry: TRuleCatalogEntry): Boolean;

/// <summary>PURE: render a catalog as the on-disk index text.</summary>
/// <returns>CATALOG_INDEX_HEADER then one tab-separated
/// From/To/FilePath/LineNo record per entry, CRLF-terminated.</returns>
function CatalogToIndexText(const ACatalog: TRuleCatalog): string;

/// <summary>PURE: parse index text produced by CatalogToIndexText.</summary>
/// <param name="AText">Index file contents.</param>
/// <returns>The entries; empty when the header line does not match
/// CATALOG_INDEX_HEADER, or for any line that is blank, a comment, or does not
/// have four fields.</returns>
/// <remarks>Refusing the whole file on a bad header is deliberate: a partially
/// understood index would silently under-report coverage, which shows up as a type
/// looking un-ruled and inviting a duplicate rule.</remarks>
function CatalogFromIndexText(const AText: string): TRuleCatalog;

/// <summary>Scans a folder's '*.rules' books and builds the catalog.</summary>
/// <param name="AFolder">Folder to scan, not recursive. A missing folder yields an
/// empty catalog and no error.</param>
/// <param name="AErrors">One message per file that could not be read.</param>
/// <returns>The merged catalog, files in name order so the "first match wins" rule
/// in FindRuleForType is stable between runs.</returns>
function ScanRulesFolder(const AFolder: string; out AErrors: TArray<string>): TRuleCatalog;

implementation

const
  { Tab-separated field order of one index record. CatalogToIndexText writes them
    in exactly this order, so the two must move together. }
  IDX_FROM        = 0;
  IDX_TO          = 1;
  IDX_PATH        = 2;
  IDX_LINE        = 3;
  IDX_FIELD_COUNT = 4;

function BareTypeName(const AQualified: string): string;
var
  DotAt: Integer;
begin
  Result := Trim(AQualified);
  DotAt  := LastDelimiter('.', Result);
  if DotAt > 0 then
    Result := Copy(Result, DotAt + 1, MaxInt);
end;

function CatalogFromText(const AText, APath: string): TRuleCatalog;
var
  Book : TRuleBook;
  List : TList<TRuleCatalogEntry>;
  Idx  : Integer;
  Node : TRuleNode;
  Entry: TRuleCatalogEntry;
  ToT  : string;
  CommaAt: Integer;
begin
  List := TList<TRuleCatalogEntry>.Create;
  Book := TRuleBook.Create;
  try
    Book.LoadFromString(AText);
    // ConvertHeaders yields node indexes in file order, and TRuleBook parses ONE
    // node per physical line, so index+1 is the 1-based line number.
    for Idx in Book.ConvertHeaders do
    begin
      Node := Book.Nodes[Idx];

      ToT := Trim(Node.ToType);
      // Defence in depth: the model already splits trailing uses-units into Units,
      // but a target must never carry them even if that changes.
      CommaAt := Pos(',', ToT);
      if CommaAt > 0 then ToT := Trim(Copy(ToT, 1, CommaAt - 1));

      Entry.FromType := Trim(Node.FromType);
      Entry.ToType   := ToT;
      Entry.FilePath := APath;
      Entry.LineNo   := Idx + 1;
      List.Add(Entry);
    end;
    Result := List.ToArray;
  finally
    Book.Free;
    List.Free;
  end;
end;

function MergeCatalogs(const AParts: TArray<TRuleCatalog>): TRuleCatalog;
var
  List : TList<TRuleCatalogEntry>;
  Part : TRuleCatalog;
  Entry: TRuleCatalogEntry;
begin
  List := TList<TRuleCatalogEntry>.Create;
  try
    for Part in AParts do
      for Entry in Part do
        List.Add(Entry);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function MappingCatalogFromText(const AText, APath: string): TMappingCatalog;
var
  Book : TRuleBook;
  List : TList<TMappingCatalogEntry>;
  i    : Integer;
  Node : TRuleNode;
  Entry: TMappingCatalogEntry;
begin
  List := TList<TMappingCatalogEntry>.Create;
  Book := TRuleBook.Create;
  try
    Book.LoadFromString(AText);
    // TRuleBook parses ONE node per physical line, so i+1 is the 1-based line number.
    for i := 0 to Book.Nodes.Count - 1 do
    begin
      Node := Book.Nodes[i];
      if Node.Kind <> rnkMapping then Continue;
      // MapFromType is the MODEL's own marker for the declaration line. A #when or
      // #else clause carries the same MapName and an empty MapFromType; treating one
      // as a declaration would report BdeBatchMode -- 1 declaration, 5 clauses -- as a
      // six-way duplicate inside a single, entirely correct file.
      if Trim(Node.MapFromType) = '' then Continue;
      if Trim(Node.MapName) = '' then Continue;

      Entry.Name     := Trim(Node.MapName);
      Entry.FilePath := APath;
      Entry.LineNo   := i + 1;
      List.Add(Entry);
    end;
    Result := List.ToArray;
  finally
    Book.Free;
    List.Free;
  end;
end;

{ Owner ruling 1c lives HERE and nowhere else. }
const
  ATOM_NAME_FMT = '%s-to-%s.rules';

function AtomFileNameFor(const AFrom, ATo: string): string;
var
  F, T: string;
  CommaAt: Integer;

  { A file name may not carry a separator or any of the characters Windows reserves.
    Substitute rather than delete, so two different types cannot collapse onto one
    name. }
  function Sanitise(const AText: string): string;
  var
    Ch: Char;
  begin
    Result := '';
    for Ch in AText do
      if TPath.IsValidFileNameChar(Ch) then Result := Result + Ch
      else Result := Result + '_';
  end;

begin
  Result := '';
  T := Trim(ATo);
  // A header's target may be followed by uses-units: keep only the type.
  CommaAt := Pos(',', T);
  if CommaAt > 0 then T := Trim(Copy(T, 1, CommaAt - 1));

  F := Sanitise(BareTypeName(AFrom));
  T := Sanitise(BareTypeName(T));
  if (F = '') or (T = '') then Exit;

  Result := Format(ATOM_NAME_FMT, [F, T]);
end;

function UniqueAtomPath(const AFolder, AName: string): string;
var
  Base, Ext: string;
  n: Integer;
begin
  Result := '';
  if Trim(AName) = '' then Exit;

  Result := TPath.Combine(AFolder, AName);
  if not TFile.Exists(Result) then Exit;

  // Suffix BEFORE the extension: 'X-2.rules', never 'X.rules-2', or the new atom
  // would stop matching the '*.rules' folder scan and become invisible to the catalog.
  Base := TPath.GetFileNameWithoutExtension(AName);
  Ext  := TPath.GetExtension(AName);
  n := 2;
  repeat
    Result := TPath.Combine(AFolder, Format('%s-%d%s', [Base, n, Ext]));
    Inc(n);
  until not TFile.Exists(Result);
end;

function TApplyIntegrity.OK: Boolean;
begin
  Result := (Length(Unsatisfied) = 0) and (Length(DuplicateMappings) = 0);
end;

function TApplyIntegrity.Summary: string;
var
  Parts, Names: TArray<string>;
  D           : TMappingDuplicate;
begin
  Parts := nil;
  if Length(Unsatisfied) > 0 then
    Parts := Parts + ['#apply without a #mapping declaration: '
      + string.Join(', ', Unsatisfied)];
  if Length(DuplicateMappings) > 0 then
  begin
    Names := nil;
    for D in DuplicateMappings do
      Names := Names + [Format('%s (%d sites)', [D.Name, Length(D.Entries)])];
    Parts := Parts + ['#mapping declared more than once: ' + string.Join(', ', Names)];
  end;
  Result := string.Join('; ', Parts);
end;

function CheckApplyIntegrity(const AText: string): TApplyIntegrity;
var
  Book   : TRuleBook;
  Decl   : TMappingCatalog;
  Missing: TList<string>;
  Node   : TRuleNode;
  E      : TMappingCatalogEntry;
  Name, M: string;
  Found  : Boolean;
begin
  Result := Default(TApplyIntegrity);
  { Declarations only -- MappingCatalogFromText already discards #when/#else
    clauses, which repeat the name without declaring it. }
  Decl := MappingCatalogFromText(AText, '');
  Result.DuplicateMappings := FindDuplicateMappings(Decl);

  Book    := TRuleBook.Create;
  Missing := TList<string>.Create;
  try
    Book.LoadFromString(AText);
    for Node in Book.Nodes do
    begin
      if Node.Kind <> rnkApply then Continue;
      Name := Trim(Node.ApplyName);
      if Name = '' then Continue;

      Found := False;
      for E in Decl do
        if SameText(E.Name, Name) then
        begin
          Found := True;
          Break;
        end;
      if Found then Continue;

      { First-appearance order, de-duplicated: one missing name is one defect
        however many blocks apply it. }
      Found := False;
      for M in Missing do
        if SameText(M, Name) then
        begin
          Found := True;
          Break;
        end;
      if not Found then
        Missing.Add(Name);
    end;
    Result.Unsatisfied := Missing.ToArray;
  finally
    Missing.Free;
    Book.Free;
  end;
end;

function HeaderIndexFor(ABook: TRuleBook; const AEntry: TRuleCatalogEntry): Integer;
var
  Hint, i: Integer;
  Want   : string;

  function HeaderMatches(AIndex: Integer): Boolean;
  begin
    Result := (ABook.Nodes[AIndex].Kind = rnkConvert)
      and SameText(BareTypeName(ABook.Nodes[AIndex].FromType), Want);
  end;

begin
  Result := -1;
  if ABook = nil then Exit;
  Want := BareTypeName(AEntry.FromType);
  if Want = '' then Exit;

  // 1. The recorded line, accepted only if it still IS this rule's header.
  Hint := AEntry.LineNo - 1;
  if (Hint >= 0) and (Hint < ABook.Nodes.Count) and HeaderMatches(Hint) then
    Exit(Hint);

  // 2. Otherwise the index is stale: the TYPE is the durable key, so take the first
  //    header converting it. First, not last, to agree with FindRuleForType -- the
  //    panel already reports that site as the owner.
  for i := 0 to ABook.Nodes.Count - 1 do
    if HeaderMatches(i) then
      Exit(i);
end;

function FindDuplicateMappings(const ACatalog: TMappingCatalog): TMappingDuplicates;
var
  Groups: TDictionary<string, TMappingCatalog>;
  Order : TList<string>;                  // keys in FIRST-APPEARANCE order
  Found : TList<TMappingDuplicate>;
  Entry : TMappingCatalogEntry;
  Bucket: TMappingCatalog;
  Dup   : TMappingDuplicate;
  Key   : string;
begin
  Result := nil;
  Groups := TDictionary<string, TMappingCatalog>.Create;
  Order  := TList<string>.Create;
  Found  := TList<TMappingDuplicate>.Create;
  try
    for Entry in ACatalog do
    begin
      // A mapping name is an identifier and never qualified, so unlike the type
      // catalog there is nothing to strip here -- only case to fold.
      Key := UpperCase(Trim(Entry.Name));
      if Key = '' then Continue;

      if not Groups.TryGetValue(Key, Bucket) then
      begin
        Bucket := nil;
        Order.Add(Key);
      end;
      Groups.AddOrSetValue(Key, Bucket + [Entry]);
    end;

    // Walk Order, not Groups: a dictionary has no order, and a report that
    // reshuffles between runs is one nobody can diff.
    for Key in Order do
      if Groups.TryGetValue(Key, Bucket) and (Length(Bucket) > 1) then
      begin
        Dup.Name    := Bucket[0].Name;      // as the first site spells it
        Dup.Entries := Bucket;
        Found.Add(Dup);
      end;

    Result := Found.ToArray;
  finally
    Found.Free;
    Order.Free;
    Groups.Free;
  end;
end;

function FindDuplicates(const ACatalog: TRuleCatalog): TCatalogDuplicates;
var
  Groups: TDictionary<string, TRuleCatalog>;
  Order : TList<string>;                  // keys in FIRST-APPEARANCE order
  Found : TList<TCatalogDuplicate>;
  Entry : TRuleCatalogEntry;
  Bucket: TRuleCatalog;
  Dup   : TCatalogDuplicate;
  Key   : string;
begin
  Result := nil;
  Groups := TDictionary<string, TRuleCatalog>.Create;
  Order  := TList<string>.Create;
  Found  := TList<TCatalogDuplicate>.Create;
  try
    for Entry in ACatalog do
    begin
      // Bare + upper: a qualified 'Bde.DBTables.TQuery' and a bare 'TQuery' are
      // the SAME rule declared twice, and that is the case a naive comparison of
      // the written names would miss entirely.
      Key := UpperCase(BareTypeName(Entry.FromType));
      if Key = '' then Continue;

      if not Groups.TryGetValue(Key, Bucket) then
      begin
        Bucket := nil;
        Order.Add(Key);
      end;
      Groups.AddOrSetValue(Key, Bucket + [Entry]);
    end;

    // Walk Order, not Groups: a dictionary has no order, and a report that
    // reshuffles between runs is one nobody can diff.
    for Key in Order do
      if Groups.TryGetValue(Key, Bucket) and (Length(Bucket) > 1) then
      begin
        Dup.FromType := Bucket[0].FromType;   // as the first site spells it
        Dup.Entries  := Bucket;
        Found.Add(Dup);
      end;

    Result := Found.ToArray;
  finally
    Found.Free;
    Order.Free;
    Groups.Free;
  end;
end;

function FindRuleForType(const ACatalog: TRuleCatalog; const ATypeName: string;
  out AEntry: TRuleCatalogEntry): Boolean;
var
  Entry: TRuleCatalogEntry;
  Want : string;
begin
  AEntry := Default(TRuleCatalogEntry);
  Result := False;
  Want   := BareTypeName(ATypeName);
  if Want = '' then Exit;

  for Entry in ACatalog do
    if SameText(BareTypeName(Entry.FromType), Want) then
    begin
      AEntry := Entry;
      Exit(True);
    end;
end;

function CatalogToIndexText(const ACatalog: TRuleCatalog): string;
var
  SB   : TStringBuilder;
  Entry: TRuleCatalogEntry;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append(CATALOG_INDEX_HEADER).Append(#13#10);
    for Entry in ACatalog do
      SB.Append(Entry.FromType).Append(#9)
        .Append(Entry.ToType).Append(#9)
        .Append(Entry.FilePath).Append(#9)
        .Append(IntToStr(Entry.LineNo)).Append(#13#10);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function CatalogFromIndexText(const AText: string): TRuleCatalog;
var
  Lines: TStringList;
  List : TList<TRuleCatalogEntry>;
  i    : Integer;
  Parts: TArray<string>;
  Entry: TRuleCatalogEntry;
  Ln   : string;
begin
  Result := nil;
  if Trim(AText) = '' then Exit;

  Lines := TStringList.Create;
  List  := TList<TRuleCatalogEntry>.Create;
  try
    Lines.Text := AText;
    // A wrong or missing header refuses the WHOLE file -- see the doc comment.
    if (Lines.Count = 0) or (not StartsText(CATALOG_INDEX_HEADER, Trim(Lines[0]))) then
      Exit;

    for i := 1 to Lines.Count - 1 do
    begin
      Ln := Lines[i];
      if Trim(Ln) = '' then Continue;
      if StartsStr('#', Trim(Ln)) then Continue;

      Parts := Ln.Split([#9]);
      if Length(Parts) < IDX_FIELD_COUNT then Continue;

      Entry.FromType := Trim(Parts[IDX_FROM]);
      Entry.ToType   := Trim(Parts[IDX_TO]);
      Entry.FilePath := Trim(Parts[IDX_PATH]);
      Entry.LineNo   := StrToIntDef(Trim(Parts[IDX_LINE]), 0);
      List.Add(Entry);
    end;
    Result := List.ToArray;
  finally
    List.Free;
    Lines.Free;
  end;
end;

function ScanRulesFolder(const AFolder: string; out AErrors: TArray<string>): TRuleCatalog;
var
  Files : TArray<string>;
  Errs  : TList<string>;
  Parts : TArray<TRuleCatalog>;
  F     : string;
begin
  AErrors := nil;
  Result  := nil;
  if (Trim(AFolder) = '') or (not TDirectory.Exists(AFolder)) then Exit;

  Errs := TList<string>.Create;
  try
    Files := TDirectory.GetFiles(AFolder, '*.rules');
    // Name order, so FindRuleForType's "first match wins" is stable between runs
    // rather than depending on whatever order the file system hands back.
    TArray.Sort<string>(Files, TComparer<string>.Construct(
      function(const L, R: string): Integer
      begin
        Result := CompareText(L, R);
      end));

    Parts := nil;
    for F in Files do
      try
        Parts := Parts + [CatalogFromText(TFile.ReadAllText(F), F)];
      except
        on E: Exception do
          Errs.Add(Format('%s: %s', [ExtractFileName(F), E.Message]));
      end;

    Result  := MergeCatalogs(Parts);
    AErrors := Errs.ToArray;
  finally
    Errs.Free;
  end;
end;

end.
