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
  System.Generics.Collections, System.Generics.Defaults;

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

uses
  ConvRules.Model;

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
