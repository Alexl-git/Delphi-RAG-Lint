{ A4 #migrate slice 1 (spec docs\superpowers\specs\2026-10-23-converter-migrate-slice1-design.md,
  owner rulings section 12a). Captures: tests\fixtures\migrate\apply-*-1350.json, made by
  capture-migrate.ps1 on the 1.35.0-alpha pin (20261025-125433). }

function MigrateFixture(const AName: string): string;
begin
  Result:= TFile.ReadAllText(TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), 'fixtures\migrate\' + AName)));
end;

function MigrateApply(const AName: string; AFeatures: TApplyFeatures): TApplyRow;
begin
  Result:= ParseApplyJson(MigrateFixture(AName), AFeatures);
end;

function MigBook(const ALines: array of string): TRuleBook;
var
  LText: string;
begin
  LText:= '';
  for var LLine: string in ALines do
    LText:= LText + LLine + sLineBreak;
  Result:= TRuleBook.Create;
  Result.LoadFromString(LText);
end;

procedure TestMigrateModel;
var
  B: TRuleBook;
  N: TRuleNode;
begin
  B:= MigBook(['#migrate Click -> Press', '#migrate Count -> dl_none',
    '#migrate TUpdateKind -> TFDUpdateRequest, FireDAC.Phys.Intf', '#migrate X -> Y, A, B',
    '#migrate TFoo:Click -> Press', '#migrate btn.Click -> Press', '#migrate TFoo:btn.Click -> Press',
    '#migrate Foo -> ', '#migrate ABC(x) -> X', '#migrate ABC -> Repl({inst})']);
  try
    N:= B.Nodes[0];
    Check('migrate.parse.plain', (N.Kind = rnkMigrate) and (N.MigScope = '') and (N.MigOld = 'Click') and (N.MigNew = 'Press') and (N.MigUnits = ''),
      Format('scope=%s old=%s new=%s units=%s', [N.MigScope, N.MigOld, N.MigNew, N.MigUnits]));
    N:= B.Nodes[1];
    Check('migrate.parse.dlnone', (N.MigNew = 'dl_none') and IsDeliberateBreak(N) and IsMemberMigrate(N), N.MigNew);
    N:= B.Nodes[2];
    Check('migrate.parse.units', (N.MigNew = 'TFDUpdateRequest') and (N.MigUnits = 'FireDAC.Phys.Intf') and not IsMemberMigrate(N), N.MigUnits);
    Check('migrate.parse.units.two', B.Nodes[3].MigUnits = 'A, B', B.Nodes[3].MigUnits);
    Check('migrate.parse.scope.class', (B.Nodes[4].MigScope = 'TFoo:') and (B.Nodes[4].MigOld = 'Click'), B.Nodes[4].MigScope);
    Check('migrate.parse.scope.obj', (B.Nodes[5].MigScope = 'btn.') and (B.Nodes[5].MigOld = 'Click'), B.Nodes[5].MigScope);
    // The engine's SplitMigrateLhs gives Scope 'TFoo: btn.' (whitespace-normalised), Old 'Click'.
    Check('migrate.parse.scope.both', (B.Nodes[6].MigScope = 'TFoo:btn.') and (B.Nodes[6].MigOld = 'Click'), B.Nodes[6].MigScope);
    N:= B.Nodes[7];
    Check('migrate.parse.fromonly', (N.MigOld = 'Foo') and (N.MigNew = '') and (MigrateRefusal(N) = MIGRATE_REFUSAL_NO_NEW), N.MigOld + '|' + MigrateRefusal(N));
    Check('migrate.parse.template', (not IsMemberMigrate(B.Nodes[8])) and (MigrateRefusal(B.Nodes[8]) = MIGRATE_REFUSAL_CALL), MigrateRefusal(B.Nodes[8]));
    Check('migrate.parse.newtemplate', MigrateRefusal(B.Nodes[9]) = MIGRATE_REFUSAL_TEMPLATE, MigrateRefusal(B.Nodes[9]));
    Check('migrate.refusal.scope', (MigrateRefusal(B.Nodes[4]) = MIGRATE_REFUSAL_SCOPED) and (MigrateRefusal(B.Nodes[6]) = MIGRATE_REFUSAL_SCOPED), MigrateRefusal(B.Nodes[4]));
    Check('migrate.refusal.units', MigrateRefusal(B.Nodes[2]) = MIGRATE_REFUSAL_UNITS, MigrateRefusal(B.Nodes[2]));
    Check('migrate.refusal.none', MigrateRefusal(B.Nodes[0]) = '', MigrateRefusal(B.Nodes[0]));
    var LRaw: Boolean:= True;
    for N in B.Nodes do
      LRaw:= LRaw and (N.Emit = N.Raw) and not N.Dirty;
    Check('migrate.emit.untouched', LRaw);
    B.Nodes[0].Dirty:= True;
    B.Nodes[2].Dirty:= True;
    B.Nodes[4].Dirty:= True;
    Check('migrate.emit.dirty', (B.Nodes[0].Emit = '#migrate Click -> Press') and (B.Nodes[2].Emit = '#migrate TUpdateKind -> TFDUpdateRequest, FireDAC.Phys.Intf')
      and (B.Nodes[4].Emit = '#migrate TFoo:Click -> Press'), B.Nodes[0].Emit + '|' + B.Nodes[2].Emit + '|' + B.Nodes[4].Emit);
    B.Nodes[0].Dirty:= False;
    var LMark: TRuleMark:= Default(TRuleMark);
    LMark.Text:= 'm';
    B.Nodes[0].Marks:= [LMark];
    B.Nodes[1].Marks:= [LMark];
    SetMigrateNew(B.Nodes[0], 'Tap');
    Check('migrate.emit.setnew', (B.Nodes[0].Emit = '#migrate Click -> Tap') and B.Nodes[0].Dirty and (Length(B.Nodes[0].Marks) = 0) and (Length(B.Nodes[1].Marks) = 1),
      B.Nodes[0].Emit);
    Check('migrate.linetext', MigrateLineText('Click', 'Press') = '#migrate Click -> Press', MigrateLineText('Click', 'Press'));
  finally
    B.Free;
  end;
end;

procedure TestMigrateBdeTail;
var
  LPath: string;
  B    : TRuleBook;
  LText: string;
  LAll, LMember, LRefUnits: Integer;
begin
  LPath:= TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\..\..\..\convrules\BDE-to-FireDAC.rules'));
  if not TFile.Exists(LPath) then
  begin
    Skip('migrate.bde.tail', 'no ' + LPath);
    Exit;
  end;
  LText:= TFile.ReadAllText(LPath);
  B:= TRuleBook.Create;
  try
    B.LoadFromString(LText);
    LAll:= 0;
    LMember:= 0;
    LRefUnits:= 0;
    for var N: TRuleNode in B.Nodes do
      if N.Kind = rnkMigrate then
      begin
        Inc(LAll);
        if IsMemberMigrate(N) then
          Inc(LMember);
        if MigrateRefusal(N) = MIGRATE_REFUSAL_UNITS then
          Inc(LRefUnits);
      end;
    // MEASURED 2026-10-26 on the old 43-line tail: 15 member form, 25 with units, 3 scoped / dotted.
    // D2 split 2026-10-27 moved the 15 Data.DB lines to DataDB-to-FireDAC.rules; MEASURED after the
    // split: 28 lines, 11 member form, 14 with units, 3 scoped / dotted. Q4b (2026-10-27) re-homed
    // UpdateRecordTypes into the TTable/TQuery/TStoredProc blocks: 27 + 3 = 30 lines, 13 member form. Pinned so a corpus edit is noticed.
    Check('migrate.bde.tail', (LAll = 30) and (LMember = 13) and (LRefUnits = 14) and (B.SaveToString = LText),
      Format('all=%d member=%d units=%d roundtrip=%s', [LAll, LMember, LRefUnits, BoolToStr(B.SaveToString = LText, True)]));
  finally
    B.Free;
  end;
end;

procedure TestDataDbBook;
var
  LPath: string;
  B    : TRuleBook;
  LText: string;
  LAll : Integer;
begin
  LPath:= TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\..\..\..\convrules\DataDB-to-FireDAC.rules'));
  if not TFile.Exists(LPath) then
  begin
    Skip('datadb.book', 'no ' + LPath);
    Exit;
  end;
  LText:= TFile.ReadAllText(LPath);
  var LBlocks: TRuleBlocks:= SplitRulesBlocks(LText);
  var LConverts: Integer:= 0;
  for var LBlock: TRuleBlock in LBlocks do
    if LBlock.Kind = rbkConvert then
      Inc(LConverts);
  Check('datadb.book.headers', (LConverts = 3) and (CountDirectiveInText(LText, '#convert') = 3), IntToStr(LConverts));
  Check('datadb.book.no.trailer', (Length(LBlocks) = 4) and (LBlocks[0].Kind = rbkPreamble), 'preamble + 3 rules, no trailing block');
  Check('datadb.book.remove.hasconstraints', Pos('#remove HasConstraints' + #13#10, LText) > 0, 'travels with the TAutoIncField block');
  Check('datadb.book.no.bde.type', Pos('#convert Bde.', LText) = 0, 'every rule is Data.DB-declared');
  Check('datadb.book.apply.integrity', CheckApplyIntegrity(LText).OK, 'no #apply without its #mapping: ' + CheckApplyIntegrity(LText).Summary);
  B:= TRuleBook.Create;
  try
    B.LoadFromString(LText);
    LAll:= 0;
    for var N: TRuleNode in B.Nodes do
      if N.Kind = rnkMigrate then
        Inc(LAll);
    Check('datadb.book.migrate', (LAll = 15) and (B.SaveToString = LText), Format('migrate=%d roundtrip=%s', [LAll, BoolToStr(B.SaveToString = LText, True)]));
  finally
    B.Free;
  end;
end;
procedure TestMigrateBlocks;
var
  B   : TRuleBook;
  LHdr: TRuleNode;
  LNew: TRuleNode;
begin
  B:= MigBook(['#migrate G -> H', '#convert TA -> TB', '#link X <- Y', '#migrate Click -> Press', '#migrate Click -> Q, U',
    '#convert TC -> TD', '#migrate Count -> DL_NONE']);
  try
    Check('migrate.block.for', (Length(MigratesForBlock(B, 1)) = 2) and (Length(MigratesForBlock(B, 5)) = 1),
      Format('%d/%d', [Length(MigratesForBlock(B, 1)), Length(MigratesForBlock(B, 5))]));
    Check('migrate.block.header.of', (HeaderIndexOfNode(B, B.Nodes[0]) = -1) and (HeaderIndexOfNode(B, B.Nodes[3]) = 1) and (HeaderIndexOfNode(B, B.Nodes[6]) = 5),
      Format('%d/%d/%d', [HeaderIndexOfNode(B, B.Nodes[0]), HeaderIndexOfNode(B, B.Nodes[3]), HeaderIndexOfNode(B, B.Nodes[6])]));
    Check('migrate.block.find', (FindMigrateInBlock(B, 1, 'click') = B.Nodes[3]) and (FindMigrateInBlock(B, 5, 'Click') = nil)
      and (FindMigrateInBlock(B, 1, 'Q') = nil));
  finally
    B.Free;
  end;

  B:= MigBook(['#convert TA -> TB', '#link X <- Y', '', '// c', '#convert TC -> TD', '#link P <- Q']);
  try
    AddMigrate(B, 0, 'Click', 'Press');
    Check('migrate.add.end', B.SaveToString = '#convert TA -> TB' + sLineBreak + '#link X <- Y' + sLineBreak + '#migrate Click -> Press' + sLineBreak + sLineBreak
      + '// c' + sLineBreak + '#convert TC -> TD' + sLineBreak + '#link P <- Q' + sLineBreak, B.SaveToString);
    LNew:= AddMigrate(B, 5, 'Count', 'DL_NONE');
    Check('migrate.add.last.block', (B.Nodes.Last = LNew) and LNew.Dirty and (LNew.Emit = '#migrate Count -> DL_NONE'), LNew.Emit);
  finally
    B.Free;
  end;

  // The index-shift trap: a node inserted before the block moves every header index.
  B:= MigBook(['#convert TA -> TB', '#link X <- Y', '#convert TC -> TD', '#link P <- Q']);
  try
    var LStale: Integer:= 2;
    LHdr:= B.Nodes[LStale];
    var LDepth: TRuleNode:= B.ParseLine('#depth 3');
    B.Nodes.Insert(0, LDepth);
    LNew:= AddMigrate(B, B.Nodes.IndexOf(LHdr), 'Click', 'Press');
    Check('migrate.add.depth.shift', HeaderIndexOfNode(B, LNew) = B.Nodes.IndexOf(LHdr), B.SaveToString);
    LNew:= AddMigrate(B, LStale, 'Hint', 'Tip');
    // Positive control: the stale index 2 is now '#link X <- Y', no header -- nothing is written.
    Check('migrate.add.depth.stale', LNew = nil, B.SaveToString);
  finally
    B.Free;
  end;
end;

procedure TestMigrateApply;
const
  LEGACY_RULE_LINES: array[0..4] of Integer = (3, 4, 6, 8, 9);
var
  Ren, Dl, Sf, Wi, Leg, Lnk, Ctl: TApplyRow;
  LOk: Boolean;
begin
  Check('migrate.features.of', (ApplyFeaturesOf(['MIGRATE_MEMBERS']) = [afMigrateMembers]) and not (afMigrateMembers in ApplyFeaturesOf(['pas_uses'])));
  Ren:= MigrateApply('apply-MigForm-rename-1350.json', [afMigrateMembers]);
  Check('migrate.rename.count', (Length(Ren.MigrateApplied) = 4) and (Length(Ren.DeliberateBreaks) = 0) and (Length(Ren.MigrateChecks) = 0),
    Format('%d/%d/%d', [Length(Ren.MigrateApplied), Length(Ren.DeliberateBreaks), Length(Ren.MigrateChecks)]));
  if Length(Ren.MigrateApplied) > 0 then
    with Ren.MigrateApplied[0] do
      Check('migrate.rename.item0', (Kind = APPLY_KIND_MIGRATE_APPLIED) and (Instance = 'btnTop') and EndsText('MigForm.pas', FileName) and (Path = 'Click')
        and (Value = 'Press') and (OldValue = 'Click') and (Line = 27) and (RuleLine = 3), Format('%s %s %s %s %s %d %d', [Kind, Instance, Path, Value, OldValue, Line, RuleLine]))
  else
    Check('migrate.rename.item0', False, 'no item');
  Dl:= MigrateApply('apply-DlForm-dlnone-1350.json', [afMigrateMembers]);
  Check('migrate.dlnone.counts', (Length(Dl.DeliberateBreaks) = 2) and (Length(Dl.MigrateApplied) = 1), Format('%d/%d', [Length(Dl.DeliberateBreaks), Length(Dl.MigrateApplied)]));
  if Length(Dl.DeliberateBreaks) > 0 then
    with Dl.DeliberateBreaks[0] do
      Check('migrate.dlnone.break0', (Kind = APPLY_KIND_DELIBERATE_BREAK) and (Value = 'DL_NONE') and (OldValue = 'btnTop.Count') and (Line = 28) and (RuleLine = 4),
        Format('%s %s %d %d', [Value, OldValue, Line, RuleLine]))
  else
    Check('migrate.dlnone.break0', False, 'no item');
  Sf:= MigrateApply('apply-SelfForm-dlnone-1350.json', [afMigrateMembers]);
  Check('migrate.self.break', (Length(Sf.DeliberateBreaks) = 2) and (Sf.DeliberateBreaks[0].OldValue = 'Self.btnTop.Count'), 'G6');
  Wi:= MigrateApply('apply-WithForm-rename-1350.json', [afMigrateMembers]);
  Check('migrate.with.check', (Length(Wi.MigrateChecks) = 1) and ContainsText(Wi.MigrateChecks[0].Text, 'with ') and (Wi.MigrateChecks[0].Instance <> '')
    and (Wi.MigrateChecks[0].Line > 0), Format('%d', [Length(Wi.MigrateChecks)]));
  Leg:= MigrateApply('apply-MigForm-legacy-1350.json', [afMigrateMembers]);
  LOk:= (Length(Leg.MigrateChecks) = 5) and (Length(Leg.MigrateApplied) = 3);
  if LOk then
    for var I: Integer:= 0 to 4 do
      LOk:= LOk and (Leg.MigrateChecks[I].Instance = '') and (Leg.MigrateChecks[I].Line = 0) and (Leg.MigrateChecks[I].RuleLine = LEGACY_RULE_LINES[I])
        and (Leg.MigrateChecks[I].RuleLine <> 7);
  if LOk then
    LOk:= ContainsText(Leg.MigrateChecks[0].Text, MIGRATE_REFUSAL_UNITS) and ContainsText(Leg.MigrateChecks[1].Text, MIGRATE_REFUSAL_SCOPED)
      and ContainsText(Leg.MigrateChecks[2].Text, 'book line 5 already converts Click') and ContainsText(Leg.MigrateChecks[3].Text, MIGRATE_REFUSAL_TEMPLATE)
      and ContainsText(Leg.MigrateChecks[4].Text, MIGRATE_REFUSAL_NO_NEW);
  Check('migrate.legacy.rulelevel', LOk, Format('checks=%d applied=%d', [Length(Leg.MigrateChecks), Length(Leg.MigrateApplied)]));
  Lnk:= MigrateApply('apply-MigForm-linked-1350.json', [afMigrateMembers]);
  Check('migrate.linked.check', (Length(Lnk.MigrateChecks) = 1) and ContainsText(Lnk.MigrateChecks[0].Text, 'book line 3 already converts OnClick')
    and (Length(Lnk.MigrateApplied) = 3), Format('%d/%d', [Length(Lnk.MigrateChecks), Length(Lnk.MigrateApplied)]));
  with MigrateApply('apply-CtlForm-noinst-1350.json', [afMigrateMembers]) do
    Check('migrate.noinst.silent', (Length(MigrateApplied) + Length(DeliberateBreaks) + Length(MigrateChecks) = 0) and Ok);
  Ctl:= MigrateApply('apply-CtlForm-control-1350.json', [afMigrateMembers]);
  Check('migrate.control.none', Ctl.Ok and (Length(Ctl.MigrateApplied) + Length(Ctl.DeliberateBreaks) + Length(Ctl.MigrateChecks) = 0));
  with MigrateApply('apply-DlForm-dlnone-1350.json', []) do
    Check('migrate.gated.off', Ok and (Length(MigrateApplied) + Length(DeliberateBreaks) + Length(MigrateChecks) = 0));
  with ParseApplyJson('{"ok":true,"items":[7,{"kind":"migrate-applied","line":"x","path":5}]}', [afMigrateMembers]) do
    Check('migrate.malformed', (Length(MigrateApplied) = 1) and (MigrateApplied[0].Line = 0) and (MigrateApplied[0].Path = ''));
  var LOff: TApplyRow:= MigrateApply('apply-DlForm-dlnone-1350.json', []);
  Check('migrate.remaining.excludes', Length(Dl.Remainder) = Length(LOff.Remainder) - 2, Format('on=%d off=%d', [Length(Dl.Remainder), Length(LOff.Remainder)]));
  var LLegOff: TApplyRow:= MigrateApply('apply-MigForm-legacy-1350.json', []);
  Check('migrate.remaining.checks', Length(Leg.Remainder) = Length(LLegOff.Remainder) - 5, Format('on=%d off=%d', [Length(Leg.Remainder), Length(LLegOff.Remainder)]));
  // Positive control: a warnings[] line that is no item text stays in the remainder.
  with ParseApplyJson('{"ok":true,"warnings":["line 1: something else"],"items":[{"kind":"migrate-check","text":"other"}]}', [afMigrateMembers]) do
    Check('migrate.remaining.keeps.other', (Length(Remainder) = 1) and (Remainder[0] = 'line 1: something else'), string.Join('|', Remainder));
end;

procedure TestMigrateNotes;
var
  LRow: TApplyRow;
  LItem: TApplyItem;
  LConv: TConvertRow;
  LLines: TArray<string>;
begin
  LRow:= Default(TApplyRow);
  LItem:= Default(TApplyItem);
  LRow.MigrateApplied:= [LItem, LItem, LItem];
  LRow.DeliberateBreaks:= [LItem, LItem];
  LRow.MigrateChecks:= [LItem];
  Check('migrate.note.three', MigrateNote(LRow) = '; migrate: 3 renamed, 2 deliberate break(s), 1 to check', MigrateNote(LRow));
  LRow.DeliberateBreaks:= nil;
  LRow.MigrateChecks:= nil;
  var LA: string:= MigrateNote(LRow);
  LRow.MigrateApplied:= nil;
  LRow.DeliberateBreaks:= [LItem, LItem];
  var LB: string:= MigrateNote(LRow);
  LRow.DeliberateBreaks:= nil;
  Check('migrate.note.one', (LA = '; migrate: 3 renamed') and (LB = '; migrate: 2 deliberate break(s)') and (MigrateNote(LRow) = ''), LA + '|' + LB);
  Check('migrate.note.gated', MigrateNote(MigrateApply('apply-DlForm-dlnone-1350.json', [])) = '');

  LConv:= Default(TConvertRow);
  LConv.Status:= csConverted;
  LConv.Book:= 'dlnone.rules';
  LConv.UnitPas:= 'DlForm.pas';
  LConv.Apply:= MigrateApply('apply-MigForm-legacy-1350.json', [afMigrateMembers]);
  LConv.Apply.DeliberateBreaks:= MigrateApply('apply-DlForm-dlnone-1350.json', [afMigrateMembers]).DeliberateBreaks;
  LLines:= ApplyItemReportLines(LConv);
  var LApplied, LBreak, LCheck: Integer;
  var LAppliedNote, LBreakNote: string;
  LApplied:= 0; LBreak:= 0; LCheck:= 0;  // dl:ok multiple-statements-per-line -- three counters reset together
  for var LL: string in LLines do
  begin
    var LCols: TArray<string>:= LL.Split([#9]);
    if Length(LCols) < 8 then
      Continue;
    if LCols[2] = REPORT_STATUS_MIGRATE then
    begin
      Inc(LApplied);
      LAppliedNote:= LCols[7];
    end
    else if LCols[2] = REPORT_STATUS_BREAK then
    begin
      Inc(LBreak);
      if LBreakNote = '' then
        LBreakNote:= LCols[7];
    end
    else if LCols[2] = REPORT_STATUS_MIGRATE_CHECK then
      Inc(LCheck);
  end;
  Check('migrate.report.lines', (LApplied = 3) and (LBreak = 2) and (LCheck = 5) and (LAppliedNote = 'MigForm.pas:33 btnTop.Click -> Press (#migrate line 5)')
    and (LBreakNote = 'DlForm.pas:28 DL_NONE(btnTop.Count) (#migrate line 4)'), Format('%d/%d/%d [%s] [%s]', [LApplied, LBreak, LCheck, LAppliedNote, LBreakNote]));
  LConv.Status:= csRefused;
  LLines:= ApplyItemReportLines(LConv);
  Check('migrate.report.refused', Length(LLines) = 0, IntToStr(Length(LLines)));
  Check('migrate.booknote', (MigrateBookNote('Fix.rules', '#migrate A -> B' + sLineBreak + '#convert TA -> TB' + sLineBreak + '#migrate Click -> Press' + sLineBreak
    + '#migrate Count -> DL_NONE' + sLineBreak + '#migrate X -> Y, U' + sLineBreak) = 'Fix.rules: 2 member #migrate line(s) -- this engine does not apply them (needs migrate_members)')
    and (MigrateBookNote('Fix.rules', '#convert TA -> TB' + sLineBreak) = ''),
    MigrateBookNote('Fix.rules', '#convert TA -> TB' + sLineBreak + '#migrate Click -> Press' + sLineBreak));
end;

procedure TestMigrateWorkList;
var
  Dl: TApplyRow;
  LBreakRow, LRenRow: TPasUseRow;
  B: TRuleBook;
begin
  Dl:= MigrateApply('apply-DlForm-dlnone-1350.json', APPLY_FEATURES_ALL);
  LBreakRow:= Default(TPasUseRow);
  LRenRow:= Default(TPasUseRow);
  for var R: TPasUseRow in Dl.PasUses do
    if SameText(R.Member, 'Count') then
      LBreakRow:= R
    else if SameText(R.Member, 'Click') then
      LRenRow:= R;
  // D0 = B: engine 1.35.0 keeps status 'mapped' on a deliberate break and names it in migrate_to;
  // the editor reads it and does NOT stamp its own status (owner ruling 12a).
  Check('migrate.wl.migrate_to', (LBreakRow.Status = PAS_USE_MAPPED) and (LBreakRow.MigrateTo = 'DL_NONE'), LBreakRow.Status + '|' + LBreakRow.MigrateTo);
  Check('migrate.wl.migrate_to.rename', (LRenRow.Status = PAS_USE_MAPPED) and (LRenRow.MigrateTo = 'Press'), LRenRow.MigrateTo);
  with MigrateApply('apply-CtlForm-control-1350.json', APPLY_FEATURES_ALL) do
    Check('migrate.wl.migrate_to.none', (Length(PasUses) = 0) or (PasUses[0].MigrateTo = ''), 'positive control: no #migrate, no migrate_to');

  B:= MigBook(['#convert Vcl.X.TSrcBtn -> TDstBtn', '#link Caption <- Caption', '#migrate Click -> Press', '#convert TOther -> TDstBtn', '#migrate Count -> X']);
  try
    Check('migrate.wl.rule.none', RuleForRow(B, LBreakRow) = '', RuleForRow(B, LBreakRow));
    Check('migrate.wl.rule.pair', RuleForRow(nil, LBreakRow) = '');
    AddMigrate(B, 0, 'Count', 'DL_NONE');
    Check('migrate.wl.rule.unsaved', RuleForRow(B, LBreakRow) = '#migrate Count -> DL_NONE (line 4, unsaved)', RuleForRow(B, LBreakRow));
    Check('migrate.wl.rule.saved', RuleForRow(B, LRenRow) = '#migrate Click -> Press (line 3, saved)', RuleForRow(B, LRenRow));
  finally
    B.Free;
  end;
end;

procedure TestMigrateDecisions;
var
  B  : TRuleBook;
  Blk: TMigrateBlock;
  P  : TMigratePick;
  O  : TMigrateOutcome;
begin
  B:= MigBook(['#convert TSrcBtn -> TDstBtn', '#link Caption <- Caption']);
  try
    Blk:= FindMigrateBlock(B, 'TSrcBtn', 'TDstBtn', 'Fix.rules');
    Check('migrate.block.found', (Blk.State = mbFound) and (Blk.NodeIndex = 0) and (Blk.Reason = ''), Blk.Reason);
    Blk:= FindMigrateBlock(B, 'TSrcBtn', 'TOther', 'Fix.rules');
    Check('migrate.block.none', (Blk.State = mbNone) and StartsText('no #convert TSrcBtn -> TOther block in Fix.rules', Blk.Reason), Blk.Reason);
  finally
    B.Free;
  end;
  B:= MigBook(['#convert Vcl.X.TSrcBtn -> LibB.TDstBtn']);
  try
    Check('migrate.block.qualified', FindMigrateBlock(B, 'TSrcBtn', 'TDstBtn', 'F.rules').State = mbFound);
  finally
    B.Free;
  end;
  B:= MigBook(['#convert TSrcBtn -> TDstBtn', '#link A <- A', '#convert TSrcBtn -> TDstBtn']);
  try
    Blk:= FindMigrateBlock(B, 'TSrcBtn', 'TDstBtn', 'F.rules');
    Check('migrate.block.ambiguous', (Blk.State = mbAmbiguous) and ContainsText(Blk.Reason, 'lines 1, 3'), Blk.Reason);
  finally
    B.Free;
  end;

  P:= Default(TMigratePick);
  B:= MigBook(['#link Hint <- Tip', '#convert TSrcBtn -> TDstBtn', '#link Press <- Click', '#link Cnt <- Cnt : SomeCast', '#link Same <- Same']);
  try
    P.Old:= 'Width'; P.New:= 'W';  // dl:ok multiple-statements-per-line -- one pick
    Check('migrate.check.clean', MigrateCheck(B, 1, P) = '', MigrateCheck(B, 1, P));
    P.Old:= 'Click'; P.New:= 'Tap';  // dl:ok multiple-statements-per-line -- one pick
    Check('migrate.check.link.rename', MigrateCheck(B, 1, P) = 'book line 3 already converts Click', MigrateCheck(B, 1, P));
    P.Old:= 'Cnt';
    var LCast: string:= MigrateCheck(B, 1, P);
    P.Old:= 'Same';
    Check('migrate.check.link.cast', (LCast = 'book line 4 already converts Cnt') and (MigrateCheck(B, 1, P) = ''), LCast + '|' + MigrateCheck(B, 1, P));
    P.Old:= 'Tip';
    Check('migrate.check.link.file', MigrateCheck(B, 1, P) = 'book line 1 already converts Tip', MigrateCheck(B, 1, P));
    P.Old:= 'Width'; P.New:= 'width';  // dl:ok multiple-statements-per-line -- one pick
    Check('migrate.check.identity', MigrateCheck(B, 1, P) = '#migrate Width -> width renames nothing', MigrateCheck(B, 1, P));
    P.New:= 'Items.Count';
    Check('migrate.check.template', MigrateCheck(B, 1, P) = MIGRATE_REFUSAL_TEMPLATE, MigrateCheck(B, 1, P));
    P.New:= 'W';
    Check('migrate.check.global', MigrateCheck(B, -1, P) = MIGRATE_GLOBAL_TEXT, MigrateCheck(B, -1, P));
  finally
    B.Free;
  end;

  B:= MigBook(['#convert TSrcBtn -> TDstBtn', '#link Caption <- Caption', '#migrate Count -> X, U']);
  try
    var LSnap: string:= B.Snapshot;
    Blk:= FindMigrateBlock(B, 'TSrcBtn', 'TDstBtn', 'Fix.rules');
    P.Old:= 'Click'; P.New:= 'Press'; P.Break:= False;  // dl:ok multiple-statements-per-line -- one pick
    O:= ApplyMigratePick(B, Blk, P);
    Check('migrate.apply.append', O.Applied and not O.Replaced and (O.Before = '') and (O.After = '#migrate Click -> Press') and (O.Line = 4)
      and (B.SaveToString = '#convert TSrcBtn -> TDstBtn' + sLineBreak + '#link Caption <- Caption' + sLineBreak + '#migrate Count -> X, U' + sLineBreak
      + '#migrate Click -> Press' + sLineBreak), Format('line=%d %s', [O.Line, B.SaveToString]));
    Check('migrate.status.wrote', MigrateStatusText('C:\x\Fix.rules', Blk, O)
      = 'Wrote #migrate Click -> Press into #convert TSrcBtn -> TDstBtn (line 4 of Fix.rules) -- not saved: File > Save, then Convert again',
      MigrateStatusText('C:\x\Fix.rules', Blk, O));
    var LMark: TRuleMark:= Default(TRuleMark);
    LMark.Text:= 'm';
    B.Nodes[1].Marks:= [LMark];
    O.Node.Marks:= [LMark];
    var LCount: Integer:= B.Nodes.Count;
    P.New:= 'Tap';
    O:= ApplyMigratePick(B, Blk, P);
    Check('migrate.apply.replace', O.Applied and O.Replaced and (O.Before = '#migrate Click -> Press') and (O.After = '#migrate Click -> Tap')
      and (B.Nodes.Count = LCount), O.Before + '|' + O.After);
    Check('migrate.apply.dirty', (B.Snapshot <> LSnap) and (Length(O.Node.Marks) = 0) and (Length(B.Nodes[1].Marks) = 1));
    Check('migrate.status.changed', MigrateStatusText('Fix.rules', Blk, O)
      = 'Changed #migrate Click -> Tap (line 4 of Fix.rules) -- not saved: File > Save, then Convert again', MigrateStatusText('Fix.rules', Blk, O));
    P.Old:= 'Count'; P.New:= ''; P.Break:= True;  // dl:ok multiple-statements-per-line -- one pick
    O:= ApplyMigratePick(B, Blk, P);
    Check('migrate.apply.break', O.Applied and (O.After = '#migrate Count -> DL_NONE'), O.After);
    Check('migrate.apply.legacy.kept', (B.Nodes[2].Emit = '#migrate Count -> X, U') and (O.Node <> B.Nodes[2]) and (O.Warning = ''), O.Warning);
    P.Old:= 'Width'; P.New:= 'width'; P.Break:= False;  // dl:ok multiple-statements-per-line -- one pick
    O:= ApplyMigratePick(B, Blk, P);
    Check('migrate.status.warning', O.Applied and EndsText('; check: #migrate Width -> width renames nothing', MigrateStatusText('Fix.rules', Blk, O)),
      MigrateStatusText('Fix.rules', Blk, O));
    P.Old:= 'Foo'; P.New:= '';  // dl:ok multiple-statements-per-line -- one pick
    O:= ApplyMigratePick(B, Blk, P);
    Check('migrate.apply.refused', (not O.Applied) and (O.Reason = MIGRATE_REFUSAL_NO_NEW), O.Reason);
    Blk:= FindMigrateBlock(B, 'TSrcBtn', 'TNone', 'Fix.rules');
    P.New:= 'Bar';
    O:= ApplyMigratePick(B, Blk, P);
    Check('migrate.apply.none', (not O.Applied) and (O.Reason = Blk.Reason), O.Reason);
    Check('migrate.status.none', MigrateStatusText('Fix.rules', Blk, O) = 'Nothing written to Fix.rules: ' + Blk.Reason, MigrateStatusText('Fix.rules', Blk, O));
  finally
    B.Free;
  end;

  B:= MigBook(['#convert TSrcBtn -> TDstBtn', '#link Press <- Click', '#migrate Click -> Press', '#migrate Count -> DL_NONE',
    '#migrate TUpdateKind -> TFDUpdateRequest, FireDAC.Phys.Intf', '#migrate Count -> Num', '#migrate Hint -> Hint']);
  try
    var LRow: TArray<string>:= MembersRowText(B.Nodes[2]);
    Check('migrate.members.row', (string.Join('|', LRow) = 'Click|Press|rename|') and (MembersRowText(B.Nodes[3])[2] = 'DL_NONE')
      and (string.Join('|', MembersRowText(B.Nodes[4])) = 'TUpdateKind|TFDUpdateRequest|legacy|' + MIGRATE_REFUSAL_UNITS), string.Join('|', MembersRowText(B.Nodes[4])));
    Check('migrate.static.marks', StaticMigrateMarks(B) = 3, 'covered Click, duplicate Count, identity Hint');
    Check('migrate.static.marks.text', (Length(B.Nodes[2].Marks) = 1) and (B.Nodes[2].Marks[0].Text = 'book line 2 already converts Click') and B.Nodes[2].Marks[0].IsWarning
      and (Length(B.Nodes[3].Marks) = 0) and (Length(B.Nodes[5].Marks) = 1) and (B.Nodes[5].Marks[0].Text = 'book line 4 already converts Count'));
    Check('migrate.static.marks.once', (StaticMigrateMarks(B) = 0) and (Length(B.Nodes[2].Marks) = 1));
    Check('migrate.members.mark', EndsText('book line 2 already converts Click', MembersRowText(B.Nodes[2])[3]), MembersRowText(B.Nodes[2])[3]);
    Check('migrate.target.by.line', FindMigrateTarget(B, 4, 'Count', 'DL_NONE') = 3);
    B.Nodes.Insert(0, B.ParseLine('#depth 3'));
    Check('migrate.target.by.text.after.shift', FindMigrateTarget(B, 4, 'Count', 'DL_NONE') = 4);
    Check('migrate.target.stale', FindMigrateTarget(B, 4, 'Nope', 'X') = -1);
    Check('migrate.marker', MigrateMarkerText(B, 1) = '; 4 migrate', MigrateMarkerText(B, 1));
  finally
    B.Free;
  end;

  // D8 B: post-run rule-level migrate-check items become warning marks on the open book's lines.
  B:= MigBook(['#convert TSrcBtn -> TDstBtn', '#link Caption <- Caption', '#migrate TUpdateKind -> TFDUpdateRequest, FireDAC.Phys.Intf',
    '#migrate TSrcBtn:Click -> Press', '#migrate Click -> Press', '#migrate Click -> Tap', '#migrate Hint -> Hint', '#migrate Count -> Items.Count', '#migrate Foo -> ']);
  try
    var LChecks: TArray<TApplyItem>:= MigrateApply('apply-MigForm-legacy-1350.json', [afMigrateMembers]).MigrateChecks;
    Check('migrate.postrun.marks', (AddMigrateCheckMarks(B, LChecks) = 5) and (Length(B.Nodes[5].Marks) = 1)
      and ContainsText(B.Nodes[5].Marks[0].Text, 'book line 5 already converts Click') and (AddMigrateCheckMarks(B, LChecks) = 0));
    var LWith: TArray<TApplyItem>:= MigrateApply('apply-WithForm-rename-1350.json', [afMigrateMembers]).MigrateChecks;
    Check('migrate.postrun.site.skipped', AddMigrateCheckMarks(B, LWith) = 0, 'a per-site check is no rule-level mark');
  finally
    B.Free;
  end;
end;

procedure TestMigrateTabHandoff;
var
  LRows   : TArray<TConvertRow>;
  LRow    : TConvertRow;
  LEntries: TArray<TBookEntry>;
  LEntry  : TBookEntry;
  LNotes  : TArray<string>;
  LReader : TFunc<string, string>;
begin
  // D8 B: the rule-level checks of the converted rows of the OPEN book only.
  LRow:= Default(TConvertRow);
  LRow.Status:= csConverted;
  LRow.Book  := 'C:\b\Fix.rules';
  LRow.Apply := MigrateApply('apply-MigForm-legacy-1350.json', [afMigrateMembers]);
  LRows:= [LRow];
  LRow.Book:= 'C:\b\Other.rules';
  LRows:= LRows + [LRow];
  LRow.Book:= 'C:\b\Fix.rules';
  LRow.Status:= csFailedRestored;
  LRows:= LRows + [LRow];
  Check('migrate.handoff.checks', Length(MigrateChecksForBook(LRows, 'c:\B\fix.rules')) = 5, IntToStr(Length(MigrateChecksForBook(LRows, 'c:\B\fix.rules'))));
  Check('migrate.handoff.checks.none', Length(MigrateChecksForBook(LRows, 'C:\b\None.rules')) = 0);

  // D4: one Preflight note per CHECKED book with member lines, only without migrate_members.
  LEntry:= Default(TBookEntry);
  LEntry.Path:= 'C:\b\Fix.rules';
  LEntry.Checked:= True;
  LEntries:= [LEntry];
  LEntry.Path:= 'C:\b\Off.rules';
  LEntry.Checked:= False;
  LEntries:= LEntries + [LEntry];
  LEntry.Path:= 'C:\b\Gone.rules';
  LEntry.Checked:= True;
  LEntries:= LEntries + [LEntry];
  LReader:= function(APath: string): string
    begin
      if EndsText('Gone.rules', APath) then
        raise EInOutError.Create('gone');
      Result:= '#convert TA -> TB' + sLineBreak + '#migrate Click -> Press' + sLineBreak;
    end;
  LNotes:= MigrateBookNotes(LEntries, [], LReader);
  Check('migrate.handoff.booknotes', (Length(LNotes) = 1) and (LNotes[0] = 'Fix.rules: 1 member #migrate line(s) -- this engine does not apply them (needs migrate_members)'),
    string.Join('|', LNotes));
  Check('migrate.handoff.booknotes.gated', Length(MigrateBookNotes(LEntries, [afMigrateMembers], LReader)) = 0);
end;
procedure TestMigrateReviewMinors;
const
  LINES: array[0..4] of string = (#9'#migrate'#9'Click -> Press', '#migrate  Click  ->  Press', '#MIGRATE Click -> Press', '#migrate Click',
    '#migrate Click -> Press // why');
  CANONICAL: array[0..4] of string = ('#migrate Click -> Press', '#migrate Click -> Press', '#migrate Click -> Press', '#migrate Click -> ',
    '#migrate Click -> Press // why');
var
  B    : TRuleBook;
  LText: string;
  LOk  : Boolean;
  LRows: TArray<TConvertRow>;
  LRow : TConvertRow;
begin
  LText:= '';
  for var LLine: string in LINES do
    LText:= LText + LLine + sLineBreak;
  B:= TRuleBook.Create;
  try
    B.LoadFromString(LText);
    Check('migrate.rt.untouched', B.SaveToString = LText, B.SaveToString);
    LOk:= B.Nodes.Count = Length(LINES);
    for var N: TRuleNode in B.Nodes do
      LOk:= LOk and (N.Kind = rnkMigrate) and (N.MigOld = 'Click');
    Check('migrate.rt.kinds', LOk, Format('nodes=%d', [B.Nodes.Count]));
    Check('migrate.rt.fields', (B.Nodes[0].MigNew = 'Press') and (B.Nodes[1].MigNew = 'Press') and (B.Nodes[2].MigNew = 'Press')
      and (B.Nodes[3].MigNew = '') and (MigrateRefusal(B.Nodes[3]) = MIGRATE_REFUSAL_NO_NEW)
      // The engine strips no trailing '//' on a #migrate line: the comment is part of New, a template refusal.
      and (B.Nodes[4].MigNew = 'Press // why') and (MigrateRefusal(B.Nodes[4]) = MIGRATE_REFUSAL_TEMPLATE),
      B.Nodes[0].MigNew + '|' + B.Nodes[1].MigNew + '|' + B.Nodes[2].MigNew + '|' + B.Nodes[3].MigNew + '|' + B.Nodes[4].MigNew);
    LOk:= True;
    for var I: Integer:= 0 to B.Nodes.Count - 1 do
    begin
      B.Nodes[I].Dirty:= True;
      LOk:= LOk and (B.Nodes[I].Emit = CANONICAL[I]);
    end;
    Check('migrate.rt.dirty.canonical', LOk, B.Nodes[0].Emit + '|' + B.Nodes[3].Emit + '|' + B.Nodes[4].Emit);
  finally
    B.Free;
  end;

  // SetMigrateNew with the same New is no edit: not Dirty, marks kept.
  B:= MigBook(['#convert TA -> TB', '#migrate Click -> Press']);
  try
    var LMark: TRuleMark:= Default(TRuleMark);
    LMark.Text:= 'm';
    B.Nodes[1].Marks:= [LMark];
    SetMigrateNew(B.Nodes[1], 'Press');
    Check('migrate.setnew.same', (not B.Nodes[1].Dirty) and (Length(B.Nodes[1].Marks) = 1));
    SetMigrateNew(B.Nodes[1], 'press');
    Check('migrate.setnew.case', B.Nodes[1].Dirty and (B.Nodes[1].Emit = '#migrate Click -> press'), 'a case change is an edit');
  finally
    B.Free;
  end;

  // The open book's path is matched as a FILE, not as a string.
  LRow:= Default(TConvertRow);
  LRow.Status:= csConverted;
  LRow.Book  := 'C:\b\rules\Fix.rules';
  LRow.Apply := MigrateApply('apply-MigForm-legacy-1350.json', [afMigrateMembers]);
  LRows:= [LRow];
  Check('migrate.handoff.samefile', (Length(MigrateChecksForBook(LRows, 'c:/b/x/../RULES/fix.rules')) = 5)
    and (Length(MigrateChecksForBook(LRows, 'C:\b\Fix.rules')) = 0));

  // G8 (engine 1.35.0): a deliberate break no longer reports DL_NONE as an unresolved uses name.
  var LDl: TApplyRow:= MigrateApply('apply-DlForm-dlnone-1350.json', APPLY_FEATURES_ALL);
  LOk:= Length(LDl.DeliberateBreaks) = 2;
  for var LName: string in LDl.UsesUnresolved do
    LOk:= LOk and not ContainsText(LName, 'DL_NONE');
  for var LLine: string in LDl.Remainder do
    LOk:= LOk and not ContainsText(LLine, 'declaring "DL_NONE"');
  Check('migrate.g8.no.dlnone.noise', LOk and not ContainsText(MigrateFixture('apply-DlForm-dlnone-1350.json'), 'uses-unit-unresolved'),
    Format('breaks=%d unresolved=%s', [Length(LDl.DeliberateBreaks), string.Join(',', LDl.UsesUnresolved)]));
end;

{ #migrate follow-ups (spec section 12a): D5 = B -- 'DL_NONE for all selected rows' in the
  Migrate dialog (ApplyBreakToRows); D6 = B -- the dialog targets the book that converted the
  row, pas_uses[].rules_file (engine contract G7, in the 1.35.0-alpha capture). }

function MigRow(const AInstance, AFrom, ATo, AMember, ARulesFile: string): TPasUseRow;
begin
  Result:= Default(TPasUseRow);
  Result.Instance := AInstance;
  Result.FromType := AFrom;
  Result.ToType   := ATo;
  Result.Member   := AMember;
  Result.RulesFile:= ARulesFile;
end;

procedure TestMigrateFollowups;
const
  OPEN_BOOK  = 'C:\books\Fix.rules';
  OTHER_BOOK = 'C:\books\Other.rules';
var
  LDl    : TApplyRow;
  LOld   : TApplyRow;
  LRaw, LStripped: string;
  LT     : TMigrateBookTarget;
  LAll   : TFunc<string, Boolean>;
  LNone  : TFunc<string, Boolean>;
  B      : TRuleBook;
  LOut   : TMigrateBulkOutcome;
  LRows  : TArray<TPasUseRow>;
  LStatus: string;
begin
  // D6: the real 1.35.0-alpha capture carries rules_file on every pas_uses[] row (G7) ...
  LDl:= MigrateApply('apply-DlForm-dlnone-1350.json', APPLY_FEATURES_ALL);
  var LNamed: Boolean:= Length(LDl.PasUses) > 0;
  for var R: TPasUseRow in LDl.PasUses do
    LNamed:= LNamed and EndsText('\dlnone.rules', R.RulesFile);
  Check('migrate.d6.rules_file.parsed', LNamed, IntToStr(Length(LDl.PasUses)) + ' rows');
  // ... and an engine before it sends none: RulesFile stays '' (positive control).
  // The apply1270 fixture is re-captured per engine (make-capture.ps1) and since 1.36.0 carries rules_file too, so the pre-G7 shape
  // is made by stripping the per-row key from it; the Check on LRaw proves the strip really removed something.
  LRaw:= TFile.ReadAllText(TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), 'fixtures\apply1270\apply-pas-uses-1270.json')));
  LStripped:= ReplaceStr(LRaw, ',"rules_file":"Fix.rules"}', '}');
  Check('migrate.d6.rules_file.strip', LStripped <> LRaw);
  LOld:= ParseApplyJson(LStripped, APPLY_FEATURES_ALL);
  Check('migrate.d6.rules_file.absent', (Length(LOld.PasUses) > 0) and (LOld.PasUses[0].RulesFile = ''), IntToStr(Length(LOld.PasUses)));

  LAll:= function(APath: string): Boolean
    begin
      Result:= True;
    end;
  LNone:= function(APath: string): Boolean
    begin
      Result:= False;
    end;
  LT:= MigrateTargetForRows(OPEN_BOOK, [MigRow('btnTop', 'TSrcBtn', 'TDstBtn', 'Count', 'c:/books/FIX.rules')], LAll);
  Check('migrate.d6.target.open', (LT.Action = mbaOpenBook) and (LT.Book = OPEN_BOOK) and (LT.OfferCount = 1) and not LT.Mixed, LT.Book);
  LT:= MigrateTargetForRows(OPEN_BOOK, [MigRow('btnTop', 'TSrcBtn', 'TDstBtn', 'Count', '')], LAll);
  Check('migrate.d6.target.unnamed', (LT.Action = mbaOpenBook) and (LT.Book = OPEN_BOOK), 'an engine without rules_file keeps v1: the open book');
  LT:= MigrateTargetForRows(OPEN_BOOK, [MigRow('btnTop', 'TSrcBtn', 'TDstBtn', 'Count', OTHER_BOOK)], LAll);
  Check('migrate.d6.target.switch', (LT.Action = mbaSwitch) and (LT.Book = OTHER_BOOK) and (LT.Reason = ''), LT.Book);
  LT:= MigrateTargetForRows(OPEN_BOOK, [MigRow('btnTop', 'TSrcBtn', 'TDstBtn', 'Count', OTHER_BOOK)], nil);
  Check('migrate.d6.target.switch.nilexists', LT.Action = mbaSwitch);
  LT:= MigrateTargetForRows(OPEN_BOOK, [MigRow('btnTop', 'TSrcBtn', 'TDstBtn', 'Count', OTHER_BOOK)], LNone);
  Check('migrate.d6.target.missing', (LT.Action = mbaMissing) and (LT.Book = OPEN_BOOK) and ContainsText(LT.Reason, 'Other.rules') and ContainsText(LT.Reason, 'not on disk'), LT.Reason);
  LT:= MigrateTargetForRows('', [MigRow('btnTop', 'TSrcBtn', 'TDstBtn', 'Count', '')], LAll);
  Check('migrate.d6.target.untitled', (LT.Action = mbaOpenBook) and (LT.Book = ''), LT.Book);
  LT:= MigrateTargetForRows(OPEN_BOOK, [], LAll);
  Check('migrate.d6.target.empty', (LT.Action = mbaOpenBook) and (LT.OfferCount = 0));
  Check('migrate.d6.opened.text', MigrateOpenedText(OTHER_BOOK) = 'Opened Other.rules (it converted the row) -- ', MigrateOpenedText(OTHER_BOOK));

  // D5: the bulk choice covers the DISTINCT instance members of one book.
  LRows:= [MigRow('btnTop', 'TSrcBtn', 'TDstBtn', 'Count', OTHER_BOOK), MigRow('btnTop', 'TSrcBtn', 'TDstBtn', 'Click', OTHER_BOOK),
    MigRow('btnLow', 'TSrcBtn', 'TDstBtn', 'count', OTHER_BOOK), MigRow('', '', '', 'Beep', OTHER_BOOK)];
  LT:= MigrateTargetForRows(OPEN_BOOK, LRows, LAll);
  Check('migrate.d5.offer.distinct', (LT.Action = mbaSwitch) and (LT.OfferCount = 2) and not LT.Mixed, Format('offer=%d', [LT.OfferCount]));
  LT:= MigrateTargetForRows(OPEN_BOOK, [LRows[0], LRows[2]], LAll);
  Check('migrate.d5.offer.samemember', LT.OfferCount = 1, Format('offer=%d -- one member, one line', [LT.OfferCount]));
  LT:= MigrateTargetForRows(OPEN_BOOK, [LRows[0], MigRow('btnTop', 'TSrcBtn', 'TDstBtn', 'Click', OPEN_BOOK)], LAll);
  Check('migrate.d5.offer.mixed', LT.Mixed and (LT.OfferCount = 1) and (LT.Action = mbaSwitch) and (LT.Book = OTHER_BOOK), Format('offer=%d', [LT.OfferCount]));

  B:= MigBook(['#convert Vcl.X.TSrcBtn -> TDstBtn', '#link Caption <- Caption', '#migrate Click -> Press', '#migrate Tag -> DL_NONE', '#convert TA -> TB', '#link P <- P']);
  try
    LRows:= [MigRow('btnTop', 'TSrcBtn', 'TDstBtn', 'Count', ''), MigRow('btnTop', 'TSrcBtn', 'TDstBtn', 'Click', ''),
      MigRow('btnTop', 'TSrcBtn', 'TDstBtn', 'Tag', ''), MigRow('btnLow', 'TSrcBtn', 'TDstBtn', 'COUNT', ''),
      MigRow('edA', 'TX', 'TY', 'Foo', ''), MigRow('', '', '', 'Beep', '')];
    LOut:= ApplyBreakToRows(B, LRows, 'Fix.rules');
    Check('migrate.d5.bulk.counts', (LOut.Asked = 5) and (LOut.Written = 1) and (LOut.Changed = 1) and (LOut.Unchanged = 1) and (Length(LOut.Skipped) = 2),
      Format('asked=%d written=%d changed=%d unchanged=%d skipped=%d', [LOut.Asked, LOut.Written, LOut.Changed, LOut.Unchanged, Length(LOut.Skipped)]));
    Check('migrate.d5.bulk.lines', (B.Nodes.Count = 7) and (B.Nodes[2].Emit = '#migrate Click -> DL_NONE') and (B.Nodes[4].Emit = '#migrate Count -> DL_NONE')
      and (B.Nodes[5].Kind = rnkConvert), B.Nodes[4].Emit);
    Check('migrate.d5.bulk.untouched', (B.Nodes[3].Emit = '#migrate Tag -> DL_NONE') and not B.Nodes[3].Dirty, 'an existing DL_NONE line is not dirtied');
    Check('migrate.d5.bulk.skipped', (Length(LOut.Skipped) = 2) and StartsText('Foo: no #convert TX -> TY block in Fix.rules', LOut.Skipped[0])
      and StartsText('Beep: ', LOut.Skipped[1]), string.Join(' | ', LOut.Skipped));
    LStatus:= BulkMigrateStatusText(OPEN_BOOK, LOut);
    Check('migrate.d5.status', StartsText('DL_NONE for 5 member(s) in Fix.rules: 1 written, 1 changed, 1 already DL_NONE -- not saved: File > Save, then Convert again; skipped 2: Foo: ', LStatus), LStatus);
    // Again: everything is DL_NONE now -- nothing is dirtied and the status says nothing was written.
    for var N: TRuleNode in B.Nodes do
      N.Dirty:= False;
    LOut:= ApplyBreakToRows(B, [LRows[0], LRows[1]], 'Fix.rules');
    Check('migrate.d5.bulk.again', (LOut.Unchanged = 2) and (LOut.Written + LOut.Changed = 0) and not B.Nodes[2].Dirty and not B.Nodes[4].Dirty,
      Format('unchanged=%d', [LOut.Unchanged]));
    LStatus:= BulkMigrateStatusText(OPEN_BOOK, LOut);
    Check('migrate.d5.status.nothing', LStatus = 'Nothing written to Fix.rules: 2 already DL_NONE', LStatus);
  finally
    B.Free;
  end;
end;