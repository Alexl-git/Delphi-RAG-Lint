unit DRagLint.Lint.UnusedGlobal;

{ The `unused-global` project rule (1.40 lane unusedg, owner request #5a).

  A unit-level const, var or type that nothing names. Sibling of `unused-local`
  (routine locals) and `unused-private-member` (private class members); the
  gap they leave is the unit's own globals.

  What `unused-public-symbol` already covers (measured before building): ONLY
  interface-section free routines (skFunction / skProcedure under a unit). It
  has no const / var / type case, and nothing covers the implementation
  section at all. This rule fills exactly that gap:

    * IMPLEMENTATION-section const / var / type / class / record / interface:
      unit-private, so the per-unit check is exact -- a finding when nothing in
      the declaring file names it. Since 1.51 (WID-PROJ) also an implementation-only
      free function / procedure (one the interface does not declare).
    * INTERFACE-section const / var / type (alias): a finding when nothing in
      ANY indexed file names it. Classes, records and enums declared in the
      interface are public API (RTTI, streaming, other projects) and are left
      to a human. A unit that declares `dl:shared` (compiled by sibling
      projects this index cannot see) is skipped for interface symbols.

  Matching is NAME-keyed (lowercased ref name), like unused-public-symbol's
  IsReferenced: a same-named ref anywhere in scope keeps the symbol alive, so
  every uncertainty errs toward silence. A ref at the declaration's own
  position is not a use. Adds no extracted facts.

  TEXT FALLBACK (measured on src\cli: 5 of the first 14 findings were false):
  the index records no ref for a name used only as an array bound
  (`array[0..CONST - 1]`) or behind a pointer type (`^TFoo`). A candidate with no
  ref therefore gets one whole-word text count over its scope (the declaring file;
  every indexed file for an interface symbol); a second occurrence in code, a
  compiler directive or a string keeps it silent. COMMENTS DO NOT COUNT
  (INBOX-orm3-server-153 item 2): `document --apply` writes symbol names into /// blocks
  (seealso cref, managed facts), and a name only a comment holds is not a use.
  Only ref-less suspects are tokenised, so the cost is one pass over the
  sources, paid only when a suspect exists. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Lint.SharedScope { TSharedScope -- SHARED-UNIT-SCOPE (1.41) }
  ;

const
  /// <summary>The rule id, as `rules --json`, `--rule` and dl:ok markers spell it.</summary>
  UNUSED_GLOBAL_RULE = 'unused-global';

/// <summary>Runs the rule over a project index.</summary>
/// <param name="AStore">The project index; nil yields no findings.</param>
/// <param name="AShared">SHARED-UNIT-SCOPE (1.41): judges an interface symbol of a unit other
/// projects list by all of them -- reported only when none names it, silent when one does or when a
/// listing project's index is missing or stale. nil: a unit with a `dl:shared` header naming
/// another project is skipped for interface symbols (the 1.40 behaviour).</param>
/// <returns>One 'unused-global' hint per unit-level const / var / type nothing
/// names: implementation-section declarations (const, var, type alias, class,
/// record, interface; since 1.51 also free functions / procedures the interface does not declare)
/// when nothing in the declaring file names them; interface
/// section declarations (const, var, type alias) when nothing in any file does,
/// unless another project that lists the unit names them (see AShared). Anchored at the declaration.</returns>
/// <remarks>
/// Name-keyed and conservative: a homonym used anywhere in scope keeps
/// a symbol silent, and so does a mention in a string or a compiler directive
/// (text fallback); a mention in a comment does not. Not thread-safe. A symbol used only inside an inactive {$IFDEF}
/// branch is invisible to the refs but visible to the text fallback.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Lint.ProjectRules.TProjectLintRules.Run (DRagLint.Lint.ProjectRules.pas)</para>
/// <para>Calls: CharInSet, Copy, DRagLint.Core.Interfaces.ISymbolStore.FindRefsNamingInFiles, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByKind, DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Core.Model.TLintFinding.SortByLocation, DRagLint.Lint.SharedScope.NoteUndecidedSite, DRagLint.Lint.SharedScope.TSharedScope.Judge, DRagLint.Lint.SharedUnit.TSharedUnit.ProjectsOf (+11 more)</para>
/// <para>Returns: nil; Findings.ToArray</para>
/// <para>Complexity: 15 (cyclomatic, outer body), 218 lines (full implementation)</para>
/// <para>Catches: Exception (swallowed)</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindRefsNamingInFiles"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByKind"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
/// <seealso cref="DRagLint.Core.Model.TLintFinding.SortByLocation"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CollectUnusedGlobal(const AStore: ISymbolStore; const AShared: TSharedScope = nil): TArray<TLintFinding>;

implementation

uses
  System.SysUtils
  , System.IOUtils
  , System.Generics.Collections
  , DRagLint.Lint.SharedUnit
  ;

const
  KIND_UNIT      = 'unit';
  SECTION_INTF   = 'interface';
  SECTION_IMPL   = 'implementation';
  { kinds checked in both sections }
  BOTH_KINDS: array[0..2] of string = ('const', 'var', 'type');
  { kinds checked in the implementation section only (unit-private types) }
  IMPL_KINDS: array[0..2] of string = ('class', 'record', 'interface');
  { free routines checked in the implementation section only, when the interface does not declare them (1.51 WID-PROJ) }
  ROUTINE_KINDS: array[0..1] of string = ('function', 'procedure');
  { an unreadable file counts as this many mentions of every suspect: an unopened file is not evidence of absence }
  UNREADABLE_HITS = 1000;

function CollectUnusedGlobal(const AStore: ISymbolStore; const AShared: TSharedScope): TArray<TLintFinding>;
var
  UnitIds   : TDictionary<Int64, Boolean>;
  Cands     : TList<TSymbol>;
  CandNames : TDictionary<string, Boolean>;
  KindOf    : TDictionary<Int64, string>;   { candidate id -> kind label }
  DeclAt    : TDictionary<string, Boolean>; { DeclKey of every candidate's own declaration }
  UsedFiles : TObjectDictionary<string, TDictionary<Int64, Boolean>>; { lower name -> files naming it }
  TextHits  : TObjectDictionary<string, TDictionary<Int64, Integer>>; { suspect lower name -> file id -> whole-word count }
  SiblingHits: TObjectDictionary<Pointer, TObjectDictionary<string, TDictionary<Int64, Integer>>>; { sibling store -> the same counts over its own files }
  Findings  : TList<TLintFinding>;

  procedure AddCandidates(const AKind: string; const ASection: string);
  begin
    for var S in AStore.FindSymbolsByKind(AKind, False, MaxInt) do
      if UnitIds.ContainsKey(S.ParentId) and SameText(S.Section, ASection) then
      begin
        Cands.Add(S);
        KindOf.AddOrSetValue(S.Id, AKind);
        CandNames.AddOrSetValue(LowerCase(S.Name), True);
      end;
  end;

  { Implementation-only free routines: a routine the interface also declares is
    public API (unused-public-symbol's domain); a forward declaration and its body
    are one candidate (the first seen). }
  procedure AddRoutineCandidates;
  var
    Public, Seen: TDictionary<string, Boolean>;
  begin
    Public:= TDictionary<string, Boolean>.Create;
    Seen  := TDictionary<string, Boolean>.Create;
    try
      for var K in ROUTINE_KINDS do
        for var S in AStore.FindSymbolsByKind(K, False, MaxInt) do
          if SameText(S.Section, SECTION_INTF) then Public.AddOrSetValue(IntToStr(S.FileId) + '|' + LowerCase(S.Name), True);
      for var K in ROUTINE_KINDS do
        for var S in AStore.FindSymbolsByKind(K, False, MaxInt) do
        begin
          var Key: string:= IntToStr(S.FileId) + '|' + LowerCase(S.Name);
          if (not UnitIds.ContainsKey(S.ParentId)) or (not SameText(S.Section, SECTION_IMPL)) or
             Public.ContainsKey(Key) or Seen.ContainsKey(Key) then Continue;
          Seen.Add(Key, True);
          Cands.Add(S);
          KindOf.AddOrSetValue(S.Id, K);
          CandNames.AddOrSetValue(LowerCase(S.Name), True);
        end;
    finally
      Seen.Free;
      Public.Free;
    end;
  end;

  function DeclKey(AFileId: Int64; ALine, ACol: Integer; const ALowerName: string): string;
  begin
    Result:= IntToStr(AFileId) + '|' + IntToStr(ALine) + '|' + IntToStr(ACol) + '|' + ALowerName;
  end;

  procedure ScanFile(AFileId: Int64);
  begin
    for var R in AStore.GetReferencesFromFile(AFileId) do
    begin
      var Key: string:= LowerCase(R.NameText);
      if not CandNames.ContainsKey(Key) then Continue;
      var Files: TDictionary<Int64, Boolean>;
      if not UsedFiles.TryGetValue(Key, Files) then
      begin
        Files:= TDictionary<Int64, Boolean>.Create;
        UsedFiles.Add(Key, Files);
      end;
      { a ref sitting on a candidate's own declaration is not a use }
      if not DeclAt.ContainsKey(DeclKey(R.FileId, R.StartLine, R.StartCol, Key)) then Files.AddOrSetValue(AFileId, True);
    end;
  end;

  function IsUsed(const ASym: TSymbol): Boolean;
  begin
    var Files: TDictionary<Int64, Boolean>;
    if not UsedFiles.TryGetValue(LowerCase(ASym.Name), Files) then Exit(False);
    Result:= if SameText(ASym.Section, SECTION_IMPL) then Files.ContainsKey(ASym.FileId) else Files.Count > 0;
  end;

  { AFrom sits on a comment opener (`//`, `{`, `(*`, never a directive's `$` form): the index of
    the comment's last character, else 0. }
  function CommentEnd(const AText: string; AFrom: Integer): Integer;
  begin
    Result:= 0;
    var Head: string:= Copy(AText, AFrom, Length('(*$'));
    if Head.StartsWith('//') then
    begin
      Result:= AFrom;
      while (Result < Length(AText)) and not CharInSet(AText[Result + 1], [#13, #10]) do Inc(Result);
      Exit;
    end;
    if Head.StartsWith('{$') or Head.StartsWith('(*$') then Exit;
    if Head.StartsWith('{') then Result:= Pos('}', AText, AFrom)
    else if Head.StartsWith('(*') then
    begin
      Result:= Pos('*)', AText, AFrom + Length('(*'));
      if Result > 0 then Inc(Result);
    end
    else Exit;
    if Result = 0 then Result:= Length(AText); { unterminated: the rest of the file is comment }
  end;

  { How many quotes stand in a row at AFrom. }
  function QuoteRun(const AText: string; AFrom: Integer): Integer;
  begin
    Result:= 0;
    while (AFrom + Result <= Length(AText)) and (AText[AFrom + Result] = '''') do Inc(Result);
  end;

  { AFrom sits on a quote that opens a multi-line string (Delphi 12: an odd run of three or more quotes
    ending its line): the index of the last quote of the closing run -- the same count, first on its line --
    else 0. }
  function TextBlockEnd(const AText: string; AFrom: Integer): Integer;
  const
    MIN_QUOTES = 3;
  begin
    Result:= 0;
    var Quotes: Integer:= QuoteRun(AText, AFrom);
    if (Quotes < MIN_QUOTES) or not Odd(Quotes) then Exit;
    var K: Integer:= AFrom + Quotes;
    while (K <= Length(AText)) and CharInSet(AText[K], [' ', #9]) do Inc(K);
    if (K <= Length(AText)) and not CharInSet(AText[K], [#13, #10]) then Exit;
    while K <= Length(AText) do
    begin
      while (K <= Length(AText)) and CharInSet(AText[K], [' ', #9, #13, #10]) do Inc(K);
      if QuoteRun(AText, K) = Quotes then Exit(K + Quotes - 1);
      while (K <= Length(AText)) and not CharInSet(AText[K], [#13, #10]) do Inc(K);
    end;
  end;

  { AFrom sits on a quote: the index of the closing quote, else AFrom (no quote left on the line). }
  function StringEnd(const AText: string; AFrom: Integer): Integer;
  begin
    Result:= TextBlockEnd(AText, AFrom);
    if Result > 0 then Exit;
    Result:= AFrom;
    var K: Integer:= AFrom + 1;
    while (K <= Length(AText)) and not CharInSet(AText[K], [#13, #10]) do
    begin
      if AText[K] = '''' then Exit(K);
      Inc(K);
    end;
  end;

  { Counts whole-word occurrences of every suspect name in one file, comments excluded: AHits[name][AFileId]. }
  procedure CountSuspects(const APath: string; AFileId: Int64; AHits: TObjectDictionary<string, TDictionary<Int64, Integer>>);
  var
    Text: string;
  begin
    try
      Text:= TFile.ReadAllText(APath, TEncoding.ANSI);
    except   // dl:ok try-except-swallowed@d905 -- REVIEWED 2026-11-24 INT-W2: an unreadable file must keep every suspect silent, never abort the run
      on Exception do
      begin
        for var Pair in AHits do Pair.Value.AddOrSetValue(AFileId, UNREADABLE_HITS);
        Exit;
      end;
    end;
    var I: Integer:= 1;
    var InString: Integer:= 0; { last index of the string literal I is in }
    while I <= Length(Text) do
    begin
      if (I > InString) and (Text[I] = '''') then InString:= StringEnd(Text, I);
      var Skip: Integer:= if I > InString then CommentEnd(Text, I) else 0;
      if Skip > 0 then I:= Skip + 1
      else if CharInSet(Text[I], ['A'..'Z', 'a'..'z', '_']) then
      begin
        var J: Integer:= I;
        while (J <= Length(Text)) and CharInSet(Text[J], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(J);
        var Counts: TDictionary<Int64, Integer>;
        if AHits.TryGetValue(LowerCase(Copy(Text, I, J - I)), Counts) then
        begin
          var N: Integer:= 0;
          Counts.TryGetValue(AFileId, N);
          Counts.AddOrSetValue(AFileId, N + 1);
        end;
        I:= J;
      end
      else Inc(I);
    end;
  end;

  { True when the text count finds the name a second time (the first is the declaration) in the symbol's scope. }
  function NamedInText(const ASym: TSymbol): Boolean;
  begin
    var Counts: TDictionary<Int64, Integer>;
    if not TextHits.TryGetValue(LowerCase(ASym.Name), Counts) then Exit(False);
    var Total: Integer:= 0;
    if SameText(ASym.Section, SECTION_IMPL) then
    begin
      Counts.TryGetValue(ASym.FileId, Total);
      Exit(Total > 1);
    end;
    for var N in Counts.Values do Inc(Total, N);
    Result:= Total > 1;
  end;

  { The same text fallback over a sibling project: True when a file only ASibling holds names ALow (the
    files both projects hold were counted with the own ones). One pass per sibling, over every suspect. }
  function NamedInSibling(const ASibling: ISymbolStore; const ALow: string): Boolean;
  begin
    var Hits: TObjectDictionary<string, TDictionary<Int64, Integer>>;
    if not SiblingHits.TryGetValue(Pointer(ASibling), Hits) then
    begin
      Hits:= TObjectDictionary<string, TDictionary<Int64, Integer>>.Create([doOwnsValues]);
      SiblingHits.Add(Pointer(ASibling), Hits);
      for var Name: string in TextHits.Keys do Hits.Add(Name, TDictionary<Int64, Integer>.Create);
      for var Fi: Int64 in ASibling.GetAllFileIds do
        if AStore.FindFileIdByPath(ASibling.GetFilePath(Fi)) <= 0 then CountSuspects(ASibling.GetFilePath(Fi), Fi, Hits);
    end;
    var Counts: TDictionary<Int64, Integer>;
    Result:= Hits.TryGetValue(ALow, Counts) and (Counts.Count > 0);
  end;

  function NamedInAnySibling(const ASiblings: TArray<ISymbolStore>; const ALow: string): Boolean;
  begin
    Result:= False;
    for var S: ISymbolStore in ASiblings do
      if NamedInSibling(S, ALow) then Exit(True);
  end;

  procedure Report(const ASym: TSymbol);
  begin
    var Fd: TLintFinding:= TLintFinding.AtSymbol(UNUSED_GLOBAL_RULE, AStore.GetFilePath(ASym.FileId), ASym, 'hint');
    Fd.Message   := Format(
      'Unit-level %s %s (%s section) is never named %s -- remove it, or name it where it is meant.',
      [KindOf[ASym.Id], ASym.Name, ASym.Section,
       if SameText(ASym.Section, SECTION_IMPL) then 'in this unit' else 'in the project']);
    Findings.Add(Fd);
  end;

begin
  Result:= nil;
  if AStore = nil then Exit;
  UnitIds  := TDictionary<Int64, Boolean>.Create;
  Cands    := TList<TSymbol>.Create;
  KindOf   := TDictionary<Int64, string>.Create;
  DeclAt   := TDictionary<string, Boolean>.Create;
  CandNames:= TDictionary<string, Boolean>.Create;
  UsedFiles:= TObjectDictionary<string, TDictionary<Int64, Boolean>>.Create([doOwnsValues]);
  TextHits := TObjectDictionary<string, TDictionary<Int64, Integer>>.Create([doOwnsValues]);
  SiblingHits:= TObjectDictionary<Pointer, TObjectDictionary<string, TDictionary<Int64, Integer>>>.Create([doOwnsValues]);
  Findings := TList<TLintFinding>.Create;
  try
    for var U in AStore.FindSymbolsByKind(KIND_UNIT, False, MaxInt) do UnitIds.AddOrSetValue(U.Id, True);
    for var K in BOTH_KINDS do
    begin
      AddCandidates(K, SECTION_INTF);
      AddCandidates(K, SECTION_IMPL);
    end;
    for var K in IMPL_KINDS do AddCandidates(K, SECTION_IMPL);
    AddRoutineCandidates;
    if Cands.Count = 0 then Exit;
    for var C in Cands do DeclAt.AddOrSetValue(DeclKey(C.FileId, C.StartLine, C.StartCol, LowerCase(C.Name)), True);
    for var Fi in AStore.GetAllFileIds do ScanFile(Fi);

    var Suspects: TList<TSymbol>:= TList<TSymbol>.Create;
    try
      for var C in Cands do
        if not IsUsed(C) then
        begin
          Suspects.Add(C);
          if not TextHits.ContainsKey(LowerCase(C.Name)) then
            TextHits.Add(LowerCase(C.Name), TDictionary<Int64, Integer>.Create);
        end;
      if Suspects.Count > 0 then
        for var Fi in AStore.GetAllFileIds do CountSuspects(AStore.GetFilePath(Fi), Fi, TextHits);
      for var C in Suspects do
      begin
        if NamedInText(C) then Continue;
        { an interface symbol of a shared unit may be used by a sibling project }
        if SameText(C.Section, SECTION_INTF) then
        begin
          var Path: string:= AStore.GetFilePath(C.FileId);
          if AShared = nil then
          begin
            if (Path <> '') and (Length(TSharedUnit.ProjectsOf(Path)) > 1) then Continue;
          end
          else
          begin
            var Low: string:= LowerCase(C.Name);
            var DeclLine: Integer:= C.StartLine;
            var Projs: string;
            var Siblings: TArray<ISymbolStore>:= []; { asked, and showing no ref }
            var Verdict: TSharedVerdict:= AShared.Judge(Path,
              function(const S: ISymbolStore): Boolean
              begin
                Result:= False;
                for var R in S.FindRefsNamingInFiles(S.GetAllFileIds, [Low]) do
                  if not (SameText(S.GetFilePath(R.FileId), Path) and (R.StartLine = DeclLine)) then Exit(True);
                Siblings:= Siblings + [S];
              end, Projs);
            if (Verdict = svUnusedEverywhere) and NamedInAnySibling(Siblings, Low) then Continue;
            if Verdict = svUndecided then NoteUndecidedSite(Path, DeclLine, UNUSED_GLOBAL_RULE);
            if Verdict in [svUsedElsewhere, svUndecided] then Continue;
          end;
        end;
        Report(C);
      end;
    finally
      Suspects.Free;
    end;
    TLintFinding.SortByLocation(Findings);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
    SiblingHits.Free;
    TextHits.Free;
    UsedFiles.Free;
    CandNames.Free;
    DeclAt.Free;
    KindOf.Free;
    Cands.Free;
    UnitIds.Free;
  end;
end;

end.
