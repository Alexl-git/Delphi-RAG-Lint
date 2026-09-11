program UpdateCheckTests;
{$APPTYPE CONSOLE}
{ Everything the update check DECIDES, decided without an IDE and without a
  network.

  WHAT THIS PINS. The About dialog will ask GitHub for the latest release tag
  of drag-lint and YADF and say whether a newer one exists. The asking needs a
  network and the saying needs a dialog; the DECIDING needs neither, and it is
  the deciding that goes wrong silently:

    a STRING compare is used -> '1.10.1' sorts BELOW '1.4.0', so the newest
      build on this machine is reported as out of date and the user is sent to
      download an OLDER release. This is not hypothetical: drag-lint's local
      version really is 1.10.1-alpha and its newest published release really is
      v1.4.0-alpha, so the wrong comparator is wrong on the very first use.

    the TAG SHAPE is assumed -> the two repos do not agree. YADF tags
      '1.0.17.0' (four fields, no prefix); drag-lint tags 'v1.4.0-alpha' (a 'v'
      prefix, three fields, a prerelease suffix). A parser written against
      either one alone silently returns 0.0.0.0 for the other, which reads as
      "you are up to date" forever.

    a FAILED fetch is treated as an answer -> offline, rate-limited or a typo'd
      repo must never render as "up to date", because that is the one outcome
      indistinguishable from a working check.

  THE NEGATIVE CONTROLS ARE THE POINT. A comparator hard-wired to return "no
  update" passes every "does not claim a false update" assertion on its own.
  Every case below is therefore asserted in BOTH directions. }
uses
  System.SysUtils,
  DragLint.Plugin.Updates in '..\src\delphi-plugin\DragLint.Plugin.Updates.pas';

var
  GPass, GFail: Integer;

procedure Check(const AName: string; ACond: Boolean; const ADetail: string = '');
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else
  begin
    Inc(GFail);
    Writeln('FAIL  ', AName);
    if ADetail <> '' then Writeln('      ', ADetail);
  end;
end;

procedure TestNormalize;
begin
  Writeln('-- normalise: the two repos do not agree on tag shape --');
  Check('1a plain four-field tag survives',
        NormalizeVersionText('1.0.17.0') = '1.0.17.0',
        NormalizeVersionText('1.0.17.0'));
  Check('1b a leading v is stripped',
        NormalizeVersionText('v1.4.0-alpha') = '1.4.0.0',
        NormalizeVersionText('v1.4.0-alpha'));
  Check('1c an uppercase V is stripped too',
        NormalizeVersionText('V2.1') = '2.1.0.0',
        NormalizeVersionText('V2.1'));
  Check('1d a prerelease suffix is dropped',
        NormalizeVersionText('1.10.1-alpha') = '1.10.1.0',
        NormalizeVersionText('1.10.1-alpha'));
  Check('1e build metadata is dropped',
        NormalizeVersionText('1.2.3+build99') = '1.2.3.0',
        NormalizeVersionText('1.2.3+build99'));
  Check('1f missing fields pad with zero, they do not fail',
        NormalizeVersionText('3') = '3.0.0.0',
        NormalizeVersionText('3'));
  { A negative control for the normaliser itself: it must not invent a version
    out of text that has no numbers, or every garbage answer becomes 0.0.0.0
    and compares equal to a genuinely unknown local version. }
  Check('1g non-numeric text does NOT normalise to a version',
        NormalizeVersionText('not-a-release') = '',
        '[' + NormalizeVersionText('not-a-release') + ']');
end;

procedure TestCompare;
begin
  Writeln;
  Writeln('-- compare: field by field, numerically --');
  Check('2a equal versions compare equal',
        CompareVersions('1.0.17.0', '1.0.17.0') = 0);
  Check('2b a higher FIRST field wins regardless of the rest',
        CompareVersions('2.0.0.0', '1.99.99.99') > 0);
  Check('2c then the second field',
        CompareVersions('1.5.0.0', '1.4.99.99') > 0);
  Check('2d then the third',
        CompareVersions('1.0.17.0', '1.0.16.99') > 0);
  Check('2e then the fourth',
        CompareVersions('1.0.0.2', '1.0.0.1') > 0);

  { THE CASE THAT BREAKS A STRING COMPARE, and the one that is live today. }
  Check('2f 1.10.1 is NEWER than 1.4.0 (string compare says the opposite)',
        CompareVersions('1.10.1.0', '1.4.0.0') > 0,
        'got ' + IntToStr(CompareVersions('1.10.1.0', '1.4.0.0')));
  Check('2g and the reverse is negative, not zero',
        CompareVersions('1.4.0.0', '1.10.1.0') < 0);

  Check('2h shapes are normalised before comparing',
        CompareVersions('v1.4.0-alpha', '1.4') = 0,
        'a v-prefixed 3-field tag and a bare 2-field one are the same version');
end;

procedure TestIsUpdateAvailable;
var
  Reason: string;
begin
  Writeln;
  Writeln('-- the question the dialog actually asks --');
  Check('3a a genuinely newer remote IS an update',
        IsUpdateAvailable('1.0.17.0', '1.0.16.0', Reason));
  Check('3b an equal remote is NOT an update',
        not IsUpdateAvailable('1.0.17.0', '1.0.17.0', Reason));

  { LOCAL AHEAD OF REMOTE IS THE LIVE CASE. drag-lint builds 1.10.1-alpha while
    its newest release is v1.4.0-alpha, so this is what the first real click
    will hit. It must not nag, and it must not claim to be "up to date" either
    -- the honest answer is that the local build is ahead. }
  Check('3c a local build AHEAD of the release is NOT an update',
        not IsUpdateAvailable('v1.4.0-alpha', '1.10.1-alpha', Reason));
  Check('3d ... and it says so, rather than "up to date"',
        Pos('ahead', LowerCase(Reason)) > 0,
        '[' + Reason + ']');

  { A FAILED FETCH MUST NOT RENDER AS "UP TO DATE". That is the one wrong
    answer nobody re-checks. }
  Check('3e an empty remote tag is NOT an update',
        not IsUpdateAvailable('', '1.0.0.0', Reason));
  Check('3f ... and it is reported as UNKNOWN, not as up to date',
        Pos('unknown', LowerCase(Reason)) > 0,
        '[' + Reason + ']');
  Check('3g unparseable remote text is UNKNOWN too',
        (not IsUpdateAvailable('not-a-release', '1.0.0.0', Reason))
        and (Pos('unknown', LowerCase(Reason)) > 0),
        '[' + Reason + ']');
  Check('3h an unknown LOCAL version is also unknown, not an update',
        (not IsUpdateAvailable('1.0.0.0', '', Reason))
        and (Pos('unknown', LowerCase(Reason)) > 0),
        '[' + Reason + ']');
end;

procedure TestComponents;
var
  C: TDLComponentInfo;
begin
  Writeln;
  Writeln('-- the components the dialog reports on --');
  Check('4a drag-lint and YADF are both registered',
        Length(DLUpdateComponents) >= 2,
        IntToStr(Length(DLUpdateComponents)));
  for C in DLUpdateComponents do
  begin
    Check('4b ' + C.DisplayName + ' names a repo', C.Repo <> '');
    Check('4c ' + C.DisplayName + ' has a releases URL', Pos('github.com', C.ReleasesUrl) > 0);
    Check('4d ' + C.DisplayName + ' has a changelog URL', Pos('CHANGELOG', C.ChangelogUrl) > 0);
  end;
end;

begin
  try
    GPass:= 0; GFail:= 0;
    TestNormalize;
    TestCompare;
    TestIsUpdateAvailable;
    TestComponents;
    Writeln;
    Writeln(Format('%d passed, %d failed', [GPass, GFail]));
    if GFail > 0 then Halt(1);
  except
    on E: Exception do
    begin
      Writeln('EXCEPTION: ', E.ClassName, ': ', E.Message);
      Halt(2);
    end;
  end;
end.
