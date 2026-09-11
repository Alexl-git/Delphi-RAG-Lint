unit DragLint.Plugin.SurfaceSplit;

{ Which half of an unsaved buffer did the user just edit -- the INTERFACE, which
  dependents can see, or the IMPLEMENTATION, which they cannot?

  WHY THIS EXISTS. LiveDiagnostics hashes the WHOLE buffer, so an implementation
  keystroke and an interface keystroke look identical. The fan-out (PLAN-lint-
  tree P3) must fire on the second and stay silent on the first: a background
  feature that runs while you type inside a method body is a feature that gets
  switched off.

  WHY NOT THE ENGINE'S OWN FINGERPRINT, which the plan asked for. It cannot be
  reached from here. `SurfaceFingerprint` takes ARRAYS OF EXTRACTED SYMBOLS
  (TSymbol/TUnitUse from Core.Model), which means a parse; the design-time BPL
  links no parser at all -- `dclDragLintWizard.dpk` contains only plugin units
  plus Core.JobObject / Core.GhostText / Core.EngineHold / Workspace.Config, and
  pulling src\parser into a design-time package is not a thing anyone should do
  to make a debounce cheaper. So the fingerprint stays where it is, and this is
  the LOCAL gate in front of it: the engine still has the last word, and still
  answers `changed:false` when a launch turns out to be unnecessary.

  THE ONE RULE THAT MAKES THAT SAFE. This gate may over-fire; it must never
  under-fire. A false launch costs one BELOW_NORMAL engine run that the engine
  short-circuits. A missed launch means an interface edit that silently reaches
  no dependent -- which is the entire failure this feature exists to prevent.
  Every judgement call below is resolved in that direction, and the split point
  is chosen as LATE as possible for exactly that reason (see FindSplit).

  WHY A CHARACTER SCANNER AND NOT A LINE REGEX. The plan proposed splitting at
  the first line matching `^\s*implementation\b`. That word appears in comments
  constantly -- most obviously in the sentence you are reading. It also appears
  in string literals and inside $IFDEF-disabled branches. A false early
  split puts real interface text into the implementation half, and interface
  edits there stop firing: a silent miss, in the one direction that is not
  allowed. So the scan carries comment and string state ACROSS LINES, the way
  the compiler does. Brace and paren-star comments do not nest in Object Pascal,
  and an $IFDEF directive is itself a brace comment to this scanner -- both are the
  compiler's real behaviour, not a simplification. }

interface

uses
  System.SysUtils;

type
  /// <summary>The launch decision for the interface-change fan-out: it holds
  /// the hashes, the idle clock, the generation counter and the two
  /// short-circuits, so the only thing left in the IDE-bound runner is reading
  /// the buffer and calling the hook.</summary>
  /// <remarks>NOT thread-safe, and deliberately so -- it is driven from the
  /// runner's timer on the main thread. NoteFingerprint arrives from a worker,
  /// so its caller must marshal (TThread.Queue).</remarks>
  TFanOutGate = record
  private
    FFile           : string  ;
    FBufHash        : Cardinal;  { whole buffer -- skips the split on a no-op poll }
    FBufSeen        : Boolean ;
    FIfaceHash      : string  ;
    FHashAtLaunch   : string  ;
    FSilentShape    : string  ;
    FLastFingerprint: string  ;
    FLastChangeTick : UInt64  ;
    FGeneration     : Integer ;
    FLastWhy        : string  ;
    FHashBeforeLaunch: string ;
  public
    /// <summary>Take back the launch the last Consider authorised, because the
    /// caller could not start it.</summary>
    /// <remarks>Consider COMMITS when it answers True -- it advances the
    /// launched-shape marker so the same edit cannot fire twice. If the caller
    /// then declines (the worker is still unwinding), that commit makes the
    /// edit VANISH: the gate reports "interface unchanged since the last
    /// launch" forever after, and the change is never fanned out. Measured
    /// 2026-09-11: two consecutive edits lost exactly this way while a 6m22s
    /// tier-3 compile held the worker.
    ///
    /// The generation is deliberately NOT rewound. It is the staleness token;
    /// reusing a number that was already handed out would make a late result
    /// from the abandoned run look current.</remarks>
    procedure UndoLaunch;

    /// <summary>Why the last Consider answered as it did -- DIAGNOSIS ONLY.</summary>
    /// <remarks>Consider has five distinct refusals that all returned a bare
    /// False, so a fan-out that never launched could not be told apart from one
    /// that was never asked. Nothing reads this to decide anything; the runner
    /// logs it when it CHANGES, which is what makes a silent gate visible
    /// without flooding a 250 ms timer's log.</remarks>
    property LastWhy: string read FLastWhy;

    /// <summary>Forgets every hash and clock, keeping the generation counter so
    /// a late result from a previous file can still be recognised as stale.</summary>
    procedure Reset;

    /// <summary>Feeds the current buffer and answers whether a fan-out should
    /// launch right now.</summary>
    /// <param name="AFile">Path of the buffer. A different path re-baselines
    /// and never launches -- switching tabs is not an edit.</param>
    /// <param name="ABufText">The full unsaved buffer text.</param>
    /// <param name="ANowTick">GetTickCount64, passed in so the gate is testable
    /// without waiting in real time.</param>
    /// <param name="AIdleMs">How long the interface half must hold still.</param>
    /// <param name="AGeneration">Receives the generation of the launch this
    /// call authorises, or 0 when the answer is False -- always assigned, so a
    /// caller cannot pass a stale generation on to the worker by accident.</param>
    /// <returns>True exactly once per settled interface change.</returns>
    function Consider(const AFile, ABufText: string; ANowTick, AIdleMs: UInt64;
                      out AGeneration: Integer): Boolean;

    /// <summary>Records the surface fingerprint the engine reported for the
    /// last launch.</summary>
    /// <param name="AFingerprint">The engine's fingerprint, or '' to forget.</param>
    /// <remarks>When it equals the previous run's, the shape just launched is
    /// marked as yielding no new work, so editing BACK to it (an undo) does not
    /// pay for the same answer twice. The mark lapses on its own as soon as the
    /// interface hash moves somewhere else.</remarks>
    procedure NoteFingerprint(const AFingerprint: string);

    /// <summary>Generation of the most recent launch; 0 before the first.</summary>
    property Generation: Integer read FGeneration;
  end;

/// <summary>Offset of the top-level `implementation` keyword, and of the
/// top-level `interface` keyword, ignoring comments, string literals and
/// compiler directives.</summary>
/// <param name="ABufText">Unit source.</param>
/// <param name="AIfaceStart">1-based offset of `interface`, or 1 if absent.</param>
/// <param name="AImplStart">1-based offset of `implementation`, or
/// Length+1 if absent.</param>
/// <param name="ACandidates">How many `implementation` keywords were seen
/// outside comments and strings. More than one means at least one sits in a
/// conditional branch; the LAST wins, which over-fires rather than missing.</param>
procedure FindSplit(const ABufText: string; out AIfaceStart, AImplStart: Integer;
                    out ACandidates: Integer);

/// <summary>The interface half of a buffer: from `interface` up to, but not
/// including, `implementation`.</summary>
/// <param name="ABufText">Unit source.</param>
/// <returns>The interface text, or the whole buffer if the unit has no
/// recognisable `implementation` -- the conservative answer, since a buffer
/// this scanner cannot read is one whose interface edits must still fire.</returns>
function InterfaceHalf(const ABufText: string): string;

/// <summary>SHA-256 of <see cref="InterfaceHalf"/>, lowercase hex.</summary>
/// <param name="ABufText">Unit source.</param>
/// <returns>64 hex characters; '' only for an empty interface half.</returns>
/// <remarks>SHA-256 rather than the runner's 32-bit CheapHash on purpose: a
/// collision here is a fan-out that never fires, and a rolling 32-bit hash over
/// text a developer is editing one character at a time is exactly the input a
/// weak hash collides on.</remarks>
function InterfaceHalfHash(const ABufText: string): string;

/// <summary>Cheap rolling hash of a whole buffer, used only to skip the split
/// scan when nothing changed at all.</summary>
/// <param name="S">Any text.</param>
/// <returns>A 32-bit hash. Never used to decide that a fan-out is
/// unnecessary -- only that a poll saw no edit whatsoever.</returns>
function CheapBufferHash(const S: string): Cardinal;

implementation

uses
  System.Hash;

const
  { The classic odd-prime multiplier for a rolling string hash; the same value
    the runner's own CheapHash has used since v0.47. }
  CHEAP_HASH_MULTIPLIER = 31;

{ WRAPAROUND IS THE ALGORITHM, so overflow checking must be OFF here -- and
  ONLY here. The design-time package compiles with -$Q+ (see the dcc32 line in
  build_plugin_win32.bat), so this multiply raised EIntOverflow after about
  seven characters, EVERY TIME. It was invisible for two reasons at once: the
  caller ended in a bare `except` with an empty body, and the console test
  harness builds with plain dcc64, where overflow checking is OFF -- so
  run_surface_split.ps1 passed 35/35 against a function that could not survive
  a single call inside the shipped BPL.

  MEASURED 2026-09-11: 105 EIntOverflow in one session; the fan-out had never
  once run. }
{$OVERFLOWCHECKS OFF}
function CheapBufferHash(const S: string): Cardinal;
var
  i: Integer;
begin
  Result:= Cardinal(Length(S));
  for i:= 1 to Length(S) do Result:= (Result * CHEAP_HASH_MULTIPLIER) + Cardinal(Ord(S[i]));
end;
{$IFOPT Q+}{$MESSAGE ERROR 'overflow checks must be off for the hash above'}{$ENDIF}
{$OVERFLOWCHECKS ON}

function IsIdentChar(C: Char): Boolean; inline;
begin
  Result:= CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

{ Word at APos, lowercased, bounded by non-identifier characters on both sides.
  The left bound is the caller's business (it only calls here at a word start). }
function WordAtIs(const S: string; APos: Integer; const AWord: string): Boolean;
var
  L: Integer;
begin
  L:= Length(AWord);
  Result:= (APos + L - 1 <= Length(S))
       and ((APos + L > Length(S)) or not IsIdentChar(S[APos + L]))
       and SameText(Copy(S, APos, L), AWord);
end;

procedure FindSplit(const ABufText: string; out AIfaceStart, AImplStart: Integer;
                    out ACandidates: Integer);
type
  TScanState = (ssCode, ssLineComment, ssBraceComment, ssParenComment, ssString);
var
  i, N   : Integer   ;
  State  : TScanState;
  AtWord : Boolean   ;
begin
  AIfaceStart:= 1;
  AImplStart := Length(ABufText) + 1;
  ACandidates:= 0;
  N:= Length(ABufText);
  State := ssCode;
  { True when position i can begin a keyword -- i.e. the previous character was
    not part of an identifier. Carried, not recomputed, so `TImplementation`
    cannot be read as the keyword. }
  AtWord:= True;
  i:= 1;
  while i <= N do
  begin
    case State of
      ssCode:
        begin
          if (ABufText[i] = '/') and (i < N) and (ABufText[i + 1] = '/') then
          begin
            State:= ssLineComment;
            Inc(i, 2);
            AtWord:= True;
            Continue;
          end;
          { A $-prefixed directive is a brace comment to this scanner, which is
            also what it is to the compiler -- so a disabled branch is scanned
            like any other text. That is the case FindSplit answers by taking
            the LAST candidate rather than the first. }
          if ABufText[i] = '{' then
          begin
            State:= ssBraceComment;
            Inc(i);
            AtWord:= True;
            Continue;
          end;
          if (ABufText[i] = '(') and (i < N) and (ABufText[i + 1] = '*') then
          begin
            State:= ssParenComment;
            Inc(i, 2);
            AtWord:= True;
            Continue;
          end;
          if ABufText[i] = '''' then
          begin
            State:= ssString;
            Inc(i);
            AtWord:= False;
            Continue;
          end;
          if AtWord then
          begin
            if (AIfaceStart = 1) and WordAtIs(ABufText, i, 'interface') then AIfaceStart:= i
            else if WordAtIs(ABufText, i, 'implementation') then
            begin
              { LAST wins. A candidate inside a conditional branch BEFORE the
                real one would split early and lose interface text to the
                implementation half -- a silent miss. Splitting late only costs
                a fan-out that did not need to happen. }
              AImplStart:= i;
              Inc(ACandidates);
            end;
          end;
          AtWord:= not IsIdentChar(ABufText[i]);
          Inc(i);
        end;

      ssLineComment:
        begin
          if CharInSet(ABufText[i], [#10, #13]) then State:= ssCode;
          Inc(i);
        end;

      ssBraceComment:
        begin
          { Brace comments do NOT nest, so an $IFDEF written inside one ends
            it at that directive's own closing brace. Reproducing the compiler here
            than being clever is the point. }
          if ABufText[i] = '}' then State:= ssCode;
          Inc(i);
        end;

      ssParenComment:
        begin
          if (ABufText[i] = '*') and (i < N) and (ABufText[i + 1] = ')') then
          begin
            State:= ssCode;
            Inc(i, 2);
          end
          else Inc(i);
        end;

      ssString:
        begin
          if ABufText[i] = '''' then
          begin
            { A doubled quote is an escaped quote, not the end. }
            if (i < N) and (ABufText[i + 1] = '''') then Inc(i, 2)
            else
            begin
              State:= ssCode;
              Inc(i);
            end;
          end
          else if CharInSet(ABufText[i], [#10, #13]) then
          begin
            { An unterminated literal is a buffer mid-edit, not a file. Ending
              it at the line break keeps one stray quote from swallowing the
              rest of the unit and hiding the real `implementation`. }
            State:= ssCode;
            Inc(i);
          end
          else Inc(i);
        end;
    end; // case
  end; // while

  if AImplStart < AIfaceStart then AIfaceStart:= 1;
end;

function InterfaceHalf(const ABufText: string): string;
var
  IfaceStart, ImplStart, Candidates: Integer;
begin
  FindSplit(ABufText, IfaceStart, ImplStart, Candidates);
  Result:= Copy(ABufText, IfaceStart, ImplStart - IfaceStart);
end;

function InterfaceHalfHash(const ABufText: string): string;
var
  Half: string;
begin
  Half:= InterfaceHalf(ABufText);
  if Half = '' then Exit('');
  Result:= THashSHA2.GetHashString(Half);
end;

{ ---- TFanOutGate ---------------------------------------------------------- }

procedure TFanOutGate.UndoLaunch;
begin
  FHashAtLaunch:= FHashBeforeLaunch;
  FLastWhy     := 'launch taken back -- the caller could not start it';
end;

procedure TFanOutGate.Reset;
begin
  FFile           := '';
  FBufHash        := 0 ;
  FBufSeen        := False;
  FIfaceHash      := '';
  FHashAtLaunch   := '';
  FSilentShape    := '';
  FHashBeforeLaunch:= '';
  FLastFingerprint:= '';
  FLastChangeTick := 0 ;
end;

function TFanOutGate.Consider(const AFile, ABufText: string; ANowTick, AIdleMs: UInt64;
                              out AGeneration: Integer): Boolean;
var
  Cheap: Cardinal;
  H    : string  ;
begin
  Result     := False;
  AGeneration:= 0;
  { FIVE DISTINCT REFUSALS USED TO LOOK IDENTICAL from outside -- Consider
    returned a bare False and the caller could not say which gate held it. That
    made "the fan-out never fired" undiagnosable without a debugger attached to
    a running IDE. LastWhy costs one string assignment per poll and turns each
    refusal into a named one. It is diagnosis, not control flow: nothing reads
    it to decide anything. }
  FLastWhy:= 'considering';
  if AFile = '' then
  begin
    FLastWhy:= 'no file';
    Exit;
  end;

  { A different buffer is a baseline, never a launch: arriving on a tab is not
    editing it, and firing here would fan out on every tab switch. }
  if not SameText(AFile, FFile) then
  begin
    FLastWhy:= 'baseline captured for a newly-active buffer (no launch)';
    Reset;
    FFile        := AFile;
    FBufHash     := CheapBufferHash(ABufText);
    FBufSeen     := True;
    FIfaceHash   := InterfaceHalfHash(ABufText);
    FHashAtLaunch:= FIfaceHash;
    Exit;
  end;

  { The split scan is the only expensive thing here, so it runs on real edits
    only. This hash decides NOTHING about whether a fan-out is needed -- just
    whether the buffer moved at all since the last poll. }
  Cheap:= CheapBufferHash(ABufText);
  if (not FBufSeen) or (Cheap <> FBufHash) then
  begin
    FBufHash:= Cheap;
    FBufSeen:= True;
    H:= InterfaceHalfHash(ABufText);
    if H <> FIfaceHash then
    begin
      FIfaceHash     := H;
      FLastChangeTick:= ANowTick;
    end;
    { An implementation-only edit lands here and changes nothing: same iface
      hash, clock untouched. That is the negative control the whole feature
      depends on. }
  end;

  if FIfaceHash = FHashAtLaunch then
  begin
    FLastWhy:= 'interface unchanged since the last launch';
    Exit;
  end;
  if (FSilentShape <> '') and (FIfaceHash = FSilentShape) then
  begin
    FLastWhy:= 'this interface shape already answered the same fingerprint';
    Exit;
  end;
  if ANowTick - FLastChangeTick < AIdleMs then
  begin
    FLastWhy:= Format('interface changed, still settling (%d of %d ms)',
                      [ANowTick - FLastChangeTick, AIdleMs]);
    Exit;
  end;

  FHashBeforeLaunch:= FHashAtLaunch;   { so UndoLaunch can put it back }
  FHashAtLaunch:= FIfaceHash;
  Inc(FGeneration);
  AGeneration:= FGeneration;
  FLastWhy:= Format('LAUNCH gen %d', [FGeneration]);
  Result:= True;
end;

procedure TFanOutGate.NoteFingerprint(const AFingerprint: string);
begin
  if AFingerprint = '' then
  begin
    FLastFingerprint:= '';
    Exit;
  end;
  if AFingerprint = FLastFingerprint then FSilentShape:= FHashAtLaunch;
  FLastFingerprint:= AFingerprint;
end;

end.
