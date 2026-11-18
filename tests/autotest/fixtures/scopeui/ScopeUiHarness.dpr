program ScopeUiHarness;
{ Lane BK-SCOPEUI (1.52) headless checks for the Lint Options frame: B36 (an unsaved rule
  toggle survives a search refill) and B44 (rule_overrides captions and the Overrides
  button). Built by run_v152_BK-SCOPEUI.ps1 against a private->public copy of
  DragLint.Plugin.LintOptionsFrame and a stub ToolsAPI. Args: <rules-sample.json>.
  Exit 0 = all pass, 1 = any failure. }
{$APPTYPE CONSOLE}
uses
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls,
  DRagLint.Lint.Config,
  DragLint.Plugin.PlugUiCore,
  DragLint.Plugin.LintOptionsFrame;

var
  Failed: Integer = 0;
  F     : TLintOptionsFrame;
  Json  : string;

procedure Check(const AName: string; AOk: Boolean; const ADetail: string = '');
begin
  if AOk then Writeln('  [PASS] ', AName)
  else
  begin
    Writeln('  [FAIL] ', AName, ' ', ADetail);
    Inc(Failed);
  end;
end;

procedure PumpFor(AMs: Cardinal);
var
  T0: UInt64;
begin
  T0:= GetTickCount64;
  while GetTickCount64 - T0 < AMs do
  begin
    Application.ProcessMessages;
    Sleep(5);
  end;
end;

{ The rule checkbox of one rule id, nil when it is not rendered (filtered out). }
function FindRuleCB(const AId: string): TCheckBox;
var
  I, J: Integer;
  GB  : TGroupBox;
begin
  Result:= nil;
  for I:= 0 to F.FScroll.ControlCount - 1 do
    if F.FScroll.Controls[I] is TGroupBox then
    begin
      GB:= TGroupBox(F.FScroll.Controls[I]);
      for J:= 0 to GB.ControlCount - 1 do
        { a rule checkbox is captioned '<id> - <title>'; category headers are not }
        if (GB.Controls[J] is TCheckBox) and (Pos(AId + ' - ', TCheckBox(GB.Controls[J]).Caption) = 1) then
          Exit(TCheckBox(GB.Controls[J]));
    end;
end;

procedure SetSearch(const AText: string);
begin
  F.FEdtSearch.Text:= AText;
  PumpFor(SEARCH_DEBOUNCE_MS + 250);
end;

procedure TestToggleSurvivesRefill;
var
  CB: TCheckBox;
  Was: Boolean;
begin
  Writeln('== unsaved rule toggle survives a search refill (B36) ==');
  F.ShowCatalog(0, Json);
  PumpFor(100);
  CB:= FindRuleCB('char-count-as-bytes');
  Check('rule is rendered', CB <> nil);
  if CB = nil then Exit;
  Was:= CB.Checked;
  CB.Checked:= not Was;           { a user click: RuleChecked marks the frame dirty }
  Check('toggle marks the frame dirty', F.FDirty);

  SetSearch('address-of-local');  { filters char-count-as-bytes OUT, refilling from the saved config }
  Check('the toggled rule is filtered out', FindRuleCB('char-count-as-bytes') = nil);
  Check('the refill keeps the unsaved marker', F.FDirty);
  SetSearch('');                  { all rules back }
  CB:= FindRuleCB('char-count-as-bytes');
  Check('the rule is back', CB <> nil);
  if CB <> nil then Check('its unsaved toggle was kept', CB.Checked = (not Was), 'checked=' + BoolToStr(CB.Checked, True));
  Check('still dirty after the second refill', F.FDirty);

  SetSearch('char-count');        { toggled rule stays visible: the refill must not undo it either }
  CB:= FindRuleCB('char-count-as-bytes');
  if CB <> nil then Check('visible through a narrowing refill too', CB.Checked = (not Was));
  SetSearch('');
end;

procedure TestOverrideCaptions;
var
  R: TRuleOverride;
begin
  Writeln('== rule_overrides captions (B44) ==');
  R:= Default(TRuleOverride);
  R.RuleId:= 'magic-number'; R.HasEnabled:= True; R.Enabled:= False; R.Reason:= 'legacy'; R.Date:= '2026-11-18';
  Check('project disable names rule, scope, reason and date',
    RuleOverrideCaption(R) = 'magic-number - off for the project (legacy, 2026-11-18)', RuleOverrideCaption(R));
  R:= Default(TRuleOverride);
  R.RuleId:= 'deep-nesting'; R.ExcludeUnits:= ['uOld', 'uOlder'];
  Check('unit exclusion lists the units', RuleOverrideCaption(R) = 'deep-nesting - off in unit uOld, uOlder', RuleOverrideCaption(R));
  Check('button caption without overrides', OverridesButtonCaption(0) = 'Overrides...');
  Check('button caption with overrides', OverridesButtonCaption(3) = 'Overrides (3)...');
  Check('frame has the Overrides button', F.FBtnOverrides <> nil);
  if F.FBtnOverrides <> nil then Check('button starts at zero overrides', F.FBtnOverrides.Caption = 'Overrides...');
end;

begin
  Application.Initialize;
  Json:= TFile.ReadAllText(ParamStr(1));
  F:= TLintOptionsFrame.Create(nil);
  try
    F.Width:= 1000;
    F.Height:= 800;
    F.Show;
    Application.ProcessMessages;
    TestToggleSurvivesRefill;
    TestOverrideCaptions;
  finally
    F.FDirty:= False;
    F.Free;
  end;
  if Failed > 0 then
  begin
    Writeln('FAILED: ', Failed);
    Halt(1);
  end;
  Writeln('ALL PASS');
end.