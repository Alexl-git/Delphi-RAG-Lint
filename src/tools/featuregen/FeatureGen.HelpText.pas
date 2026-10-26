unit FeatureGen.HelpText;

{ P7 -- the verb reference of `drag-lint --help`, generated from the registry.

  Emits src\cli\DRagLint.CLI.HelpText.pas (one procedure, WriteVerbReference,
  one Writeln per line, 7-bit ASCII).

  Every public cli surface that carries a frozen block (helpOrder + help, seeded
  by `featuregen import-help --blocks`) contributes that block VERBATIM, in
  helpOrder. The reference is therefore byte-identical to the hand-written
  banner it replaced, which keeps every entry's surface hash (it hashes the
  verb's --help block) unchanged. A public surface with no block (a verb added
  after the freeze) is appended as its usage line, its pitfalls and a pointer
  to its feature page, unless a block already shows that usage line.
  The hand-written COMMON QUESTIONS table stays in DRagLint.CLI.pas. }

interface

uses
  FeatureGen.Model;

const
  /// <summary>Registry-relative path of the generated unit.</summary>
  HELPTEXT_UNIT_PATH = 'src\cli\DRagLint.CLI.HelpText.pas';

type
  /// <summary>One public cli surface as a sortable row of the verb reference.</summary>
  TRow = record
    Id: string;
    Verb: string;
    Sub: string;
    Order: Integer;
    EntryIndex: Integer;
    SurfaceIndex: Integer;
  end;

/// <summary>Total order of the verb-reference rows.</summary>
/// <param name="pA">First row.</param>
/// <param name="pB">Second row.</param>
/// <returns>Negative, zero or positive. Blocks (Order &gt; 0) first by Order, equal Order by entry Id (ordinal compare), then Verb, Sub, EntryIndex, SurfaceIndex; blockless rows by Verb, Sub, Id, EntryIndex, SurfaceIndex.</returns>
/// <remarks>TList.Sort is unstable; a tie on Order alone would let the generated block order flip between builds.</remarks>
function CompareRows(const pA, pB: TRow): Integer;

/// <summary>The lines of the generated verb reference, without Pascal quoting.</summary>
/// <param name="pReg">Loaded registry.</param>
/// <returns>Blocks in helpOrder, then blockless surfaces in verb order.</returns>
/// <remarks>Internal, planned and removed entries are skipped: they are not part of the public surface.</remarks>
function VerbReferenceLines(const pReg: TRegistry): TArray<string>;

/// <summary>The "Flag aliases:" section of --help, without Pascal quoting (docs\CLI-FLAG-ALIASES.md).</summary>
/// <param name="pAliases">Rows of features\flag-aliases.json.</param>
/// <returns>A header line, three lines of policy, one row per canonical flag (`  --canonical  also: --a, --b`) and a blank line; an empty array when pAliases is empty.</returns>
/// <remarks>The header matches the --help section-header shape (a capitalised word run ending in a colon), so the flag/verb scanners stop the last verb block there; the rows are the only --help lines allowed to name an alias.</remarks>
function FlagAliasLines(const pAliases: TArray<TFlagAlias>): TArray<string>;

/// <summary>The flag alias table as Markdown, for the CLI reference pages and the docs\AI-USAGE.md flag-aliases block.</summary>
/// <param name="pAliases">Rows of features\flag-aliases.json.</param>
/// <param name="pHeading">True prefixes a "## Flag aliases" heading (the CLI reference pages).</param>
/// <returns>A sentence of policy and a canonical / aliases / why table, LF line ends; '' when pAliases is empty.</returns>
function FlagAliasesMarkdown(const pAliases: TArray<TFlagAlias>; pHeading: Boolean): string;

/// <summary>The complete text of src\cli\DRagLint.CLI.HelpText.pas for pReg (LF line ends; the output writer converts to CRLF).</summary>
/// <param name="pReg">Loaded registry.</param>
/// <remarks>Emits WriteVerbReference, WriteFlagAliases (the "Flag aliases:" section, FlagAliasLines) and WriteVerbHelp.</remarks>
function RenderHelpTextUnit(const pReg: TRegistry): string;

implementation

uses
  System.SysUtils
  , System.RegularExpressions
  , System.Generics.Collections
  , System.Generics.Defaults;

const
  USAGE_INDENT = '  ';
  NOTE_INDENT = '       ';

function IsPublic(const pEntry: TFeatureEntry): Boolean;
begin
  Result := not (SameText(pEntry.Status, 'internal') or SameText(pEntry.Status, 'planned') or (pEntry.RemovedIn <> ''));
end;

{ Whitespace-insensitive form of a help line, for "is this usage line already shown". }
function Squeezed(const pLine: string): string;
begin
  Result := Trim(TRegEx.Replace(pLine, '\s+', ' '));
end;

function CompareRows(const pA, pB: TRow): Integer;
begin
  if (pA.Order > 0) and (pB.Order > 0) then
  begin
    Result := pA.Order - pB.Order;
    if Result = 0 then
      Result := CompareStr(pA.Id, pB.Id);
  end
  else if (pA.Order > 0) <> (pB.Order > 0) then
  begin
    if pA.Order > 0 then
      Exit(-1)
    else
      Exit(1);
  end
  else
  begin
    Result := CompareStr(pA.Verb, pB.Verb);
    if Result = 0 then
      Result := CompareStr(pA.Sub, pB.Sub);
    if Result = 0 then
      Result := CompareStr(pA.Id, pB.Id);
  end;
  if Result = 0 then
    Result := CompareStr(pA.Verb, pB.Verb);
  if Result = 0 then
    Result := CompareStr(pA.Sub, pB.Sub);
  if Result = 0 then
    Result := pA.EntryIndex - pB.EntryIndex;
  if Result = 0 then
    Result := pA.SurfaceIndex - pB.SurfaceIndex;
end;

function PublicRows(const pReg: TRegistry): TArray<TRow>;
var
  lList: TList<TRow>;
  lE, lS: Integer;
  lRow: TRow;
begin
  lList := TList<TRow>.Create;
  try
    for lE := 0 to High(pReg.Entries) do
    begin
      if not IsPublic(pReg.Entries[lE]) then
        Continue;
      for lS := 0 to High(pReg.Entries[lE].Surfaces) do
        if SameText(pReg.Entries[lE].Surfaces[lS].Kind, 'cli') and (pReg.Entries[lE].Surfaces[lS].Usage <> '') then
        begin
          lRow.Id := pReg.Entries[lE].Id;
          lRow.Verb := pReg.Entries[lE].Surfaces[lS].Verb;
          lRow.Sub := pReg.Entries[lE].Surfaces[lS].Sub;
          lRow.Order := 0;
          if Length(pReg.Entries[lE].Surfaces[lS].Help) > 0 then
            lRow.Order := pReg.Entries[lE].Surfaces[lS].HelpOrder;
          lRow.EntryIndex := lE;
          lRow.SurfaceIndex := lS;
          lList.Add(lRow);
        end;
    end;
    lList.Sort(TComparer<TRow>.Construct(CompareRows));
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

function VerbReferenceLines(const pReg: TRegistry): TArray<string>;
var
  lOut: TList<string>;
  lShown: TDictionary<string, Boolean>;
  lRow: TRow;
  lE: TFeatureEntry;
  lSurf: TSurface;
  lLine, lPit: string;
begin
  lOut := TList<string>.Create;
  lShown := TDictionary<string, Boolean>.Create;
  try
    for lRow in PublicRows(pReg) do
      if lRow.Order > 0 then
        for lLine in pReg.Entries[lRow.EntryIndex].Surfaces[lRow.SurfaceIndex].Help do
        begin
          lOut.Add(lLine);
          lShown.AddOrSetValue(Squeezed(lLine), True);
        end;
    for lRow in PublicRows(pReg) do
    begin
      if lRow.Order > 0 then
        Continue;
      lE := pReg.Entries[lRow.EntryIndex];
      lSurf := lE.Surfaces[lRow.SurfaceIndex];
      if lShown.ContainsKey(Squeezed(USAGE_INDENT + lSurf.Usage)) then
        Continue;
      lShown.AddOrSetValue(Squeezed(USAGE_INDENT + lSurf.Usage), True);
      lOut.Add(USAGE_INDENT + lSurf.Usage);
      for lPit in lE.Pitfalls do
        lOut.Add(NOTE_INDENT + '^ ' + lPit);
      if lE.WikiPage <> '' then
        lOut.Add(NOTE_INDENT + 'see wiki page: ' + lE.WikiPage);
    end;
    Result := lOut.ToArray;
  finally
    lShown.Free;
    lOut.Free;
  end;
end;

const
  /// <summary>Longest raw chunk of one Writeln literal; dcc refuses a source line over 1023 characters (F2069).</summary>
  MAX_LITERAL_CHUNK = 800;

{ One Writeln statement for pLine; a long line becomes a concatenation of quoted chunks, one per source line. }
function WriteLnStatement(const pLine: string): string;
var
  lPos: Integer;
begin
  if Length(pLine) <= MAX_LITERAL_CHUNK then
    Exit('  Writeln(''' + pLine.Replace('''', '''''') + ''');'#10);
  Result := '  Writeln(';
  lPos := 1;
  while lPos <= Length(pLine) do
  begin
    if lPos > 1 then
      Result := Result + ' +'#10'    ';
    Result := Result + '''' + Copy(pLine, lPos, MAX_LITERAL_CHUNK).Replace('''', '''''') + '''';
    Inc(lPos, MAX_LITERAL_CHUNK);
  end;
  Result := Result + ');'#10;
end;
{ WriteVerbHelp: one branch per verb that has help blocks (public surfaces, helpOrder > 0), in helpOrder. }
function RenderVerbHelpFunction(const pReg: TRegistry): string;
var
  lSb: TStringBuilder;
  lVerbs: TList<string>;
  lRow: TRow;
  lVerb, lLine: string;
begin
  lSb := TStringBuilder.Create;
  lVerbs := TList<string>.Create;
  try
    for lRow in PublicRows(pReg) do
      if (lRow.Order > 0) and not lVerbs.Contains(lRow.Verb) then
        lVerbs.Add(lRow.Verb);
    lSb.Append('function WriteVerbHelp(const pVerb: string): Boolean;  // dl:ok method-too-long@44f1 -- GENERATED: one Writeln per registry help line'#10);
    lSb.Append('begin'#10);
    lSb.Append('  Result := True;'#10);
    for lVerb in lVerbs do
    begin
      lSb.Append('  if pVerb = ''' + lVerb.Replace('''', '''''') + ''' then'#10);
      lSb.Append('  begin'#10);
      for lRow in PublicRows(pReg) do
        if (lRow.Order > 0) and (lRow.Verb = lVerb) then
          for lLine in pReg.Entries[lRow.EntryIndex].Surfaces[lRow.SurfaceIndex].Help do
            lSb.Append('  ' + WritelnStatement(lLine));
      lSb.Append('    Exit;'#10);
      lSb.Append('  end;'#10);
    end;
    lSb.Append('  Result := False;'#10);
    lSb.Append('end;'#10#10);
    Result := lSb.ToString;
  finally
    lVerbs.Free;
    lSb.Free;
  end;
end;

const
  /// <summary>Column the "also:" of an alias row starts after (the longest canonical flag plus a gap).</summary>
  ALIAS_CANON_WIDTH = 22;

function FlagAliasLines(const pAliases: TArray<TFlagAlias>): TArray<string>;
var
  lA: TFlagAlias;
begin
  Result := nil;
  if Length(pAliases) = 0 then
    Exit;
  Result := ['Flag aliases:',
    '  Every verb line above names the CANONICAL spelling of a flag. Each alias below is accepted',
    '  wherever its canonical flag is and means exactly the same, so scripts that use one keep',
    '  working; write the canonical spelling. Policy: docs\CLI-FLAG-ALIASES.md.'];
  for lA in pAliases do
    Result := Result + [USAGE_INDENT + lA.Canonical.PadRight(ALIAS_CANON_WIDTH) + ' also: ' + string.Join(', ', lA.Aliases)];
  Result := Result + [''];
end;

function FlagAliasesMarkdown(const pAliases: TArray<TFlagAlias>; pHeading: Boolean): string;
var
  lA: TFlagAlias;
  lSb: TStringBuilder;
begin
  if Length(pAliases) = 0 then
    Exit('');
  lSb := TStringBuilder.Create;
  try
    if pHeading then
      lSb.Append('## Flag aliases'#10#10);
    lSb.Append('A verb''s usage line names the canonical flag only. Each alias is accepted wherever its canonical flag is and means '
      + 'exactly the same, so scripts that use one keep working; write the canonical spelling. `drag-lint --help` lists them '
      + 'in its "Flag aliases:" section. Policy: `docs/CLI-FLAG-ALIASES.md`.'#10#10);
    lSb.Append('| Canonical | Aliases | Why |'#10'|---|---|---|'#10);
    for lA in pAliases do
      lSb.Append('| `' + lA.Canonical + '` | `' + string.Join('`, `', lA.Aliases) + '` | ' + lA.Reason + ' |'#10);
    lSb.Append(#10);
    Result := lSb.ToString;
  finally
    lSb.Free;
  end;
end;

function RenderHelpTextUnit(const pReg: TRegistry): string;
var
  lSb: TStringBuilder;
  lLine: string;
begin
  lSb := TStringBuilder.Create;
  try
    lSb.Append('unit DRagLint.CLI.HelpText;'#10#10);
    lSb.Append('{ GENERATED by featuregen from features\entries -- do not edit; run featuregen build --all.'#10);
    lSb.Append('  The verb reference of drag-lint --help (P7). COMMON QUESTIONS stays in DRagLint.CLI.pas. }'#10#10);
    lSb.Append('interface'#10#10);
    lSb.Append('/// <summary>Writes the generated verb reference of --help to standard output.</summary>'#10);
    lSb.Append('procedure WriteVerbReference;'#10#10);
    lSb.Append('/// <summary>Writes the "Flag aliases:" section of --help (features\flag-aliases.json; policy docs\CLI-FLAG-ALIASES.md).</summary>'#10);
    lSb.Append('procedure WriteFlagAliases;'#10#10);
    lSb.Append('/// <summary>Writes the own help of one verb: the help lines of its registry surfaces, in helpOrder.</summary>'#10);
    lSb.Append('/// <param name="pVerb">Verb name, e.g. menu-tree.</param>'#10);
    lSb.Append('/// <returns>True when the registry carries help lines for pVerb (and they were written); False writes nothing.</returns>'#10);
    lSb.Append('function WriteVerbHelp(const pVerb: string): Boolean;'#10#10);
    lSb.Append('implementation'#10#10);
    lSb.Append('procedure WriteVerbReference;  // dl:ok method-too-long@1e0d -- GENERATED: one Writeln per registry help line; the length follows the verb count'#10);
    lSb.Append('begin'#10);
    for lLine in VerbReferenceLines(pReg) do
      lSb.Append(WritelnStatement(lLine));
    lSb.Append('end;'#10#10);
    lSb.Append('procedure WriteFlagAliases;'#10);
    lSb.Append('begin'#10);
    for lLine in FlagAliasLines(pReg.FlagAliases) do
      lSb.Append(WritelnStatement(lLine));
    lSb.Append('end;'#10#10);
    lSb.Append(RenderVerbHelpFunction(pReg));
    lSb.Append('end.'#10);
    Result := lSb.ToString;
  finally
    lSb.Free;
  end;
end;

end.
