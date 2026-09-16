unit ConvRules.ConvCatalog;

{ THE CONVERSION CATALOG -- one answer to "what can this property become?".

  Conversions live in two disconnected places in this editor, and neither can
  answer that question on its own:

    * SCALAR casts are hard-coded in ConvRules.Casts (TCastFn / ValidCasts).
      They answer "is From->To allowed", never "what are the To's".
    * CLASS and ENUM casts live in the .castlib, parsed by the ENGINE's
      DRagLint.Convert.CastLib into TCastDef / TEnumDef. ClassCastFor likewise
      takes both ends and answers yes/no.

  Every existing caller asks the PAIR question because it already knows both
  types. The user picking a From property does not: they want the list. This
  unit is that list, and it is the only place the two sources are merged.

  PURE: no UI, no file I/O, no engine calls. The caller passes the castlib defs
  it already loaded (MainForm.FCastDefs), so this unit never decides where the
  library comes from.

  DELIBERATELY REPORTS ONLY WHAT IS REAL. If Boolean->Integer is not a cast the
  editor can perform, it is not listed -- an aspirational entry would be a
  target the user can pick and the engine cannot honour. Adding such a
  conversion is an edit to the .castlib (or to ValidCasts), not to this unit. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  DRagLint.Convert.CastLib;

type
  /// <summary>How a conversion is realised -- which of the three sources
  /// supplies it. Drives the badge shown beside the target type.</summary>
  /// <remarks>
  /// <para>ckIdentity -- same type; a #link with no cast suffix.</para>
  /// <para>ckScalar   -- ConvRules.Casts TCastFn (IntToStr, Trunc, ...).</para>
  /// <para>ckClass    -- a .castlib 'cast' block (AssignGraphic, ...).</para>
  /// <para>ckEnum     -- a .castlib 'enum' block (ButtonLayout, ...).</para>
  /// <para>The members carry no trailing comments on purpose: the linter's
  /// inline-comment-in-multiline-args rule fires on any '//' inside a
  /// parenthesised list, because a reformatter may reflow the next element up
  /// into it -- and this folder is now YADF-formatted.</para>
  /// </remarks>
  TConvKind = (ckIdentity, ckScalar, ckClass, ckEnum);

  /// <summary>One thing the selected property could be converted INTO.</summary>
  /// <remarks>ToType is what the user picks; CastName is the suffix that would
  /// be written after ':' on the #link ('' for identity and for scalar casts,
  /// which carry their own function name in Detail instead).</remarks>
  /// <remarks>ToType is the target type name as the pool shows it. CastName is
  /// the .castlib block name, '' when the conversion is not a library cast.
  /// Detail is a human hint -- the pas template for a class cast, the cast
  /// function for a scalar one.</remarks>
  TConvOption = record
    ToType  : string;
    CastName: string;
    Kind    : TConvKind;
    Detail  : string;
  end;

/// <summary>Every conversion available FROM AFromType, merged from all three
/// sources, in a stable order: identity first, then scalar, class, enum.</summary>
/// <param name="AFromType">The selected property's type. '' or 'unknown'
/// yields [] -- an unresolved type cannot be reasoned about.</param>
/// <param name="ACastDefs">The loaded .castlib 'cast' blocks (may be []).</param>
/// <param name="AEnumDefs">The loaded .castlib 'enum' blocks (may be []).</param>
/// <returns>Possibly empty. Never nil-dereferences on empty libraries.</returns>
function ConversionsFor(const AFromType: string;
  const ACastDefs: TArray<TCastDef>;
  const AEnumDefs: TArray<TEnumDef>): TArray<TConvOption>;

/// <summary>The badge text for a kind -- 'same', 'scalar', 'class', 'enum'.</summary>
/// <param name="AKind">The kind to label.</param>
/// <returns>A short lower-case word for the UI badge; never ''.</returns>
function ConvKindLabel(AKind: TConvKind): string;

/// <summary>Render one option the way the UI list shows it, e.g.
/// 'TdxSmartGlyph  [class: AssignGraphic]'.</summary>
/// <param name="AOption">The option to render.</param>
/// <returns>Type name plus a bracketed badge; the cast name is included only
/// when the conversion carries one.</returns>
function ConvOptionText(const AOption: TConvOption): string;

implementation

uses
  ConvRules.Casts;

function ConvKindLabel(AKind: TConvKind): string;
begin
  case AKind of
    ckIdentity: Result := 'same';
    ckScalar  : Result := 'scalar';
    ckClass   : Result := 'class';
  else
    Result := 'enum';
  end;
end;

function ConvOptionText(const AOption: TConvOption): string;
begin
  if AOption.CastName <> '' then
    Result := Format('%s  [%s: %s]',
      [AOption.ToType, ConvKindLabel(AOption.Kind), AOption.CastName])
  else
    Result := Format('%s  [%s]', [AOption.ToType, ConvKindLabel(AOption.Kind)]);
end;

{ The representative target type for each scalar family.

  ValidCasts answers From->To for a PAIR, so enumerating targets means probing
  it with one concrete name per family. These four names are what the pool and
  the .rules DSL actually use, so the strings the catalog offers are the strings
  a #link will carry -- no translation step, and nothing to keep in sync. }
const
  SCALAR_TARGETS: array[0..3] of string = ('Integer', 'Double', 'string', 'Boolean');

{ The cast-function names bridging AFrom -> ATo, comma-separated, '' when there
  is no scalar cast between them.

  Extracted from ConversionsFor for two reasons the linter named: the accumulator
  was an O(n^2) `S := S + X` in a loop, and inlining this pushed ConversionsFor to
  six levels of nesting. Joining a TStringList fixes both at once. }
function ScalarCastNames(const AFrom, ATo: string): string;
var
  Fns  : TCastFnSet;
  Names: TStringList;
  Fn   : TCastFn;
begin
  Fns := ValidCasts(AFrom, ATo);
  if Fns = [] then
    Exit('');
  Names := TStringList.Create;
  try
    for Fn := Low(TCastFn) to High(TCastFn) do
      if Fn in Fns then
        Names.Add(CastFnName(Fn));
    Result := string.Join(', ', Names.ToStringArray);
  finally
    Names.Free;
  end;
end;

function ConversionsFor(const AFromType: string;
  const ACastDefs: TArray<TCastDef>;
  const AEnumDefs: TArray<TEnumDef>): TArray<TConvOption>;
var
  Res  : TList<TConvOption>;
  Seen : TStringList;
  From : string;
  Opt  : TConvOption;
  d    : TCastDef;
  e    : TEnumDef;
  Y    : string;
  T    : string;
  A    : string;

  { One entry per target type. A later source never displaces an earlier one:
    the ordering below (identity, scalar, class, enum) IS the precedence, and
    an identity link must never be relabelled as a cast. }
  procedure AddOnce(const AToType, ACastName: string; AKind: TConvKind;
    const ADetail: string);
  begin
    if Trim(AToType) = '' then
      Exit;
    if Seen.IndexOf(LowerCase(AToType)) >= 0 then
      Exit;
    Seen.Add(LowerCase(AToType));
    Opt.ToType   := AToType;
    Opt.CastName := ACastName;
    Opt.Kind     := AKind;
    Opt.Detail   := ADetail;
    Res.Add(Opt);
  end;

begin
  Result := [];
  From := Trim(AFromType);
  // An unresolved type is not a type. Offering anything here would invite the
  // user to pick a target nothing can honour -- IsUnknownType is the same test
  // DoAssign already trusts.
  if IsUnknownType(From) then
    Exit;

  Res  := TList<TConvOption>.Create;
  Seen := TStringList.Create;
  try
    Seen.CaseSensitive := False;

    // 1. Identity. Always legal, always first: TFont <- TFont needs no cast.
    AddOnce(From, '', ckIdentity, 'same type -- no cast');

    // 2. Scalar casts, discovered by probing the real classifier rather than by
    //    a second table that could drift away from it.
    for T in SCALAR_TARGETS do
      if not SameText(T, From) then
      begin
        var Detail: string := ScalarCastNames(From, T);
        if Detail <> '' then
          AddOnce(T, '', ckScalar, Detail);
      end;

    // 3. Class casts from the .castlib: every block that ACCEPTS this type
    //    offers each of its yields.
    for d in ACastDefs do
    begin
      var Accepted: Boolean := False;
      for A in d.Accepts do
        if SameText(A, From) then
        begin
          Accepted := True;
          Break;
        end;
      if not Accepted then
        Continue;
      for Y in d.Yields do
        AddOnce(Y, d.Name, ckClass, d.PasTemplate);
    end;

    // 4. Enum casts, matched on the block's declared from-type.
    for e in AEnumDefs do
      if SameText(e.FromType, From) then
        AddOnce(e.ToType, e.Name, ckEnum,
          Format('%d member pair(s)', [Length(e.Pairs)]));

    Result := Res.ToArray;
  finally
    Seen.Free;
    Res.Free;
  end;
end;

end.
