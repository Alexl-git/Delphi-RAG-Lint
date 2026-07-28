unit ConvRules.CastLib;

{ Pure parser + resolver for the shipped class-cast library (.castlib).

  A .castlib defines named CLASS casts (TPicture -> TdxSmartGlyph, ...) that the
  scalar TCastFn enum cannot express. Each cast lists the From types it accepts, the
  To type(s) it yields, and realization hints (dfm strategy, pas template, todo text)
  the ENGINE convert-apply consumes -- the editor only needs name/accepts/yields to
  decide castability and emit the '#link ... : <name>' suffix.

  Pure + headless (no VCL, no engine, no process spawn) so it is unit-tested against
  inline fixtures. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  /// <summary>One named class cast from the .castlib.</summary>
  /// <remarks>Accepts/Yields are bare type names, matched case-insensitively by
  /// EXACT name (no ancestry walk in v1 -- list the concrete types). Dfm/Compat/
  /// PasTemplate/Todo are engine realization hints; the editor stores them verbatim
  /// and does not interpret them.</remarks>
  TCastDef = record
    Name       : string;
    Accepts    : TArray<string>;
    Yields     : TArray<string>;
    Dfm        : string;
    Compat     : string;
    PasTemplate: string;
    Todo       : string;
  end;

/// <summary>PURE: parse .castlib text into cast definitions. Tolerant -- skips blank
/// lines, '#' comments, and unknown keys; a malformed block (missing name or 'end')
/// is dropped without aborting the rest of the file.</summary>
function LoadCastLibText(const AText: string): TArray<TCastDef>;

/// <summary>Read + parse a .castlib file. Returns [] when APath is empty or missing
/// (class casts simply unavailable -- never raises).</summary>
/// <param name="APath">Absolute path to the .castlib, or '' for none.</param>
function LoadCastLib(const APath: string): TArray<TCastDef>;

/// <summary>The name of the class cast whose Accepts contains AFrom AND Yields
/// contains ATo (case-insensitive), or '' when no cast bridges the pair.</summary>
function ClassCastFor(const ADefs: TArray<TCastDef>; const AFrom, ATo: string): string;

implementation

uses
  System.IOUtils;

{ Split 'a, b ,c' -> ['a','b','c'], trimmed, empties dropped. }
function SplitList(const AValue: string): TArray<string>;
var
  parts: TArray<string>;
  p    : string;
  list : TList<string>;
begin
  list := TList<string>.Create;
  try
    parts := AValue.Split([',']);
    for p in parts do
      if Trim(p) <> '' then list.Add(Trim(p));
    Result := list.ToArray;
  finally
    list.Free;
  end;
end;

{ Strip one layer of surrounding single quotes from a value ('x' -> x). }
function Unquote(const AValue: string): string;
begin
  Result := Trim(AValue);
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

{ Case-insensitive membership over a bare-name array. }
function Has(const AArr: TArray<string>; const AName: string): Boolean;
var s: string;
begin
  for s in AArr do
    if SameText(s, AName) then Exit(True);
  Result := False;
end;

function LoadCastLibText(const AText: string): TArray<TCastDef>;
var
  SL   : TStringList;
  i, sp: Integer;
  Line, Key, Val: string;
  cur  : TCastDef;
  inBlk: Boolean;
  defs : TList<TCastDef>;
begin
  defs := TList<TCastDef>.Create;
  SL := TStringList.Create;
  try
    SL.Text := AText;
    inBlk := False;
    cur := Default(TCastDef);
    for i := 0 to SL.Count - 1 do
    begin
      Line := Trim(SL[i]);
      if (Line = '') or Line.StartsWith('#') then Continue;   // blank / comment
      sp := Pos(' ', Line);
      if sp > 0 then
      begin
        Key := LowerCase(Copy(Line, 1, sp - 1));
        Val := Trim(Copy(Line, sp + 1, MaxInt));
      end
      else
      begin
        Key := LowerCase(Line);
        Val := '';
      end;

      if Key = 'cast' then
      begin
        // a new block; a prior unclosed block (no 'end') is discarded
        inBlk := True;
        cur := Default(TCastDef);
        cur.Name := Val;
      end
      else if Key = 'end' then
      begin
        if inBlk and (cur.Name <> '') then defs.Add(cur);
        inBlk := False;
        cur := Default(TCastDef);
      end
      else if inBlk then
      begin
        if      Key = 'accepts' then cur.Accepts := SplitList(Val)
        else if Key = 'yields'  then cur.Yields := SplitList(Val)
        else if Key = 'dfm'     then cur.Dfm := Val
        else if Key = 'compat'  then cur.Compat := Val
        else if Key = 'pas'     then cur.PasTemplate := Unquote(Val)
        else if Key = 'todo'    then cur.Todo := Unquote(Val);
        // unknown keys tolerated (skipped)
      end;
    end;
    Result := defs.ToArray;
  finally
    SL.Free;
    defs.Free;
  end;
end;

function LoadCastLib(const APath: string): TArray<TCastDef>;
begin
  if (APath = '') or not TFile.Exists(APath) then Exit(nil);
  Result := LoadCastLibText(TFile.ReadAllText(APath));
end;

function ClassCastFor(const ADefs: TArray<TCastDef>; const AFrom, ATo: string): string;
var
  d: TCastDef;
begin
  Result := '';
  for d in ADefs do
    if Has(d.Accepts, AFrom) and Has(d.Yields, ATo) then Exit(d.Name);
end;

end.
