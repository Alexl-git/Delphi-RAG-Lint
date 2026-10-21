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

/// <summary>The lines of the generated verb reference, without Pascal quoting.</summary>
/// <param name="pReg">Loaded registry.</param>
/// <returns>Blocks in helpOrder, then blockless surfaces in verb order.</returns>
/// <remarks>Internal, planned and removed entries are skipped: they are not part of the public surface.</remarks>
function VerbReferenceLines(const pReg: TRegistry): TArray<string>;

/// <summary>The complete text of src\cli\DRagLint.CLI.HelpText.pas for pReg (LF line ends; the output writer converts to CRLF).</summary>
/// <param name="pReg">Loaded registry.</param>
function RenderHelpTextUnit(const pReg: TRegistry): string;

implementation

uses
  System.SysUtils
  , System.RegularExpressions
  , System.Generics.Collections
  , System.Generics.Defaults;

type
  TRow = record
    Verb: string;
    Sub: string;
    Order: Integer;
    EntryIndex: Integer;
    SurfaceIndex: Integer;
  end;

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
    Exit(pA.Order - pB.Order);
  if (pA.Order > 0) <> (pB.Order > 0) then
    if pA.Order > 0 then
      Exit(-1)
    else
      Exit(1);
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
    lSb.Append('implementation'#10#10);
    lSb.Append('procedure WriteVerbReference;  // dl:ok method-too-long@889d -- GENERATED: one Writeln per registry help line; the length follows the verb count'#10);
    lSb.Append('begin'#10);
    for lLine in VerbReferenceLines(pReg) do
      lSb.Append(WritelnStatement(lLine));
    lSb.Append('end;'#10#10);
    lSb.Append('end.'#10);
    Result := lSb.ToString;
  finally
    lSb.Free;
  end;
end;

end.
