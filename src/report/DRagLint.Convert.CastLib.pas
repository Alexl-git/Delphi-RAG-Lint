unit DRagLint.Convert.CastLib;

{ Pure parser + resolver for the shipped cast library (.castlib).

  A .castlib defines two named block kinds the scalar TCastFn enum cannot
  express:

    cast <Name> ... end   -- a CLASS cast (TPicture -> TdxSmartGlyph): which From
                             types it accepts, which To type it yields, plus
                             realization hints.
    enum <Name> ... end   -- an ENUM cast (TabcButtonLayout -> TButtonLayout):
                             member-by-member value translation.

  Both are named by the DSL's '#link To <- From : <Name>' suffix.

  WHY THIS UNIT MOVED HERE (2026-09-05). It was ConvRules.CastLib under
  src\tools\convrules-editor\, so only the editor could read it -- and the
  ENGINE is what has to perform a cast. The editor still uses it (name/accepts/
  yields decide castability and emit the ': <name>' suffix); it now imports it
  from src\report\ instead of owning it. One parser, two consumers, no drift.

  The CLASS cast's realization hints (dfm/compat/pas/todo) remain EDITOR-SIDE:
  the engine reads name/accepts/yields to know a cast exists, and still refuses
  to rewrite a .pas access site for a link carrying one rather than renaming
  without performing the conversion. The ENUM cast IS executed -- see
  EnumCastValue.

  Pure + headless (no VCL, no engine, no store, no process spawn), so it is
  unit-tested against inline fixtures. }

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

  /// <summary>One member pair of an enum cast: the source member name and the
  /// target member name it becomes.</summary>
  TEnumPair = record
    FromMember: string;
    ToMember  : string;
  end;

  /// <summary>One named ENUM cast: member-by-member value translation between
  /// two enum types.</summary>
  /// <remarks>
  /// The grammar mirrors the two DSLs it sits between, deliberately, so an
  /// author already writing rule books has nothing new to learn:
  ///
  /// <code>
  /// enum ButtonLayout
  ///   from Abcbtn.TabcButtonLayout
  ///   to   Vcl.Buttons.TButtonLayout
  ///   map  ablGlyphLeft -&gt; blGlyphLeft
  ///   map  ablGlyphRight -&gt; blGlyphRight
  ///   else blGlyphLeft
  ///   todo 'ablGlyphTop has no counterpart'
  /// end
  /// </code>
  ///
  /// `from`/`to` match `#mapping &lt;Name&gt; from &lt;T&gt; to &lt;T&gt;`;
  /// the `-&gt;` in `map` matches a `#when ... -&gt; ...` branch; `else` matches
  /// `#else`. One pair per line so the file stays diffable and the editor can
  /// append a line without rewriting one.
  ///
  /// MATCHING IS BY NAME, NOT ORDINAL, and that is a deliberate rule rather
  /// than a limitation. Two enums being converted are different types whose
  /// members correspond by MEANING; equal ordinals across unrelated types are a
  /// coincidence, not evidence. (The index does store a correct ordinal for
  /// every member, explicit-valued ones included, so ordinal remains available
  /// as an editor SUGGESTION -- never as the rule.)
  ///
  /// Fallback is '' when the block declares no `else`, and an unmatched value
  /// is then reported rather than guessed at.
  /// </remarks>
  TEnumDef = record
    Name    : string;
    FromType: string;
    ToType  : string;
    Pairs   : TArray<TEnumPair>;
    Fallback: string;
    Todo    : string;
  end;

  /// <summary>Everything one .castlib file declares.</summary>
  TCastLib = record
    Casts: TArray<TCastDef>;
    Enums: TArray<TEnumDef>;
  end;

/// <summary>PURE: parse .castlib text into cast definitions. Tolerant -- skips blank
/// lines, '#' comments, and unknown keys; a malformed block (missing name or 'end')
/// is dropped without aborting the rest of the file.</summary>
function LoadCastLibText(const AText: string): TArray<TCastDef>;

/// <summary>PURE: parse .castlib text into BOTH block kinds.</summary>
/// <remarks>Same tolerance as LoadCastLibText, which is now a thin wrapper over
/// this so the two can never disagree about the block grammar.</remarks>
function ParseCastLibText(const AText: string): TCastLib;

/// <summary>Read + parse a .castlib file. Returns [] when APath is empty or missing
/// (class casts simply unavailable -- never raises).</summary>
/// <param name="APath">Absolute path to the .castlib, or '' for none.</param>
function LoadCastLib(const APath: string): TArray<TCastDef>;

/// <summary>Read + parse a .castlib file into both block kinds. Returns an empty
/// record when APath is empty or missing -- never raises.</summary>
function ParseCastLib(const APath: string): TCastLib;

/// <summary>The name of the class cast whose Accepts contains AFrom AND Yields
/// contains ATo (case-insensitive), or '' when no cast bridges the pair.</summary>
function ClassCastFor(const ADefs: TArray<TCastDef>; const AFrom, ATo: string): string;

/// <summary>Find the enum cast named AName (case-insensitive).</summary>
/// <returns>True and fills ADef when found.</returns>
function FindEnumCast(const ALib: TCastLib; const AName: string;
  out ADef: TEnumDef): Boolean;

/// <summary>Translate one source enum member through an enum cast.</summary>
/// <param name="ADef">The cast to apply.</param>
/// <param name="AValue">The source member name, as it appears in the .dfm.</param>
/// <param name="AResult">The translated member name.</param>
/// <returns>True when a `map` pair matched, or the block declared an `else`.
/// False means the value is unmapped AND there is no fallback -- the caller must
/// REPORT that rather than emit anything, because inventing a member of the
/// target enum is how a form acquires a value nobody chose.</returns>
function EnumCastValue(const ADef: TEnumDef; const AValue: string;
  out AResult: string): Boolean;

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

{ Split 'a -> b' into its two sides. False when the arrow or either side is
  missing -- a half-written pair is dropped rather than stored as a rule that
  maps something to nothing. }
function SplitArrow(const AValue: string; out ALeft, ARight: string): Boolean;
var p: Integer;
begin
  ALeft := '';
  ARight := '';
  p := Pos('->', AValue);
  if p <= 0 then Exit(False);
  ALeft  := Trim(Copy(AValue, 1, p - 1));
  ARight := Trim(Copy(AValue, p + 2, MaxInt));
  Result := (ALeft <> '') and (ARight <> '');
end;

function ParseCastLibText(const AText: string): TCastLib;
var
  SL   : TStringList;
  i, sp: Integer;
  Line, Key, Val, L, R: string;
  cur  : TCastDef;
  curE : TEnumDef;
  pair : TEnumPair;
  inCast, inEnum: Boolean;
  casts: TList<TCastDef>;
  enums: TList<TEnumDef>;
begin
  Result := Default(TCastLib);
  casts := TList<TCastDef>.Create;
  enums := TList<TEnumDef>.Create;
  SL := TStringList.Create;
  try
    SL.Text := AText;
    inCast := False;
    inEnum := False;
    cur  := Default(TCastDef);
    curE := Default(TEnumDef);
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
        inCast := True;
        inEnum := False;
        cur := Default(TCastDef);
        cur.Name := Val;
      end
      else if Key = 'enum' then
      begin
        inEnum := True;
        inCast := False;
        curE := Default(TEnumDef);
        curE.Name := Val;
      end
      else if Key = 'end' then
      begin
        if inCast and (cur.Name <> '') then casts.Add(cur);
        if inEnum and (curE.Name <> '') then enums.Add(curE);
        inCast := False;
        inEnum := False;
        cur  := Default(TCastDef);
        curE := Default(TEnumDef);
      end
      else if inCast then
      begin
        if      Key = 'accepts' then cur.Accepts := SplitList(Val)
        else if Key = 'yields'  then cur.Yields := SplitList(Val)
        else if Key = 'dfm'     then cur.Dfm := Val
        else if Key = 'compat'  then cur.Compat := Val
        else if Key = 'pas'     then cur.PasTemplate := Unquote(Val)
        else if Key = 'todo'    then cur.Todo := Unquote(Val);
        // unknown keys tolerated (skipped)
      end
      else if inEnum then
      begin
        if      Key = 'from' then curE.FromType := Val
        else if Key = 'to'   then curE.ToType := Val
        else if Key = 'else' then curE.Fallback := Val
        else if Key = 'todo' then curE.Todo := Unquote(Val)
        else if Key = 'map'  then
        begin
          if SplitArrow(Val, L, R) then
          begin
            pair := Default(TEnumPair);
            pair.FromMember := L;
            pair.ToMember   := R;
            curE.Pairs := curE.Pairs + [pair];
          end;
        end;
        // unknown keys tolerated (skipped)
      end;
    end;
    Result.Casts := casts.ToArray;
    Result.Enums := enums.ToArray;
  finally
    SL.Free;
    casts.Free;
    enums.Free;
  end;
end;

function LoadCastLibText(const AText: string): TArray<TCastDef>;
begin
  Result := ParseCastLibText(AText).Casts;
end;

function ParseCastLib(const APath: string): TCastLib;
begin
  Result := Default(TCastLib);
  if (APath = '') or not TFile.Exists(APath) then Exit;
  Result := ParseCastLibText(TFile.ReadAllText(APath));
end;

function LoadCastLib(const APath: string): TArray<TCastDef>;
begin
  Result := ParseCastLib(APath).Casts;
end;

function ClassCastFor(const ADefs: TArray<TCastDef>; const AFrom, ATo: string): string;
var
  d: TCastDef;
begin
  Result := '';
  for d in ADefs do
    if Has(d.Accepts, AFrom) and Has(d.Yields, ATo) then Exit(d.Name);
end;

function FindEnumCast(const ALib: TCastLib; const AName: string;
  out ADef: TEnumDef): Boolean;
var e: TEnumDef;
begin
  ADef := Default(TEnumDef);
  if AName = '' then Exit(False);
  for e in ALib.Enums do
    if SameText(e.Name, AName) then
    begin
      ADef := e;
      Exit(True);
    end;
  Result := False;
end;

function EnumCastValue(const ADef: TEnumDef; const AValue: string;
  out AResult: string): Boolean;
var
  p : TEnumPair;
  V : string;
begin
  AResult := '';
  V := Trim(AValue);
  for p in ADef.Pairs do
    if SameText(p.FromMember, V) then
    begin
      AResult := p.ToMember;
      Exit(True);
    end;
  { No pair matched. An `else` is the author saying "anything else becomes
    this"; without one there is nothing honest to emit. }
  if ADef.Fallback <> '' then
  begin
    AResult := ADef.Fallback;
    Exit(True);
  end;
  Result := False;
end;

end.
