program SurfaceAdaptersTests;
{$APPTYPE CONSOLE}
{ The two producers of a surface must be comparable, and must be REFUSED when
  they are not.

  WHAT THIS PINS. lint-tree diffs a fingerprint built by the PARSER (an unsaved
  buffer) against one built by the STORE (what the index last saw). Three ways
  that goes silently wrong, all covered here:

  1. VERSION SKEW. `directives` and `vis_explicit` landed in schema 22, and a
     pre-v22 row reads back as '' and True. A baseline captured at v21 and
     diffed against a v22 parse therefore reports EVERY routine as changed --
     a whole-surface false positive indistinguishable from a real edit.
     TIndexerProfile.Matches must refuse that pairing, and must refuse the
     unknown-provenance pairing too: two EMPTY profiles are not "equal", they
     are two things we know nothing about. The empty-vs-empty case is the one a
     naive `A = B` implementation gets wrong, so it is asserted explicitly.

  2. OVER-DETECTION of expansion-visible bodies. Hashing a body that no
     dependent can see makes ordinary implementation edits fan out. The trap is
     a substring test: a routine NAMED `InlineHelper` contains "inline" but
     carries no directive. Asserted directly.

  3. UNDER-DETECTION, which is worse because it is silent: an `inline` routine
     whose body changed but whose fingerprint did not, reported as all-clear.

  THE SPAN RULE IS A CORRECTNESS PROPERTY, NOT AN EDGE CASE. A body span that
  does not fit the supplied lines is SKIPPED, never clamped. The two sides hold
  different text at different moments -- the buffer is ahead of the file -- and
  a clamped span hashes differently depending on which side clamped it, which
  would fan out on every keystroke and never converge. So "out of range yields
  no body" is asserted as behaviour, not tolerated as an accident.

  WHAT THIS DOES NOT PROVE. TryFingerprintOfIndex needs a live ISymbolStore and
  is therefore NOT exercised here; it is covered end-to-end by the B4 guard
  run_surface_fingerprint.ps1, which drives real files through the verb. The
  pure functions are the ones with the subtle contracts, and they are the ones
  a store-backed test would obscure rather than clarify. }
uses
  System.SysUtils,
  DRagLint.Core.Model      in '..\src\core\DRagLint.Core.Model.pas',
  DRagLint.Core.Interfaces in '..\src\core\DRagLint.Core.Interfaces.pas',
  DRagLint.Analysis.SurfaceFingerprint
    in '..\src\analysis\DRagLint.Analysis.SurfaceFingerprint.pas',
  DRagLint.Analysis.SurfaceAdapters
    in '..\src\analysis\DRagLint.Analysis.SurfaceAdapters.pas';

var
  GPass: Integer = 0;
  GFail: Integer = 0;

procedure Check(const AName: string; ACond: Boolean; const ADetail: string = '');
begin
  if ACond then
  begin
    Inc(GPass);
    Writeln('PASS  ', AName);
  end
  else
  begin
    Inc(GFail);
    Writeln('FAIL  ', AName, sLineBreak, '      ', ADetail);
  end;
end;

function Routine(const AQName, ADirectives: string;
  const ASection: string = 'interface';
  const AImplFrom: Integer = 1; const AImplTo: Integer = 3): TSymbol;
begin
  Result              := Default(TSymbol);
  Result.Kind         := skMethod;
  Result.Name         := AQName;
  Result.QualifiedName:= AQName;
  Result.Signature    := 'procedure ' + AQName;
  Result.Section      := ASection;
  Result.Directives   := ADirectives;
  Result.ImplStartLine:= AImplFrom;
  Result.ImplEndLine  := AImplTo;
end;

var
  Prof, Other: TIndexerProfile;
  Bodies     : TArray<TInlineBody>;
  Lines      : TArray<string>;
  Parse      : TParseResult;
  FpA, FpB   : string;
begin
  try
    Lines := ['begin', '  Result := 1;', 'end;', 'extra'];

    { ---- 1. the stamp ---- }

    Prof := ParseIndexerFingerprint('v=1.15.0-alpha;schema=22;pp=1;plat=win64');
    Check('fingerprint: extractor version parsed',
      Prof.ExtractorVersion = '1.15.0-alpha', 'got "' + Prof.ExtractorVersion + '"');
    Check('fingerprint: schema parsed', Prof.SchemaVersion = 22,
      'got ' + IntToStr(Prof.SchemaVersion));
    Check('fingerprint: pp parsed', Prof.Preprocess);
    Check('fingerprint: platform parsed', Prof.Platform = 'win64',
      'got "' + Prof.Platform + '"');
    Check('fingerprint: raw preserved',
      Prof.Raw = 'v=1.15.0-alpha;schema=22;pp=1;plat=win64');

    Other := ParseIndexerFingerprint('v=1.15.0-alpha;schema=22;pp=0;plat=win32');
    Check('MATCH same extractor+schema matches despite platform/pp differing',
      Prof.Matches(Other),
      'platform or pp leaked into the comparability test');

    Other := ParseIndexerFingerprint('v=1.14.0-alpha;schema=22;pp=1;plat=win64');
    Check('REFUSE a different extractor version', not Prof.Matches(Other));

    Other := ParseIndexerFingerprint('v=1.15.0-alpha;schema=21;pp=1;plat=win64');
    Check('REFUSE a different schema (the v21 directives trap)',
      not Prof.Matches(Other));

    Other := ParseIndexerFingerprint('');
    Check('REFUSE an empty profile', not Prof.Matches(Other));

    Prof := ParseIndexerFingerprint('');
    Check('REFUSE empty vs empty (unknown is not equal)',
      not Prof.Matches(Other),
      'two unknown provenances were treated as comparable');

    Prof := ParseIndexerFingerprint('garbage without separators');
    Check('REFUSE an unparseable profile', not Prof.Matches(Prof));

    { ---- 2. expansion-visible detection ---- }

    Bodies := CollectInlineBodies([Routine('uB.TW.Fast', 'inline')], Lines);
    Check('BODY an inline routine is collected', Length(Bodies) = 1,
      'got ' + IntToStr(Length(Bodies)));

    Bodies := CollectInlineBodies([Routine('uB.TW.InlineHelper', '')], Lines);
    Check('BODY a routine merely NAMED Inline* is not collected',
      Length(Bodies) = 0, 'substring match instead of whole-word directive');

    Bodies := CollectInlineBodies([Routine('uB.TW.Slow', 'virtual overload')],
      Lines);
    Check('BODY other directives do not qualify', Length(Bodies) = 0);

    Bodies := CollectInlineBodies(
      [Routine('uB.TW.Fast', 'overload inline register')], Lines);
    Check('BODY inline is found among several directives', Length(Bodies) = 1);

    Bodies := CollectInlineBodies([Routine('uB.TList<T>.Add', '')], Lines);
    Check('BODY a generic method is collected', Length(Bodies) = 1,
      'generics are instantiated in the caller and must be hashed');

    Bodies := CollectInlineBodies(
      [Routine('uB.TW.Fast', 'inline', 'implementation')], Lines);
    Check('BODY an implementation-section routine is excluded',
      Length(Bodies) = 0);

    { ---- 3. the span rule ---- }

    Bodies := CollectInlineBodies(
      [Routine('uB.TW.Fast', 'inline', 'interface', 1, 99)], Lines);
    Check('SPAN an out-of-range span is SKIPPED, not clamped',
      Length(Bodies) = 0, 'a clamped span would never converge');

    Bodies := CollectInlineBodies(
      [Routine('uB.TW.Fast', 'inline', 'interface', 0, 2)], Lines);
    Check('SPAN a zero start line is skipped', Length(Bodies) = 0);

    Bodies := CollectInlineBodies(
      [Routine('uB.TW.Fast', 'inline', 'interface', 3, 2)], Lines);
    Check('SPAN an inverted span is skipped', Length(Bodies) = 0);

    Bodies := CollectInlineBodies(
      [Routine('uB.TW.Fast', 'inline', 'interface', 1, 3)], Lines);
    Check('SPAN an in-range span yields the text',
      (Length(Bodies) = 1) and (Pos('Result := 1', Bodies[0].BodyText) > 0),
      'span text missing or wrong');
    Check('SPAN the body is keyed by qualified name',
      (Length(Bodies) = 1) and (Bodies[0].QualifiedName = 'uB.TW.Fast'));

    { ---- 4. the parse-side adapter ---- }

    Parse             := Default(TParseResult);
    Parse.Symbols     := [Routine('uB.TW.Fast', 'inline')];
    Parse.UsesEntries := [];
    FpA := FingerprintOfParse(Parse, Lines);
    Check('PARSE a fingerprint comes out of a parse result', FpA <> '');

    FpB := FingerprintOfParse(Parse, Lines);
    Check('PARSE it is stable', FpA = FpB);

    Lines := ['begin', '  Result := 2;', 'end;', 'extra'];
    Check('PARSE editing the inline body changes it',
      FingerprintOfParse(Parse, Lines) <> FpA,
      'the body text did not reach the fingerprint');

    Parse.Symbols := [Routine('uB.TW.Slow', 'virtual')];
    Lines         := ['begin', '  Result := 1;', 'end;', 'extra'];
    FpA           := FingerprintOfParse(Parse, Lines);
    Lines         := ['begin', '  Result := 999;', 'end;', 'extra'];
    Check('PARSE editing a NON-inline body does not change it',
      FingerprintOfParse(Parse, Lines) = FpA,
      'an ordinary implementation edit would fan out');

    Check('ADAPTER a nil store yields an empty profile',
      IndexProfileOf(nil).ExtractorVersion = '');
  except
    on E: Exception do
    begin
      Inc(GFail);
      Writeln('FAIL  unhandled ', E.ClassName, ': ', E.Message);
    end;
  end;

  Writeln;
  Writeln(Format('%d passed, %d failed', [GPass, GFail]));
  if GFail > 0 then Halt(1);
end.
