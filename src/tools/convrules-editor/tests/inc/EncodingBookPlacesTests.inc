{ ConvRules.ConvertEncoding, ENC-N1 + ENC-N3: only the #convert blocks that apply to a unit count
  for its pre-run question (FromTypeApplier: the unit's .dfm headers, its .pas identifiers and its C8
  analysis), and the rule shown for a place is windowed around the offending column. }

procedure TestEncodingBookPlaces;
const
  CYR = #$0414;
  PAIR = #$D83D#$DE00;
var
  Book, Narrow, Long, Ex: string;
  Applies: TFromTypeAppliesFn;
  Reader: TDfmTextReader;
  Inherit: TUnitInheritance;
  Verdict: TInstanceVerdict;
  Places: TArray<TEncodingPlace>;
  BookFn: TBookTextFn;
  LevelFn: TUnitLevelFn;
  Applier: TUnitApplierFn;
  LFirst, LSecond: TArray<string>;
begin
  // --- AppliedRuleLines: a non-applying block's own lines are blanked, line breaks kept ---
  Book:= '#use U' + CYR + #13#10                           // 1 book scope: always counts
    + '#convert A.TX -> B.TY, B' + #13#10                  // 2 applies
    + '#link Caption <- Caption' + #13#10                  // 3
    + '#convert TZ -> TZ' + CYR + #13#10                   // 4 does not apply
    + '#link Hint' + CYR + ' <- Hint' + #13#10             // 5
    + '#default Tag = ' + CYR + #13#10                     // 6
    + '#mapping M' + CYR + ' from TZ to TQ' + #13#10       // 7 a mapping may be applied elsewhere: kept
    + '#use V' + CYR;                                      // 8 a unit directive: kept
  Applies:=
    function(const AFromType: string): Boolean
    begin
      Result:= SameText(AFromType, 'A.TX') or SameText(AFromType, 'TX');
    end;
  Narrow:= AppliedRuleLines(Book, Applies);
  Check('n1.lines.kept.count', Length(Narrow.Split([#10])) = 8, IntToStr(Length(Narrow.Split([#10]))));
  if Length(Narrow.Split([#10])) = 8 then
  begin
    Check('n1.book.scope.kept', Narrow.Split([#10])[0] = '#use U' + CYR + #13, Narrow.Split([#10])[0]);
    Check('n1.applying.block.kept', Narrow.Split([#10])[1].StartsWith('#convert A.TX'));
    Check('n1.unapplied.header.blank', Narrow.Split([#10])[3] = #13, Narrow.Split([#10])[3]);
    Check('n1.unapplied.link.blank', Narrow.Split([#10])[4] = #13, Narrow.Split([#10])[4]);
    Check('n1.unapplied.default.blank', Narrow.Split([#10])[5] = #13, Narrow.Split([#10])[5]);
    Check('n1.mapping.kept', Narrow.Split([#10])[6].StartsWith('#mapping M'), Narrow.Split([#10])[6]);
    Check('n1.unit.directive.kept', Narrow.Split([#10])[7] = '#use V' + CYR, Narrow.Split([#10])[7]);
  end;
  Check('n1.nil.applies.unchanged', AppliedRuleLines(Book, nil) = Book);

  // --- FromTypeApplier: the evidence of one unit ---
  Reader:=
    function(const APath: string; out AText: string): TDfmRead
    begin
      Result:= drRead;
      AText := '';
      if SameText(APath, 'form.pas') then
        AText:= 'type TF = class(TForm) Q1: TQ; X1: TX; end;' + #13#10 + 'R:= TRun.Create(nil); S:= TQRS(nil);'
      else if SameText(APath, 'form.dfm') then
        AText:= 'object F: TF' + #13#10 + '  object X1: TX' + #13#10 + '  end' + #13#10
          + '  inherited I1: TInh' + #13#10 + '  end' + #13#10 + 'end'
      else if SameText(APath, 'plain.pas') then
        AText:= 'procedure P; var Q: TQ; begin Q:= TQ.Create; end;'
      else if SameText(APath, 'plain.dfm') then
        Result:= drMissing
      else if SameText(APath, 'bin.pas') or SameText(APath, 'bad.pas') then
        AText:= 'unit X;'
      else if SameText(APath, 'bin.dfm') then
        AText:= BINARY_DFM_SIGNATURE + 'xyz'
      else
        Result:= drUnreadable;
    end;
  Inherit:= Default(TUnitInheritance);
  Inherit.UnitPas:= 'form.pas';
  Inherit.Known  := True;
  Verdict:= Default(TInstanceVerdict);
  Verdict.Instance.Name    := 'tblCode';
  Verdict.Instance.TypeName:= 'TCodeUse';
  Verdict.Instance.FromCode:= True;
  Verdict.State            := asUnconverted;
  Inherit.Verdicts:= [Verdict];
  Applies:= FromTypeApplier('form.pas', Reader, Inherit);
  Check('n1.applies.dfm.object', Applies('TX'));
  Check('n1.applies.qualified', Applies('Vcl.Foo.TX'));
  Check('n1.applies.dfm.inherited', Applies('tinh'));
  Check('n1.applies.pas.creator', Applies('TRun'));
  Check('n1.applies.c8.code.use', Applies('TCodeUse'));
  Check('n1.not.applies.absent', not Applies('TNone'));
  Check('n1.not.applies.word.part', not Applies('TQR'));
  Check('n1.applies.empty.from', Applies(''));
  // no .dfm (decision 2026-10-26): only the .pas and the C8 analysis say what applies
  Applies:= FromTypeApplier('plain.pas', Reader, Default(TUnitInheritance));
  Check('n1.nodfm.pas.type.applies', Applies('TQ'));
  Check('n1.nodfm.other.not', not Applies('TX'));
  // cannot tell: binary .dfm, unreadable .dfm, unreadable .pas -> every block applies
  Applies:= FromTypeApplier('bin.pas', Reader, Default(TUnitInheritance));
  Check('n1.binary.dfm.all', Applies('TNone'));
  Applies:= FromTypeApplier('bad.pas', Reader, Default(TUnitInheritance));
  Check('n1.unreadable.dfm.all', Applies('TNone'));
  Applies:= FromTypeApplier('gone.pas', Reader, Default(TUnitInheritance));
  Check('n1.unreadable.pas.all', Applies('TNone'));

  // --- EncodingPlacesFor: a lossy character in a block that does not apply is not a place ---
  BookFn:=
    function(const APath: string): string
    begin
      Result:= '#convert TX -> TY' + #13#10 + '#default Tag = a' + CYR + #13#10
        + '#convert TZ -> TW' + #13#10 + '#default Tag = b' + CYR;
    end;
  LevelFn:=
    function(const APas: string; out ALevel: TTextLevel): Boolean
    begin
      ALevel:= tlAscii7;
      Result:= True;
    end;
  Applier:=
    function(const AUnitPas: string): TFromTypeAppliesFn
    begin
      Result:= nil;
      if SameText(AUnitPas, 'x.pas') then
        Result:=
          function(const AFromType: string): Boolean
          begin
            Result:= SameText(AFromType, 'TX');
          end;
    end;
  Places:= EncodingPlacesFor(['b.rules'], ['x.pas', 'y.pas'], BookFn, LevelFn, Applier);
  Check('n1.places.narrowed', Length(PlacesOfUnit(Places, 'x.pas')) = 1, IntToStr(Length(PlacesOfUnit(Places, 'x.pas'))));
  if Length(PlacesOfUnit(Places, 'x.pas')) = 1 then
    Check('n1.places.narrowed.line', PlacesOfUnit(Places, 'x.pas')[0].Line = 2);
  Check('n1.places.nil.fn.all', Length(PlacesOfUnit(Places, 'y.pas')) = 2);
  Check('n1.places.nil.applier.all', Length(EncodingPlacesFor(['b.rules'], ['x.pas'], BookFn, LevelFn, nil)) = 2);

  // --- ENC-N3: the rule excerpt is windowed around the column ---
  Long:= '  #default Caption = ''' + StringOfChar('a', 120) + CYR + StringOfChar('b', 120) + '''';
  Ex:= RuleExcerpt(Long, Pos(CYR, Long));
  Check('n3.window.holds.char', Ex.Contains(CYR), Ex);
  Check('n3.window.cut.both', Ex.StartsWith('...') and Ex.EndsWith('...'), Ex);
  Check('n3.window.length', Length(Ex) <= PRE_RUN_RULE_CHARS + 6, IntToStr(Length(Ex)));
  Ex:= RuleExcerpt('  #use U' + CYR + StringOfChar('c', 200), 9);
  Check('n3.window.start.not.cut', Ex.StartsWith('#use U' + CYR) and Ex.EndsWith('...'), Ex);
  Ex:= RuleExcerpt('  #use U' + CYR, 9);
  Check('n3.short.line.whole', Ex = '#use U' + CYR, Ex);
  // a window edge never splits a surrogate pair
  Long:= 'x' + PAIR + StringOfChar('y', 200);
  Ex:= RuleExcerpt(Long, 3 + PRE_RUN_RULE_CHARS div 2);
  Check('n3.edge.no.lone.low', not ((Length(Ex) > 3) and (Ord(Ex[4]) >= $DC00) and (Ord(Ex[4]) <= $DFFF)), Ex);
  Places:= EncodingPlaces(['l.rules'], ['a.pas'],
    function(const APath: string): string
    begin
      Result:= '#default Caption = ''' + StringOfChar('a', 150) + CYR + '''';
    end, LevelFn);
  Check('n3.place.rule.holds.char', (Length(Places) = 1) and Places[0].Rule.Contains(CYR));

  // --- N13-1: the book is split the way the model splits it (CRLF, LF, lone CR, mixed) ---
  LFirst := [#13#10, #10, #13, #13];
  LSecond:= [#13#10, #10, #13, #10];
  for var LCase: Integer:= 0 to 3 do
  begin
    var LB1: string:= LFirst[LCase];
    var LB2: string:= LSecond[LCase];
    var LText: string:= '#use A' + LB1 + '// c' + CYR + LB2 + '#default Tag = z' + CYR + LB1 + '#use B';
    Places:= EncodingPlaces(['m.rules'], ['a.pas'],
      function(const APath: string): string
      begin
        Result:= LText;
      end, LevelFn);
    Check('n13.split.one.place.' + IntToStr(LCase), Length(Places) = 1, IntToStr(Length(Places)));
    if Length(Places) = 1 then
      Check('n13.split.line3.' + IntToStr(LCase), (Places[0].Line = 3) and (Places[0].Col = 17),
        IntToStr(Places[0].Line) + '/' + IntToStr(Places[0].Col));
  end;

  // --- rlines: RuleLinesOnly splits like the model (CRLF, LF, lone CR, mixed) ---
  for var LCase: Integer:= 0 to 3 do
  begin
    var LText: string:= '#use A' + LFirst[LCase] + '// c' + CYR + LSecond[LCase] + '#use B' + LFirst[LCase] + '#use C';
    var LOut: TArray<string>:= RuleLinesOnly(LText).Split([#10]);
    Check('rlines.count.' + IntToStr(LCase), Length(LOut) = 4, IntToStr(Length(LOut)));
    if Length(LOut) = 4 then
      Check('rlines.blanked.' + IntToStr(LCase),
        (LOut[0] = '#use A') and (LOut[1] = '') and (LOut[2] = '#use B') and (LOut[3] = '#use C'),
        string.Join('|', LOut));
  end;
end;
