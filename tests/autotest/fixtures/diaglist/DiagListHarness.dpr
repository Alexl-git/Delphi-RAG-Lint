program DiagListHarness;

{ Console harness for DragLint.Plugin.DiagList (pure, no ToolsAPI). Prints
  key=value lines that tests\autotest\run_diaglist_harness.ps1 asserts. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DragLint.Plugin.DiagnosticCache in '..\..\..\..\src\delphi-plugin\DragLint.Plugin.DiagnosticCache.pas',
  DragLint.Plugin.DiagList in '..\..\..\..\src\delphi-plugin\DragLint.Plugin.DiagList.pas';

function D(ALine, ACol: Integer; ASev: TDragLintSeverity; const ACode, AMsg: string): TDragLintDiagnostic;
begin
  Result:= Default(TDragLintDiagnostic);
  Result.Line    := ALine;
  Result.StartCol:= ACol;
  Result.Severity:= ASev;
  Result.Code    := ACode;
  Result.Message := AMsg;
end;

function Join(const A: TArray<Integer>): string;
var
  S: TArray<string>;
  I: Integer;
begin
  SetLength(S, Length(A));
  for I:= 0 to High(A) do S[I]:= IntToStr(A[I]);
  Result:= string.Join(',', S);
end;

{ AItems[AIndex], or '<none>' when out of range -- keeps a short array from
  raising inside the harness and turns it into a readable FAIL }
function JoinS(const AItems: TArray<string>; AIndex: Integer): string;
begin
  Result:= if (AIndex >= 0) and (AIndex <= High(AItems)) then AItems[AIndex] else '<none>';
end;

const
  CAP_RENAME_ROWS   = 80;  { far more than the dialog's cap of 10, as on BASICS.PAS }
  CAP_DROPPED_ROWS  = 15;  { more than the cap of 10 too }
  CAP_DROPPED_LINE0 = 100; { the dropped rows' line numbers start below the renames' }

var
  SB   : TStringBuilder;
  Prev : TRenamePreview;
  Diags: TArray<TDragLintDiagnostic>;
  Diags2: TArray<TDragLintDiagnostic>;
  Order: TArray<Integer>;
  Lines: TArray<Integer>;
  I    : Integer;
  Txt  : string;
  Json : string;
begin
  { rule-grouped, the way the engine emits: line 0-based }
  Diags:= [D(226, 6, dlsInfo, 'public-field', 'pf A'),
           D(9, 4, dlsWarning, 'unused-unit-in-uses', 'uu ShellAPI'),
           D(226, 2, dlsInfo, 'public-field', 'pf B'),
           D(10, 4, dlsWarning, 'unused-unit-in-uses', 'uu ShlObj'),
           D(9, 4, dlsHint, 'other', 'same pos later')];
  Order:= DiagDisplayOrder(Diags);
  Writeln('order=', Join(Order));
  SetLength(Lines, Length(Order));
  for I:= 0 to High(Order) do Lines[I]:= Diags[Order[I]].Line + 1;
  Writeln('lines=', Join(Lines));
  Writeln('near.exact10=', NearestDiagRow(Lines, 10));
  Writeln('near.exact11=', NearestDiagRow(Lines, 11));
  Writeln('near.before=', NearestDiagRow(Lines, 1));
  Writeln('near.after=', NearestDiagRow(Lines, 9999));
  Writeln('near.mid=', NearestDiagRow(Lines, 100));
  Writeln('near.tie=', NearestDiagRow([10, 20], 15));
  Writeln('near.empty=', NearestDiagRow([], 5));
  Writeln('near.zero=', NearestDiagRow(Lines, 0));
  Writeln('line0=', DiagClipboardLine(Diags[1]));
  Txt:= DiagClipboardText('C:\x\BASICS.PAS', Diags, Order);
  Writeln('text.lines=', Length(Txt.Split([sLineBreak], TStringSplitOptions.ExcludeEmpty)));
  Writeln('text.first=', Txt.Split([sLineBreak])[1]);
  Writeln('text.last=', Txt.Split([sLineBreak], TStringSplitOptions.ExcludeEmpty)[5]);
  Writeln('text.crlfend=', Txt.EndsWith(sLineBreak));
  Writeln('text.sel=', DiagClipboardText('', Diags, [3]).Trim);
  Writeln('text.none=[', DiagClipboardText('C:\x', Diags, [99]), ']');
  Writeln('fix.two=', CountFixableDiags(Diags, ['Unused-Unit-In-Uses']));
  Writeln('fix.no=', CountFixableDiags(Diags, ['magic-literal']));
  Writeln('fix.empty=', CountFixableDiags([], ['public-field']));
  Writeln('sig.same=', DiagSetSignature(Diags) = DiagSetSignature(Copy(Diags)));
  Diags2:= Copy(Diags);
  Diags2[1].Message:= 'uu SysUtils';
  Writeln('sig.msg=', DiagSetSignature(Diags) <> DiagSetSignature(Diags2));
  Diags2:= Copy(Diags);
  Diags2[1].Line:= 11;
  Writeln('sig.line=', DiagSetSignature(Diags) <> DiagSetSignature(Diags2));
  Writeln('sig.emptydiff=', DiagSetSignature([]) <> DiagSetSignature(Diags));
  Writeln('af.applied=', AutofixSummary('x'#13#10'autofix: applied 2 edit(s) across 1 file(s) (.bak written)'#13#10'2 finding(s)'));
  Writeln('af.none=', AutofixSummary('autofix: no fixable findings (of 14 finding(s))'#10));
  Writeln('af.missing=[', AutofixSummary('3 finding(s)'), ']');
  Writeln('af.isapplied=', AutofixApplied('applied 2 edit(s) across 1 file(s)'));
  Writeln('af.zero=', AutofixApplied('applied 0 edit(s) across 0 file(s)'));
  Writeln('af.noneapplied=', AutofixApplied('no fixable findings (of 14 finding(s))'));
  { the exact interleaving captured in the IDE on ORM3 BASICS.PAS, 2026-10-13:
    the stdout summary split an unbuffered stderr note mid-word }
  Writeln('af.interleaved=', AutofixSummary('(loaded defaults from C:\Projects\.drag-lint.json)'#13#10 +
    'drag-lint: note: project rules ran for this file. STILL NOT reported here: doc-drift/missing-doc (pass --project-rules), cross-file duplicate-code, in' +
    'autofix: no fixable findings (of 147 finding(s))'#13#10 +
    'terface-reference-cycle, exception-class enrichment, and unit-not-in-dpr without --project.'#13#10));
  Writeln('af.optout=', AutofixOptOutRules('drag-lint: note: 2 naming rule(s) here are fixable but NOT opted in: const-casing, type-name-prefix. Naming fixes rewrite call sites project-wide, so they are opt-in'#13#10));
  Writeln('af.nooptout=[', AutofixOptOutRules('autofix: no fixable findings (of 3 finding(s))'), ']');
  Writeln('uu.name=', UnusedUnitFromMessage('Unit ''System.Win.Registry'' is listed in the uses clause but no symbols from it are referenced'));
  Writeln('uu.other=[', UnusedUnitFromMessage('Public field on a class breaks encapsulation'), ']');
  Json:= '(loaded defaults)'#13#10 +
    '{"schema":"uses-fix/1","applied":true,"items":[' +
    '{"unit":"iSetupDefaults","kind":"remove","line":48,"status":"deselected","reason":"not in --only"},' +
    '{"unit":"System.Win.Registry","kind":"remove","line":16,"status":"verified","reason":""},' +
    '{"unit":"System.IniFiles","kind":"move","line":14,"status":"verified","reason":"has an initialization section: moved, not removed"},' +
    '{"unit":"System.SysUtils","kind":"move","line":7,"status":"skipped","reason":"moving it did not verify"}]}';
  Writeln('uf.remove=', UsesFixSummary(Json, 'system.win.registry'));
  Writeln('uf.move=', UsesFixSummary(Json, 'System.IniFiles'));
  Writeln('uf.skip=', UsesFixSummary(Json, 'System.SysUtils'));
  Writeln('uf.absent=', UsesFixSummary(Json, 'Vcl.Nothing'));
  Writeln('uf.nojson=[', UsesFixSummary('ERROR: database not found', 'X'), ']');
  Writeln('uf.applied=', AutofixApplied(UsesFixSummary(Json, 'System.IniFiles')));
  Writeln('uf.notapplied=', AutofixApplied(UsesFixSummary(Json, 'System.SysUtils')));

  { multi-project rename preview (spec criteria 16-19). rp: the Task 5 brief's
    sample verbatim -- 2 rename-project lines, 4 sections in the apply counts }
  Prev:= ParseRenamePreview(
    'rename-owners: 4 of 37 indexes'#13#10 +
    'rename-project: Micronite2027 index=fresh'#13#10 +
    'rename-project: MicroniteMW1Service index=reindexed'#13#10 +
    'rename-target: L36 LotNotes_Headline -> LotNotesHeadline apply Micronite2027=0 MicroniteMW1Service=0 DMTEST=0 TEST_uSetupDefaultsFrm=0'#13#10 +
    'rename-target: L40 Foo_Bar -> FooBar dropped project MicroniteMW1Service: name FooBar already declared in uX'#13#10 +
    'rename-unknown: C:\x\X.sqlite: database disk image is malformed'#13#10 +
    'autofix: 1 fixable finding(s) -- pass --apply to write'#13#10);
  Writeln('rp.owners=', Prev.OwnerCount);
  Writeln('rp.probed=', Prev.Probed);
  Writeln('rp.projects=', Length(Prev.ProjectLines));
  Writeln('rp.project0=', JoinS(Prev.ProjectLines, 0));
  Writeln('rp.project1=', JoinS(Prev.ProjectLines, 1));
  Writeln('rp.project2=', JoinS(Prev.ProjectLines, 2));
  Writeln('rp.refused=[', Prev.Refused, ']');
  Writeln('rp.old=', Prev.OldName);
  Writeln('rp.new=', Prev.NewName);
  Writeln('rp.renames=', Length(Prev.Renames));
  Writeln('rp.dropped0=', JoinS(Prev.Dropped, 0));
  Writeln('rp.unknown0=', JoinS(Prev.Unknown, 0));
  Writeln('rp.action=', Ord(RenamePreviewAction(Prev)));
  Txt:= RenameConfirmText('BASICS.PAS', Prev.OldName, Prev.NewName, Prev);
  Writeln('rc.notindexed=', Txt.Contains('only projects with a drag-lint index were checked'));
  Writeln('rc.allnames=', Txt.Contains('Micronite2027') and Txt.Contains('MicroniteMW1Service')
    and Txt.Contains('DMTEST') and Txt.Contains('TEST_uSetupDefaultsFrm'));
  Writeln('rc.header=', Txt.Contains('LotNotes_Headline -> LotNotesHeadline') and Txt.Contains('BASICS.PAS'));
  Writeln('rc.dropped=', Txt.Contains('Foo_Bar -> FooBar'));
  Writeln('rc.unknown=', Txt.Contains('X.sqlite: database disk image is malformed'));
  Writeln('rc.counts=', Txt.Contains('4 indexed project(s)') and Txt.Contains('37 index(es) checked'));

  { rr: the engine's real refusal shape (run_multi_project_rename S4) }
  Prev:= ParseRenamePreview(
    'rename-owners: 3 of 4 indexes'#13#10 +
    'rename-project: A index=fresh'#13#10 +
    'rename-project: MicroniteMW1Service index=fresh'#13#10 +
    'rename-project: C index=fresh'#13#10 +
    'rename-target: L6 My_Const -> MyConst dropped project MicroniteMW1Service: name MyConst already declared in uB'#13#10 +
    'autofix: rename refused -- project MicroniteMW1Service: name MyConst already declared in uB'#13#10);
  Writeln('rr.refused=', Prev.Refused);
  Writeln('rr.action=', Ord(RenamePreviewAction(Prev)));

  { rs: a single-project unit prints no rename- lines (criterion 15) }
  Prev:= ParseRenamePreview('(loaded defaults from C:\Projects\.drag-lint.json)'#13#10 +
    'autofix: 1 fixable finding(s) -- pass --apply to write'#13#10);
  Writeln('rs.owners=', Prev.OwnerCount);
  Writeln('rs.projects=', Length(Prev.ProjectLines));
  Writeln('rs.action=', Ord(RenamePreviewAction(Prev)));

  { rx: the shapes the brief's sample does not show -- reason suffix, real
    counts summed over two targets, a library owner, a tag mid-line }
  Prev:= ParseRenamePreview(
    'drag-lint: note: project rules ran for this file, inrename-owners: 3 of 5 indexes'#13#10 +
    'rename-project: A index=fresh'#13#10 +
    'rename-project: B index=unverified (reindex failed: exit 2)'#13#10 +
    'rename-project: LIB index=library'#13#10 +
    'rename-target: L6 My_Const -> MyConst apply A=1 B=2'#13#10 +
    'rename-target: L7 Other_Const -> OtherConst apply A=2 B=0'#13#10);
  Writeln('rx.owners=', Prev.OwnerCount);
  Writeln('rx.probed=', Prev.Probed);
  Writeln('rx.project0=', JoinS(Prev.ProjectLines, 0));
  Writeln('rx.project1=', JoinS(Prev.ProjectLines, 1));
  Writeln('rx.project2=', JoinS(Prev.ProjectLines, 2));
  Writeln('rx.renames=', string.Join('|', Prev.Renames));
  Writeln('rx.action=', Ord(RenamePreviewAction(Prev)));
  Txt:= RenameConfirmText('uShared.pas', Prev.OldName, Prev.NewName, Prev);
  Writeln('rx.multi=', Txt.Contains('2 rename(s)') and Txt.Contains('Other_Const -> OtherConst'));

  { rm: a manifest that did not load -- 0 of 0, free-text unknown, refusal }
  Prev:= ParseRenamePreview(
    'rename-owners: 0 of 0 indexes'#13#10 +
    'rename-unknown: manifest did not load completely: C:\x\drag-lint.json: Unexpected character'#13#10 +
    'rename-target: L6 My_Const -> ? dropped ownership unknown: manifest did not load completely: C:\x\drag-lint.json: Unexpected character'#13#10 +
    'autofix: rename refused -- ownership unknown: manifest did not load completely: C:\x\drag-lint.json: Unexpected character'#13#10);
  Writeln('rm.owners=', Prev.OwnerCount);
  Writeln('rm.unknown0=', JoinS(Prev.Unknown, 0));
  Writeln('rm.action=', Ord(RenamePreviewAction(Prev)));
  { rb: the same in a batch run (Fix all): no refusal line, the target is only
    dropped -- 0 owners must still not mean "single project, apply directly" }
  Prev:= ParseRenamePreview(
    'rename-owners: 0 of 0 indexes'#13#10 +
    'rename-unknown: manifest did not load completely: C:\x\drag-lint.json: Unexpected character'#13#10 +
    'rename-target: L6 My_Const -> ? dropped ownership unknown: manifest'#13#10 +
    'autofix: no fixable findings (of 3 finding(s))'#13#10);
  Writeln('rb.action=', Ord(RenamePreviewAction(Prev)));

  { ra: an --apply run whose rename was dropped at write time: the refusal is
    the LAST autofix: line (the Diagnostics row), but other edits were written }
  Txt:= 'rename-owners: 2 of 3 indexes'#13#10 +
    'rename-dropped-at-write: My_Const -> MyConst C:\w\B\uB.pas:7 (stale)'#13#10 +
    'autofix: applied 1 edit(s) across 1 file(s) (.bak written)'#13#10 +
    'autofix: rename refused -- project B: uB.pas:7 changed since it was indexed'#13#10;
  Writeln('ra.summary=', AutofixSummary(Txt));
  Writeln('ra.summaryapplied=', AutofixApplied(AutofixSummary(Txt)));
  Writeln('ra.anyapplied=', AutofixAppliedInOutput(Txt));
  Writeln('ra.dropped0=', JoinS(ParseRenamePreview(Txt).Dropped, 0));
  Writeln('ra.noneapplied=', AutofixAppliedInOutput('autofix: applied 0 edit(s) across 0 file(s)'#13#10'autofix: rename refused -- x'));

  { cap (fix round 1, Important 2): Fix all on BASICS.PAS has ~80 renames --
    the dialog lists 10 of each list plus '... and K more'; projects stay whole }
  Txt:= 'rename-owners: 2 of 3 indexes'#13#10 + 'rename-project: A index=fresh'#13#10 + 'rename-project: B index=fresh'#13#10;
  SB:= TStringBuilder.Create(Txt);
  try
    for I:= 0 to CAP_RENAME_ROWS - 1 do SB.AppendFormat('rename-target: L%d C_%d -> C%d apply A=1 B=1'#13#10, [I + 1, I, I]);
    for I:= 0 to CAP_DROPPED_ROWS - 1 do SB.AppendFormat('rename-target: L%d D_%d -> D%d dropped project B: taken'#13#10, [I + CAP_DROPPED_LINE0, I, I]);
    Txt:= SB.ToString;
  finally
    SB.Free;
  end; // try
  Prev:= ParseRenamePreview(Txt);
  Txt:= RenameConfirmText('BASICS.PAS', Prev.OldName, Prev.NewName, Prev);
  Writeln('cap.renames=', Length(Prev.Renames));
  Writeln('cap.tenth=', Txt.Contains('C_9 -> C9'));
  Writeln('cap.eleventh=', Txt.Contains('C_10 -> C10'));
  Writeln('cap.more=', Txt.Contains('... and 70 more'));
  Writeln('cap.dropmore=', Txt.Contains('... and 5 more') and Txt.Contains('D_9 -> D9') and not Txt.Contains('D_10 -> D10'));
  Writeln('cap.projects=', Txt.Contains('A -- index fresh, 80 reference(s)') and Txt.Contains('B -- index fresh, 80 reference(s)'));

  { rl: single-project Fix all under --fix-naming prints 'rename-local: N' }
  Prev:= ParseRenamePreview('autofix: 4 fixable finding(s) -- pass --apply to write'#13#10'rename-local: 3'#13#10);
  Writeln('rl.count=', Prev.LocalRenames);
  Writeln('rl.action=', Ord(RenamePreviewAction(Prev)));
  Writeln('rl.text=', RenameLocalConfirmText('Micronite2027', Prev).Split([sLineBreak])[0]);
  Writeln('rl.zero=', Ord(RenamePreviewAction(ParseRenamePreview('rename-local: 0'#13#10'autofix: 1 fixable finding(s)'))));
  Writeln('rl.multi=', Ord(RenamePreviewAction(ParseRenamePreview('rename-owners: 2 of 3 indexes'#13#10'rename-local: 0'#13#10))));

  { st: a preview never reindexes (Ruling 12) -- a stale owner reads
    index=stale; a configured project whose DB file does not exist is
    rename-unindexed (Ruling 14). B and DMTEST appear twice (two files). }
  Txt:= 'rename-owners: 2 of 3 indexes'#13#10 +
    'rename-project: A index=fresh'#13#10 +
    'rename-project: B index=stale (2 changed file(s))'#13#10 +
    'rename-unindexed: DMTEST (C:\x\DMTEST.sqlite)'#13#10 +
    'rename-project: B index=stale (2 changed file(s))'#13#10 +
    'rename-unindexed: DMTEST (C:\x\DMTEST.sqlite)'#13#10 +
    'rename-target: L6 My_Const -> MyConst apply A=1 B=1'#13#10;
  Prev:= ParseRenamePreview(Txt);
  Writeln('st.stale=', Prev.StaleCount);
  Writeln('st.unindexed=', string.Join('|', Prev.Unindexed));
  Writeln('st.project1=', JoinS(Prev.ProjectLines, 1));
  Txt:= RenameConfirmText('uShared.pas', Prev.OldName, Prev.NewName, Prev);
  Writeln('st.staletext=', Txt.Contains('1 project index(es) are stale and will be reindexed before writing -- this can take several minutes.'));
  Writeln('st.unindexedtext=', Txt.Contains('Not checked (no index): DMTEST -- projects without a drag-lint index may still compile this unit.'));
  Writeln('st.nostale=', RenameConfirmText('u.pas', 'a', 'b', ParseRenamePreview('rename-owners: 2 of 2 indexes'#13#10 +
    'rename-project: A index=fresh'#13#10'rename-project: B index=reindexed'#13#10)).Contains('are stale'));
  Writeln('st.singleaction=', Ord(RenamePreviewAction(ParseRenamePreview('rename-unindexed: DMTEST (C:\x\DMTEST.sqlite)'#13#10 +
    'autofix: 1 fixable finding(s) -- pass --apply to write'#13#10))));

  { un: owner decision 2026-10-14 -- any rename-unindexed line means a
    confirmation, even with one indexed owner; a refusal still wins }
  Prev:= ParseRenamePreview('rename-unindexed: DMTEST (C:\x\DMTEST.sqlite)'#13#10 +
    'rename-unindexed: TOOLS (C:\x\TOOLS.sqlite)'#13#10 +
    'autofix: 1 fixable finding(s) -- pass --apply to write'#13#10);
  Txt:= RenameConfirmText('uShared.pas', Prev.OldName, Prev.NewName, Prev);
  Writeln('un.text=', Txt.Contains('Not checked (no index): DMTEST, TOOLS -- projects without a drag-lint index may still compile this unit.'));
  Writeln('un.noowners=', Txt.Contains('0 indexed project(s)') or Txt.Contains('Apply 0 rename(s)'));
  Writeln('un.plain=', Ord(RenamePreviewAction(ParseRenamePreview('autofix: 1 fixable finding(s) -- pass --apply to write'#13#10))));
  Writeln('un.refuse=', Ord(RenamePreviewAction(ParseRenamePreview('rename-unindexed: DMTEST (C:\x\DMTEST.sqlite)'#13#10 +
    'autofix: rename refused -- index for B could not be read'#13#10))));
  Writeln('un.local=', Ord(RenamePreviewAction(ParseRenamePreview('rename-unindexed: DMTEST (C:\x\DMTEST.sqlite)'#13#10 +
    'rename-local: 3'#13#10))));
  Txt:= '';
  for I:= 1 to 12 do Txt:= Txt + Format('rename-unindexed: U%d (C:\x\U%d.sqlite)'#13#10, [I, I]);
  Txt:= RenameConfirmText('u.pas', '', '', ParseRenamePreview(Txt));
  Writeln('un.cap=', Txt.Contains('U9, U10 and 2 more -- ') and not Txt.Contains('U11'));

  { tm: INBOX rename-owner-without-target-reports-fresh -- an owner whose DB
    carries another project's tag is unverified, one missing a member is
    stale; both reasons reach the dialog verbatim, and the refusal wins }
  Prev:= ParseRenamePreview('rename-owners: 3 of 4 indexes'#13#10 +
    'rename-project: A index=fresh'#13#10 +
    'rename-project: C index=unverified (index was built from project A, not C.dproj -- rebuild it: drag-lint index --project C:\w\C\C.dproj --db C:\w\C.sqlite --rebuild)'#13#10 +
    'rename-project: E index=stale (1 project member(s) not in the index: C:\w\E\uLate.pas)'#13#10 +
    'rename-target: L6 My_Const -> MyConst dropped project C: unverified -- index was built from project A, not C.dproj'#13#10 +
    'autofix: rename refused -- project C: unverified -- index was built from project A, not C.dproj'#13#10);
  Writeln('tm.project1=', JoinS(Prev.ProjectLines, 1));
  Writeln('tm.project2=', JoinS(Prev.ProjectLines, 2));
  Writeln('tm.stale=', Prev.StaleCount);
  Writeln('tm.action=', Ord(RenamePreviewAction(Prev)));
  Writeln('DONE');
end.