{ ConvRules.ConvertEncoding: the pre-run encoding question (owner ruling 2026-10-26). A book whose
  rule text holds a character the target .pas cannot hold at its own level is asked about BEFORE
  the run, every place listed. The lossy character is Cyrillic (U+0414): cp1252 cannot hold it. }

procedure TestEncodingPreRun;
const
  CYR = #$0414;
var
  Places, Own: TArray<TEncodingPlace>;
  Plan: TPreRunPlan;
  Q: string;
  Asked: Integer;
  BookFn: TBookTextFn;
  LevelFn: TUnitLevelFn;
begin
  BookFn:=
    function(const APath: string): string
    begin
      if SameText(APath, 'cyr.rules') then
        Result:= '// a comment with ' + CYR + ' is never written' + #13#10
          + '#convert A.TX -> B.TY, B' + #13#10
          + '#set Caption = ''x' + CYR + 'y''' + #13#10
          + '#set Hint = ''' + CYR + ''''
      else if SameText(APath, 'lone.rules') then
        Result:= '#set Caption = ''a' + #$D83D + 'b'''
      else
        Result:= '#convert A.TX -> B.TY, B';
    end;
  LevelFn:=
    function(const APas: string; out ALevel: TTextLevel): Boolean
    begin
      Result:= not SameText(APas, 'missing.pas');
      if SameText(APas, 'utf8.pas') then
        ALevel:= tlUtf8Bom
      else
        ALevel:= tlAscii7;
    end;

  // --- comment lines are blanked, line numbers kept ---
  Check('prerun.rule.lines.only', RuleLinesOnly('// x' + CYR + #13#10 + '#use A') = #13#10 + '#use A',
    RuleLinesOnly('// x' + CYR + #13#10 + '#use A'));

  // --- every place (not one per character): book, line:col, code, the rule line, the unit ---
  Places:= EncodingPlaces(['plain.rules', 'cyr.rules'], ['a.pas', 'utf8.pas', 'missing.pas'], BookFn, LevelFn);
  Check('prerun.places.each', Length(Places) = 2, IntToStr(Length(Places)));
  if Length(Places) = 2 then
  begin
    Check('prerun.place.where', (Places[0].Book = 'cyr.rules') and (Places[0].Line = 3) and (Places[0].Col = 18)
      and (Places[0].Code = $0414) and (Places[0].UnitPas = 'a.pas') and (Places[0].UnitLevel = tlAscii7)
      and (Places[0].Needs = tlUtf8), Format('%s %d:%d', [Places[0].Book, Places[0].Line, Places[0].Col]));
    Check('prerun.place.rule', Places[0].Rule = '#set Caption = ''x' + CYR + 'y''', Places[0].Rule);
    Check('prerun.place.second', (Places[1].Line = 4) and (Places[1].Col = 14), Format('%d:%d', [Places[1].Line, Places[1].Col]));
  end;
  // a UTF-8 .pas holds it; a missing .pas is not asked about; a plain book has no place
  Check('prerun.utf8.unit.no.place', Length(PlacesOfUnit(Places, 'utf8.pas')) = 0);
  Check('prerun.missing.unit.no.place', Length(PlacesOfUnit(Places, 'missing.pas')) = 0);
  Check('prerun.plain.none', Length(EncodingPlaces(['plain.rules'], ['a.pas'], BookFn, LevelFn)) = 0);

  // --- the question names book, line:col, U+XXXX, the rule, the unit, and the three choices ---
  Own:= PlacesOfUnit(Places, 'a.pas');
  Q:= PreRunQuestion('a.pas', Own, CanRaisePlaces(Own, True));
  Check('prerun.question.where', Q.Contains('cyr.rules 3:18') and Q.Contains('cyr.rules 4:14') and Q.Contains('U+0414')
    and Q.Contains('#set Caption') and Q.Contains('a.pas') and Q.Contains('ASCII-7'), Q);
  Check('prerun.question.choices', Q.Contains('Yes = raise') and Q.Contains('No = do not convert') and Q.Contains('Cancel'), Q);

  // --- a lone surrogate fits only UTF-16: the engine raises a source to UTF-8 only -> no Yes, and it says so ---
  Places:= EncodingPlaces(['lone.rules'], ['utf8.pas'], BookFn, LevelFn);
  Check('prerun.lone.surrogate.utf8.unit', (Length(Places) = 1) and (Places[0].Needs = tlUtf16Bom) and (Places[0].Code = $D83D));
  Check('prerun.lone.surrogate.cannot.raise', not CanRaisePlaces(Places, True));
  Q:= PreRunQuestion('utf8.pas', Places, False);
  Check('prerun.lone.surrogate.says.so', Q.Contains('lone surrogate') and Q.Contains('UTF-16') and not Q.Contains('Yes = raise'), Q);
  Check('prerun.no.guard.cannot.raise', not CanRaisePlaces(Own, False));

  // --- the plan: Yes raises that unit's .pas; No stops (change the rules); Cancel stops; no place = no question ---
  Places:= EncodingPlaces(['cyr.rules'], ['a.pas', 'b.pas'], BookFn, LevelFn);
  Asked:= 0;
  Plan:= PreRunPlan(Places, True,
    function(const AUnitPas, AQuestion: string; ACanRaise: Boolean): Integer
    begin
      Inc(Asked);
      Result:= mrYes;
    end);
  Check('prerun.plan.yes.keeps.every.place', Length(Plan.Notes) = Length(Places), IntToStr(Length(Plan.Notes)));
  Check('prerun.plan.yes.note.text', (Length(Plan.Notes) > 0) and PlaceNoteText(Plan.Notes[0]).StartsWith('encoding: cyr.rules ')
    and PlaceNoteText(Plan.Notes[0]).Contains('U+0414') and PlaceNoteText(Plan.Notes[0]).Contains('a.pas'));
  Check('prerun.plan.yes.raises', (Asked = 2) and not Plan.Stop and (Length(Plan.RaiseFiles) = 2)
    and (Plan.RaiseFiles[0] = 'a.pas') and (Plan.RaiseFiles[1] = 'b.pas'), IntToStr(Asked));
  Asked:= 0;
  Plan:= PreRunPlan(Places, True,
    function(const AUnitPas, AQuestion: string; ACanRaise: Boolean): Integer
    begin
      Inc(Asked);
      Result:= mrNo;
    end);
  Check('prerun.plan.no.stops.change.rules', (Asked = 1) and Plan.Stop and Plan.ChangeRules and (Length(Plan.RaiseFiles) = 0)
    and (Length(Plan.Places) = 2));
  Check('prerun.plan.no.keeps.stopping.places', Length(Plan.Notes) = 2);
  Plan:= PreRunPlan(Places, True,
    function(const AUnitPas, AQuestion: string; ACanRaise: Boolean): Integer
    begin
      Result:= mrCancel;
    end);
  Check('prerun.plan.cancel', Plan.Stop and not Plan.ChangeRules and (Length(Plan.RaiseFiles) = 0));
  Check('prerun.plan.cancel.adds.no.notes', Length(Plan.Notes) = 0);
  // Yes on the first unit, Cancel on the second: nothing is kept
  Asked:= 0;
  Plan:= PreRunPlan(Places, True,
    function(const AUnitPas, AQuestion: string; ACanRaise: Boolean): Integer
    begin
      Inc(Asked);
      Result:= if Asked = 1 then mrYes else mrCancel;
    end);
  Check('prerun.plan.yes.then.cancel.adds.no.notes', Plan.Stop and (Length(Plan.Notes) = 0) and (Length(Plan.RaiseFiles) = 1));
  // a Yes where raising is not possible counts as No
  Plan:= PreRunPlan(Places, False,
    function(const AUnitPas, AQuestion: string; ACanRaise: Boolean): Integer
    begin
      Result:= if ACanRaise then mrCancel else mrYes;
    end);
  Check('prerun.plan.yes.without.raise.is.no', Plan.Stop and Plan.ChangeRules and (Length(Plan.RaiseFiles) = 0));
  Asked:= 0;
  Plan:= PreRunPlan(nil, True,
    function(const AUnitPas, AQuestion: string; ACanRaise: Boolean): Integer
    begin
      Inc(Asked);
      Result:= mrCancel;
    end);
  Check('prerun.plan.nothing.no.question', (Asked = 0) and not Plan.Stop and (Length(Plan.RaiseFiles) = 0));

  // --- a raise run still asks after the run (its .dfm may be refused); only a re-run never asks ---
  var LJob: TConvertJob:= Default(TConvertJob);
  LJob.ApplyFeatures:= [afEncodingGuard];
  LJob.RaiseFiles   := ['a.pas'];
  Check('prerun.raise.run.still.asks.after', ShouldAskRaise(LJob, False));
  Check('prerun.rerun.never.asks', not ShouldAskRaise(RerunJob(LJob, ['a.pas'], ['a.pas']), False));
  Check('prerun.raised.status', RerunStatusText(LJob) = 'Raised 1 file(s) to UTF-8 with BOM (asked before the run): a.pas', RerunStatusText(LJob));
  Check('prerun.rerun.status.kept', RerunStatusText(RerunJob(LJob, ['a.pas'], ['a.pas'])).StartsWith('Re-run after raising 1 file(s)'));
end;
