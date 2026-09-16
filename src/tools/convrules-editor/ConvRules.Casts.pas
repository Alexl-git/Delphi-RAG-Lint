unit ConvRules.Casts;

{ Pure cast classifier for the conversion editor.

  Given the Delphi TYPE NAMES of a source (From) property leaf and a target (To)
  property leaf, returns the set of valid built-in cast functions that bridge
  them -- or an empty set when the pair is same-type (identity, no cast needed)
  or genuinely incompatible (the UI blocks the link).

  This is the tool-side companion to the engine's #link ": CastFn" support: the
  editor only ever offers casts this classifier deems valid, and emits the chosen
  one as the DSL suffix. Kept pure + headless so it is directly unit-tested. }

interface

uses
  System.SysUtils
  ;

type
  /// <summary>A built-in cast the DSL understands (mirrors the engine catalog).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: ConvRules.Casts.CastFnFromName (ConvRules.Casts.pas), ConvRules.MainForm.TConvRulesForm.AssignLink (ConvRules.MainForm.pas), declaration (ConvRules.Casts.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TCastFn = (
    cfNone, // identity -- same type, no suffix emitted
    cfIntToStr, // Integer  -> string
    cfFloatToStr, // Double   -> string
    cfStrToInt, // string   -> Integer
    cfStrToIntDef, // string   -> Integer (with default)
    cfStrToFloat, // string   -> Double
    cfStrToFloatDef, // string   -> Double  (with default)
    cfIntToFloat, // Integer  -> Double  (widening)
    cfTrunc, // Double   -> Integer (toward zero)
    cfRound, // Double   -> Integer (nearest)
    cfBoolToStr // Boolean  -> string
  );
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: ConvRules.MainForm.TConvRulesForm.AssignLink (ConvRules.MainForm.pas), declaration (ConvRules.Casts.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TCastFnSet = set of TCastFn;

  /// <summary>The DSL token for a cast (what gets emitted after ': '). Empty for
  /// cfNone.</summary>
  /// <param name="ACast"><!-- drag-lint:auto type -->TCastFn</param>
  /// <returns><!-- drag-lint:auto -->string -- Observed: 'IntToStr'; 'FloatToStr';
  /// 'StrToInt'; 'StrToIntDef'; 'StrToFloat'; 'StrToFloatDef'.</returns>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Called from: ConvRules.Casts.CastFnFromName (ConvRules.Casts.pas), ConvRules.MainForm.TConvRulesForm.AssignLink (ConvRules.MainForm.pas)</para>
  /// <para>Complexity: 11 (cyclomatic, outer body), 16 lines (full implementation)</para>
  /// <para>Pure</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
function CastFnName(ACast: TCastFn): string;

/// <summary>Parse a DSL cast token (case-insensitive) back to its enum; cfNone
/// for '' or an unknown token.</summary>
/// <param name="AName"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->TCastFn -- Observed: C; cfNone.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Calls: ConvRules.Casts.CastFnName, SameText</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.Casts.CastFnName"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CastFnFromName(const AName: string): TCastFn;

/// <summary>Broad type family of a Delphi type name, so leaf types that differ
/// only by width (Integer/Int64, Double/Single/Extended) classify together.</summary>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Used by: ConvRules.Casts.SameFamily (ConvRules.Casts.pas), ConvRules.Casts.ValidCasts (ConvRules.Casts.pas), declaration (ConvRules.Casts.pas)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
type
  TTypeFamily = (tfUnknown, tfInteger, tfFloat, tfString, tfBoolean);

  /// <param name="ATypeName"><!-- drag-lint:auto type -->const string</param>
  /// <returns><!-- drag-lint:auto -->TTypeFamily -- Observed: tfInteger; tfFloat; tfString;
  /// tfBoolean; tfUnknown.</returns>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Called from: ConvRules.Casts.SameFamily (ConvRules.Casts.pas), ConvRules.Casts.ValidCasts (ConvRules.Casts.pas)</para>
  /// <para>Calls: LowerCase, Trim</para>
  /// <para>Complexity: 31 (cyclomatic, outer body), 21 lines (full implementation)</para>
  /// <para>Pure</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
function TypeFamilyOf(const ATypeName: string): TTypeFamily;

/// <summary>The valid casts from a source leaf type to a target leaf type.
/// Same-family -> [] (identity, no cast). Incompatible -> [] as well; callers
/// distinguish the two via SameFamily/IsCastable below.</summary>
/// <param name="AFromType"><!-- drag-lint:auto type -->const string</param>
/// <param name="AToType"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->TCastFnSet -- Observed: []; [cfIntToStr];
/// [cfIntToFloat]; [cfFloatToStr]; [cfTrunc, cfRound]; [cfStrToInt, cfStrToIntDef].</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.Casts.IsCastable (ConvRules.Casts.pas), ConvRules.MainForm.TConvRulesForm.AssignLink (ConvRules.MainForm.pas)</para>
/// <para>Calls: ConvRules.Casts.TypeFamilyOf</para>
/// <para>Complexity: 15 (cyclomatic, outer body), 29 lines (full implementation)</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.Casts.TypeFamilyOf"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ValidCasts(const AFromType, AToType: string): TCastFnSet;

/// <summary>True when both types are the same family (an identity link, no cast).</summary>
/// <param name="AFromType"><!-- drag-lint:auto type -->const string</param>
/// <param name="AToType"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->Boolean -- Observed: (F &lt;&gt; tfUnknown) and (F =
/// T).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.Casts.IsCastable (ConvRules.Casts.pas), ConvRules.MainForm.TConvRulesForm.AssignLink (ConvRules.MainForm.pas)</para>
/// <para>Calls: ConvRules.Casts.TypeFamilyOf</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.Casts.TypeFamilyOf"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SameFamily(const AFromType, AToType: string): Boolean;

/// <summary>True when a link between these leaf types is expressible -- either
/// identity (same family) or via at least one valid cast. False means the UI
/// should BLOCK the link (e.g. enum -> class, or two unrelated class types).</summary>
/// <param name="AFromType"><!-- drag-lint:auto type -->const string</param>
/// <param name="AToType"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->Boolean -- Observed: SameFamily(AFromType, AToType) or
/// (ValidCasts(AFromType, AToType) &lt;&gt; []).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.MainForm.TConvRulesForm.CanCast (ConvRules.MainForm.pas)</para>
/// <para>Calls: ConvRules.Casts.SameFamily, ConvRules.Casts.ValidCasts, SameText, Trim</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.Casts.SameFamily"/>
/// <seealso cref="ConvRules.Casts.ValidCasts"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsCastable(const AFromType, AToType: string): Boolean;

/// <summary>True when a proptree leaf type is not usable for cast reasoning --
/// proptree emits 'unknown' (and occasionally '') when a property is inherited
/// from a parent class the index could not resolve (e.g. TcxButton.Align: the cx
/// ancestry breaks at the unresolved TcxBaseButton, so every VCL-inherited
/// property loses its type).</summary>
/// <param name="AType"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->Boolean -- Observed: (Trim(AType) = '') or
/// SameText(Trim(AType), 'unknown').</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.Casts.ResolveUnknownTypes (ConvRules.Casts.pas)</para>
/// <para>Calls: SameText, Trim</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsUnknownType(const AType: string): Boolean;

/// <summary>Cast-reasoning inference for a same-named From&lt;-&gt;To property pair.
/// When exactly ONE side's type is unknown (inherited from an unresolved parent),
/// adopt the other side's known type for both -- a property with the same name on
/// both classes is the same inherited member (Align is TAlign on both), so the
/// link is an identity. When both are unknown, leaves them as-is.</summary>
/// <param name="AFromType"><!-- drag-lint:auto type -->var string</param>
/// <param name="AToType"><!-- drag-lint:auto type -->var string</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.MainForm.TConvRulesForm.DoAssign (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoAutoMatch (ConvRules.MainForm.pas)</para>
/// <para>Calls: ConvRules.Casts.IsUnknownType</para>
/// <para>Mutates: AFromType (var), AToType (var)</para>
/// <seealso cref="ConvRules.Casts.IsUnknownType"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure ResolveUnknownTypes(var AFromType, AToType: string);

implementation

function CastFnName(ACast: TCastFn): string;
begin
  case ACast of
    cfIntToStr     : Result:= 'IntToStr';
    cfFloatToStr   : Result:= 'FloatToStr';
    cfStrToInt     : Result:= 'StrToInt';
    cfStrToIntDef  : Result:= 'StrToIntDef';
    cfStrToFloat   : Result:= 'StrToFloat';
    cfStrToFloatDef: Result:= 'StrToFloatDef';
    cfIntToFloat   : Result:= 'IntToFloat';
    cfTrunc        : Result:= 'Trunc';
    cfRound        : Result:= 'Round';
    cfBoolToStr    : Result:= 'BoolToStr';
    else
      Result:= ''; // cfNone
  end; // case
end; // function

function CastFnFromName(const AName: string): TCastFn;
var
  C: TCastFn;
begin
  for C:= Low(TCastFn) to High(TCastFn) do
    if (C <> cfNone) and SameText(CastFnName(C), AName) then
      Exit(C);
  Result:= cfNone;
end;

function TypeFamilyOf(const ATypeName: string): TTypeFamily;
var
  T: string;
begin
  T:= LowerCase(Trim(ATypeName));
  // strip a leading 'T' alias wrapper is NOT done -- we match on known RTL names.
  if (T = 'integer') or (T = 'int64') or (T = 'cardinal') or (T = 'longint')
     or (T = 'smallint') or (T = 'shortint') or (T = 'byte') or (T = 'word')
     or (T = 'longword') or (T = 'nativeint') or (T = 'uint64') then
    Exit(tfInteger);
  if (T = 'double') or (T = 'single') or (T = 'extended') or (T = 'real')
     or (T = 'currency') or (T = 'comp') then
    Exit(tfFloat);
  if (T = 'string') or (T = 'unicodestring') or (T = 'ansistring')
     or (T = 'widestring') or (T = 'char') or (T = 'ansichar')
     or (T = 'widechar') or (T = 'shortstring') then
    Exit(tfString);
  if (T = 'boolean') or (T = 'bool') or (T = 'bytebool') or (T = 'wordbool')
     or (T = 'longbool') then
    Exit(tfBoolean);
  Result:= tfUnknown;
end; // function

function SameFamily(const AFromType, AToType: string): Boolean;
var
  F: TTypeFamily;
  T: TTypeFamily;
begin
  F:= TypeFamilyOf(AFromType);
  T:= TypeFamilyOf(AToType  );
  Result:= (F <> tfUnknown) and (F = T);
end;

function ValidCasts(const AFromType, AToType: string): TCastFnSet;
var
  F: TTypeFamily;
  T: TTypeFamily;
begin
  Result:= [];
  F:= TypeFamilyOf(AFromType);
  T:= TypeFamilyOf(AToType  );
  if (F = tfUnknown) or (T = tfUnknown) then Exit; // can't reason -> block
  if F = T then Exit; // identity -> no cast

  case F of
    tfInteger:
    case T of
      tfString: Result:= [cfIntToStr  ];
      tfFloat : Result:= [cfIntToFloat];
    end;
    tfFloat:
    case T of
      tfString : Result:= [cfFloatToStr]    ;
      tfInteger: Result:= [cfTrunc, cfRound];
    end;
    tfString:
    case T of
      tfInteger: Result:= [cfStrToInt  , cfStrToIntDef  ];
      tfFloat  : Result:= [cfStrToFloat, cfStrToFloatDef];
    end;
    tfBoolean:
      if T = tfString then
        Result:= [cfBoolToStr];
  end; // case
end; // function

function IsCastable(const AFromType, AToType: string): Boolean;
begin
  // Identical type names are ALWAYS an identity link (no cast) -- this covers
  // every class/enum/record/interface pair the family classifier treats as
  // tfUnknown (TFont<-TFont, TColor<-TColor, ...). Only genuinely DIFFERENT
  // types that have no known cast are blocked.
  if SameText(Trim(AFromType), Trim(AToType)) then
    Exit(True);
  Result:= SameFamily(AFromType, AToType) or (ValidCasts(AFromType, AToType) <> []);
end;

function IsUnknownType(const AType: string): Boolean;
begin
  Result:= (Trim(AType) = '') or SameText(Trim(AType), 'unknown');
end;

procedure ResolveUnknownTypes(var AFromType, AToType: string);
begin
  if IsUnknownType(AFromType) and not IsUnknownType(AToType) then
    AFromType:= AToType
  else if IsUnknownType(AToType) and not IsUnknownType(AFromType) then
    AToType:= AFromType;
end;

end.
