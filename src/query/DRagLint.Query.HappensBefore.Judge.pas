{ drag-lint 1.56 -- lane LINTFIX-A: the presets of the `happens-before` verb, split out of
DRagLint.Query.HappensBefore.Verb (unit-too-large). A preset expands one name into the two event specs of a
question; nothing here reads the index. }

unit DRagLint.Query.HappensBefore.Judge;

interface

/// <summary>Expands a preset name into its events.</summary>
/// <param name="pPreset">Preset name, case-insensitive.</param>
/// <param name="pA">Out: event A of the preset; '' when the preset takes the caller's --a.</param>
/// <param name="pB">Out: event B of the preset.</param>
/// <returns>False for a name that is not a built preset (pA and pB are then ''), and for the three
/// presets that take a variable (<see cref="HbvPresetTarget"/>).</returns>
/// <remarks>Built: `randomize` (A = extcall:Randomize, B = extcall:Random); `format-settings`
/// (A = extwrite:FormatSettings, B = extcall: of the RTL routines that format or parse with the
/// global settings); `before-app-run` (A = the caller's --a, B = app-run:*).</remarks>
function HbvPresetEvents(const pPreset: string; out pA, pB: string): Boolean;

/// <summary>Rewrites the --a / --b values of the presets that take a VARIABLE: `use-after-free`
/// (A = free:X, B = use:X), `finalization` (A = final-free:X, B = use:X) and `lock-held-when`
/// (A = held:L, B = the caller's event).</summary>
/// <param name="pPreset">Preset name, case-insensitive.</param>
/// <param name="pA">In: the variable's QName as given with --a. Out: event A.</param>
/// <param name="pB">In: the --b value ('' when absent). Out: event B.</param>
/// <param name="pError">Out: '' or the usage error (missing --a, an event in place of the variable,
/// a --b the preset does not take, lock-held-when without --b); pA and pB are then unchanged.</param>
/// <returns>True when pPreset is one of the three presets (also when pError is set).</returns>
function HbvPresetTarget(const pPreset: string; var pA, pB: string; out pError: string): Boolean;

/// <summary>The names of the built presets, in help order.</summary>
/// <returns>A new array; never empty.</returns>
function HbvPresetNames: TArray<string>;

implementation

uses
  System.SysUtils
, System.StrUtils
, DRagLint.Query.HappensBefore.Verb
  ;

const
  PRESET_FINALIZATION = 'finalization';
  PRESET_LOCK_HELD_WHEN = 'lock-held-when';
  PRESET_RANDOMIZE = 'randomize';
  PRESET_FORMAT_SETTINGS = 'format-settings';
  PRESET_BEFORE_APP_RUN = 'before-app-run';
  { the RTL routines that format or parse with the global FormatSettings when no settings argument is given }
  FORMAT_SETTINGS_USERS = 'Format,FormatFloat,FormatCurr,FormatDateTime,FloatToStr,FloatToStrF,CurrToStr,CurrToStrF,' +
    'StrToFloat,StrToFloatDef,TryStrToFloat,StrToCurr,StrToCurrDef,TryStrToCurr,DateToStr,TimeToStr,DateTimeToStr,' +
    'StrToDate,StrToDateDef,TryStrToDate,StrToTime,StrToTimeDef,TryStrToTime,StrToDateTime,StrToDateTimeDef,TryStrToDateTime';
  PRESET_NAMES: array[0..5] of string = (PRESET_RANDOMIZE, PRESET_FORMAT_SETTINGS, PRESET_BEFORE_APP_RUN,
    PRESET_USE_AFTER_FREE, PRESET_FINALIZATION, PRESET_LOCK_HELD_WHEN);
  TARGET_PRESETS: array[0..2] of string = (PRESET_USE_AFTER_FREE, PRESET_FINALIZATION, PRESET_LOCK_HELD_WHEN);
  TARGET_PRESET_KINDS: array[0..2] of THbvEventKind = (hekFree, hekFinalFree, hekHeld);

function HbvPresetNames: TArray<string>;
begin
  Result:= nil;
  for var N in PRESET_NAMES do Result:= Result + [N];
end;

function HbvPresetEvents(const pPreset: string; out pA, pB: string): Boolean;
begin
  pA:= '';
  pB:= '';
  Result:= True;
  if SameText(pPreset, PRESET_RANDOMIZE) then
  begin
    pA:= KIND_CODES[hekExtCall] + EVENT_SEP + 'Randomize';
    pB:= KIND_CODES[hekExtCall] + EVENT_SEP + 'Random';
  end
  else if SameText(pPreset, PRESET_FORMAT_SETTINGS) then
  begin
    pA:= KIND_CODES[hekExtWrite] + EVENT_SEP + 'FormatSettings';
    pB:= KIND_CODES[hekExtCall] + EVENT_SEP + FORMAT_SETTINGS_USERS;
  end
  else if SameText(pPreset, PRESET_BEFORE_APP_RUN) then
    pB:= KIND_CODES[hekAppRun] + EVENT_SEP + APP_RUN_ALL
  else
    Result:= False;
end;

function HbvPresetTarget(const pPreset: string; var pA, pB: string; out pError: string): Boolean;
const
  LOCK_PRESET = 2;
begin
  pError:= '';
  var Ix:= IndexText(pPreset, TARGET_PRESETS);  // dl:ok index-possibly-out-of-range@fe83 -- REVIEWED LINTFIX-A: Ix comes from IndexText over TARGET_PRESETS and is checked >= 0 on the line above, so TARGET_PRESETS[Ix] and TARGET_PRESET_KINDS[Ix] (same bounds) are inside the arrays
  Result:= Ix >= 0;
  if not Result then Exit;
  var IsLock:= Ix = LOCK_PRESET;
  if pA = '' then
    pError:= Format('--preset %s needs --a <QName>: %s', [TARGET_PRESETS[Ix],
      if IsLock then 'the lock (a unit variable, class var or field)' else 'the variable (a unit variable, class var or field) whose free is event A'])
  else if pA.Contains(EVENT_SEP) then
    pError:= Format('--preset %s takes the variable itself in --a (a QName such as uCache.GCache), not an event', [TARGET_PRESETS[Ix]])
  else if IsLock and (pB = '') then
    pError:= Format('--preset %s needs --b <event>: the access that must run with the lock held', [TARGET_PRESETS[Ix]])
  else if not IsLock and (pB <> '') then
    pError:= Format('--preset %s names event B (%s%s<variable>): give --a <QName> only', [TARGET_PRESETS[Ix], KIND_CODES[hekUse], EVENT_SEP])
  else
  begin
    if not IsLock then pB:= KIND_CODES[hekUse] + EVENT_SEP + pA;
    pA:= KIND_CODES[TARGET_PRESET_KINDS[Ix]] + EVENT_SEP + pA;
  end;
end;

end.
