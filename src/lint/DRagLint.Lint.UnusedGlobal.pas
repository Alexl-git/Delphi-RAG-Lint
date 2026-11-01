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
      the declaring file names it.
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
  (`array[0..CONST - 1]`), behind a pointer type (`^TFoo`) or in a doc comment
  (`<see cref>`). A candidate with no ref therefore gets one whole-word text
  count over its scope (the declaring file; every indexed file for an interface
  symbol); a second occurrence anywhere -- code, comment or string -- keeps it
  silent. Only ref-less suspects are tokenised, so the cost is one pass over the
  sources, paid only when a suspect exists. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

const
  /// <summary>The rule id, as `rules --json`, `--rule` and dl:ok markers spell it.</summary>
  UNUSED_GLOBAL_RULE = 'unused-global';

/// <summary>Runs the rule over a project index.</summary>
/// <param name="AStore">The project index; nil yields no findings.</param>
/// <returns>One 'unused-global' hint per unit-level const / var / type nothing
/// names: implementation-section declarations (const, var, type alias, class,
/// record, interface) when nothing in the declaring file names them; interface
/// section declarations (const, var, type alias) when nothing in any file does,
/// unless the declaring unit is `dl:shared`. Anchored at the declaration.</returns>
/// <remarks>Name-keyed and conservative: a homonym used anywhere in scope keeps
/// a symbol silent, and so does a mention in a comment or string (text
/// fallback). Not thread-safe. A symbol used only inside an inactive {$IFDEF}
/// branch is invisible to the refs but visible to the text fallback.</remarks>
function CollectUnusedGlobal(const AStore: ISymbolStore): TArray<TLintFinding>;

implementation

uses
  System.SysUtils
  , System.IOUtils
  , System.Generics.Collections
  , System.Generics.Defaults
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
  { an unreadable file counts as this many mentions of every suspect: an unopened file is not evidence of absence }
  UNREADABLE_HITS = 1000;

function CollectUnusedGlobal(const AStore: ISymbolStore): TArray<TLintFinding>;
var
  UnitIds   : TDictionary<Int64, Boolean>;
  Cands     : TList<TSymbol>;
  CandNames : TDictionary<string, Boolean>;
  KindOf    : TDictionary<Int64, string>;   { candidate id -> kind label }
  UsedFiles : TObjectDictionary<string, TDictionary<Int64, Boolean>>; { lower name -> files naming it }
  TextHits  : TObjectDictionary<string, TDictionary<Int64, Integer>>; { suspect lower name -> file id -> whole-word count }
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
      var OnDecl: Boolean:= False;
      for var C in Cands do
        if (C.FileId = R.FileId) and (C.StartLine = R.StartLine) and (C.StartCol = R.StartCol) and
          SameText(C.Name, R.NameText) then
        begin
          OnDecl:= True;
          Break;
        end;
      if not OnDecl then Files.AddOrSetValue(AFileId, True);
    end;
  end;

  function IsUsed(const ASym: TSymbol): Boolean;
  begin
    var Files: TDictionary<Int64, Boolean>;
    if not UsedFiles.TryGetValue(LowerCase(ASym.Name), Files) then Exit(False);
    Result:= if SameText(ASym.Section, SECTION_IMPL) then Files.ContainsKey(ASym.FileId) else Files.Count > 0;
  end;

  { Counts whole-word occurrences of every suspect name in one file. }
  procedure CountSuspects(AFileId: Int64);
  var
    Text: string;
  begin
    try
      Text:= TFile.ReadAllText(AStore.GetFilePath(AFileId), TEncoding.ANSI);
    except   // dl:ok try-except-swallowed@3756 -- an unreadable file must keep every suspect silent, never abort the run
      on Exception do
      begin
        for var Pair in TextHits do Pair.Value.AddOrSetValue(AFileId, UNREADABLE_HITS);
        Exit;
      end;
    end;
    var I: Integer:= 1;
    while I <= Length(Text) do
    begin
      if CharInSet(Text[I], ['A'..'Z', 'a'..'z', '_']) then
      begin
        var J: Integer:= I;
        while (J <= Length(Text)) and CharInSet(Text[J], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(J);
        var Counts: TDictionary<Int64, Integer>;
        if TextHits.TryGetValue(LowerCase(Copy(Text, I, J - I)), Counts) then
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

  procedure Report(const ASym: TSymbol);
  begin
    var Fd: TLintFinding:= Default(TLintFinding);
    Fd.RuleId    := UNUSED_GLOBAL_RULE;
    Fd.FileId    := ASym.FileId;
    Fd.FilePath  := AStore.GetFilePath(ASym.FileId);
    Fd.StartLine := ASym.StartLine;
    Fd.EndLine   := ASym.StartLine;
    Fd.StartCol  := if ASym.StartCol > 0 then ASym.StartCol else 1;
    Fd.EndCol    := Fd.StartCol + Length(ASym.Name);
    Fd.Severity  := 'hint';
    Fd.SymbolName:= ASym.Name;
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
  CandNames:= TDictionary<string, Boolean>.Create;
  UsedFiles:= TObjectDictionary<string, TDictionary<Int64, Boolean>>.Create([doOwnsValues]);
  TextHits := TObjectDictionary<string, TDictionary<Int64, Integer>>.Create([doOwnsValues]);
  Findings := TList<TLintFinding>.Create;
  try
    for var U in AStore.FindSymbolsByKind(KIND_UNIT, False, MaxInt) do UnitIds.AddOrSetValue(U.Id, True);
    for var K in BOTH_KINDS do
    begin
      AddCandidates(K, SECTION_INTF);
      AddCandidates(K, SECTION_IMPL);
    end;
    for var K in IMPL_KINDS do AddCandidates(K, SECTION_IMPL);
    if Cands.Count = 0 then Exit;
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
        for var Fi in AStore.GetAllFileIds do CountSuspects(Fi);
      for var C in Suspects do
      begin
        if NamedInText(C) then Continue;
        { an interface symbol of a shared unit may be used by a sibling project }
        if SameText(C.Section, SECTION_INTF) then
        begin
          var Path: string:= AStore.GetFilePath(C.FileId);
          if (Path <> '') and (Length(TSharedUnit.ProjectsOf(Path)) > 1) then Continue;
        end;
        Report(C);
      end;
    finally
      Suspects.Free;
    end;
    Findings.Sort(TComparer<TLintFinding>.Construct(
      function(const A, B: TLintFinding): Integer
      begin
        Result:= CompareText(A.FilePath, B.FilePath);
        if Result = 0 then Result:= A.StartLine - B.StartLine;
        if Result = 0 then Result:= A.StartCol - B.StartCol;
      end));
    Result:= Findings.ToArray;
  finally
    Findings.Free;
    TextHits.Free;
    UsedFiles.Free;
    CandNames.Free;
    KindOf.Free;
    Cands.Free;
    UnitIds.Free;
  end;
end;

end.
