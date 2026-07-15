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
  System.SysUtils;

type
  /// <summary>A built-in cast the DSL understands (mirrors the engine catalog).</summary>
  TCastFn = (
    cfNone,          // identity -- same type, no suffix emitted
    cfIntToStr,      // Integer  -> string
    cfFloatToStr,    // Double   -> string
    cfStrToInt,      // string   -> Integer
    cfStrToIntDef,   // string   -> Integer (with default)
    cfStrToFloat,    // string   -> Double
    cfStrToFloatDef, // string   -> Double  (with default)
    cfIntToFloat,    // Integer  -> Double  (widening)
    cfTrunc,         // Double   -> Integer (toward zero)
    cfRound,         // Double   -> Integer (nearest)
    cfBoolToStr      // Boolean  -> string
  );
  TCastFnSet = set of TCastFn;

/// <summary>The DSL token for a cast (what gets emitted after ': '). Empty for
/// cfNone.</summary>
function CastFnName(ACast: TCastFn): string;

/// <summary>Parse a DSL cast token (case-insensitive) back to its enum; cfNone
/// for '' or an unknown token.</summary>
function CastFnFromName(const AName: string): TCastFn;

/// <summary>Broad type family of a Delphi type name, so leaf types that differ
/// only by width (Integer/Int64, Double/Single/Extended) classify together.</summary>
type
  TTypeFamily = (tfUnknown, tfInteger, tfFloat, tfString, tfBoolean);

function TypeFamilyOf(const ATypeName: string): TTypeFamily;

/// <summary>The valid casts from a source leaf type to a target leaf type.
/// Same-family -> [] (identity, no cast). Incompatible -> [] as well; callers
/// distinguish the two via SameFamily/IsCastable below.</summary>
function ValidCasts(const AFromType, AToType: string): TCastFnSet;

/// <summary>True when both types are the same family (an identity link, no cast).</summary>
function SameFamily(const AFromType, AToType: string): Boolean;

/// <summary>True when a link between these leaf types is expressible -- either
/// identity (same family) or via at least one valid cast. False means the UI
/// should BLOCK the link (e.g. enum -> class, or two unrelated class types).</summary>
function IsCastable(const AFromType, AToType: string): Boolean;

implementation

function CastFnName(ACast: TCastFn): string;
begin
  case ACast of
    cfIntToStr     : Result := 'IntToStr';
    cfFloatToStr   : Result := 'FloatToStr';
    cfStrToInt     : Result := 'StrToInt';
    cfStrToIntDef  : Result := 'StrToIntDef';
    cfStrToFloat   : Result := 'StrToFloat';
    cfStrToFloatDef: Result := 'StrToFloatDef';
    cfIntToFloat   : Result := 'IntToFloat';
    cfTrunc        : Result := 'Trunc';
    cfRound        : Result := 'Round';
    cfBoolToStr    : Result := 'BoolToStr';
  else
    Result := ''; // cfNone
  end;
end;

function CastFnFromName(const AName: string): TCastFn;
var
  C: TCastFn;
begin
  for C := Low(TCastFn) to High(TCastFn) do
    if (C <> cfNone) and SameText(CastFnName(C), AName) then
      Exit(C);
  Result := cfNone;
end;

function TypeFamilyOf(const ATypeName: string): TTypeFamily;
var
  T: string;
begin
  T := LowerCase(Trim(ATypeName));
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
  Result := tfUnknown;
end;

function SameFamily(const AFromType, AToType: string): Boolean;
var
  F, T: TTypeFamily;
begin
  F := TypeFamilyOf(AFromType);
  T := TypeFamilyOf(AToType);
  Result := (F <> tfUnknown) and (F = T);
end;

function ValidCasts(const AFromType, AToType: string): TCastFnSet;
var
  F, T: TTypeFamily;
begin
  Result := [];
  F := TypeFamilyOf(AFromType);
  T := TypeFamilyOf(AToType);
  if (F = tfUnknown) or (T = tfUnknown) then Exit; // can't reason -> block
  if F = T then Exit;                              // identity -> no cast

  case F of
    tfInteger:
      case T of
        tfString: Result := [cfIntToStr];
        tfFloat : Result := [cfIntToFloat];
      end;
    tfFloat:
      case T of
        tfString : Result := [cfFloatToStr];
        tfInteger: Result := [cfTrunc, cfRound];
      end;
    tfString:
      case T of
        tfInteger: Result := [cfStrToInt, cfStrToIntDef];
        tfFloat  : Result := [cfStrToFloat, cfStrToFloatDef];
      end;
    tfBoolean:
      if T = tfString then Result := [cfBoolToStr];
  end;
end;

function IsCastable(const AFromType, AToType: string): Boolean;
begin
  Result := SameFamily(AFromType, AToType) or (ValidCasts(AFromType, AToType) <> []);
end;

end.
