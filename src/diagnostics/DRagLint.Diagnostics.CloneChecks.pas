unit DRagLint.Diagnostics.CloneChecks;

/// <summary>Type-2 (renamed-identifier tolerant) duplicate-code detection.
///  Reports maximal identical runs of normalized tokens (>= AMinTokens) shared
///  between two routines, within one file (Check) or across a project (CheckProject).</summary>
/// <remarks>Pure-AST: identifiers and literals are normalized to placeholders so
///  copy-paste-and-rename clones match; keywords/operators/punctuation are kept as
///  themselves. No statement reordering (not Type-3). Not thread-safe (uses the
///  shared parse cache). Anchors each finding at the lexicographically-later site
///  for deterministic output.</remarks>
interface

uses
  System.Generics.Collections,
  DRagLint.Core.Model;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics (DRagLint.LSP.Completion.pas)
  /// Used in units: DRagLint.LSP.Completion
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TCloneChecker = class
  public
    /// <summary>Within-file clones in AFile.</summary>
    /// <param name="AFile">Path to the .pas file to scan.</param>
    /// <param name="AMinTokens">Minimum clone length in normalized tokens.</param>
    /// <returns>One info finding per maximal clone pair, sorted by (FilePath, StartLine).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics (DRagLint.LSP.Completion.pas)
    /// Calls: DRagLint.Diagnostics.CloneChecks.RunEngine
    /// Returns: RunEngine([AFile], AMinTokens)
    /// Pure
    /// <seealso cref="DRagLint.Diagnostics.CloneChecks.RunEngine"/>
    /// <seealso cref="DRagLint.Diagnostics.CloneChecks.TCloneChecker.CheckProject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Check(const AFile: string; AMinTokens: Integer = 90): TArray<TLintFinding>;
    /// <summary>Within + cross-file clones across AFiles (used by lint-all).</summary>
    /// <param name="AFiles">All .pas files in the project scan.</param>
    /// <param name="AMinTokens">Minimum clone length in normalized tokens.</param>
    /// <returns>One info finding per maximal clone pair, sorted by (FilePath, StartLine).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)
    /// Calls: DRagLint.Diagnostics.CloneChecks.RunEngine
    /// Returns: RunEngine(AFiles, AMinTokens)
    /// Pure
    /// <seealso cref="DRagLint.Diagnostics.CloneChecks.RunEngine"/>
    /// <seealso cref="DRagLint.Diagnostics.CloneChecks.TCloneChecker.Check"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckProject(const AFiles: TArray<string>; AMinTokens: Integer = 90): TArray<TLintFinding>;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Generics.Defaults,
  TreeSitter,
  DRagLint.Diagnostics.ParseCache;

const
  { Information-density floor for a reported clone -- see IsLowInformation.
    Distinct normalized tokens must reach VOCAB_COEFF * Sqrt(Len), never below
    VOCAB_FLOOR_MIN. Tuned so the small hand-written fixture (20 tokens, 17
    distinct) stays reported while a 100-token dispatch chain (~9 distinct) does not. }
  VOCAB_COEFF     = 1.5;
  VOCAB_FLOOR_MIN = 8  ;
  { A clone at least this % covered by one repeating statement shape is a repetitive
    construct, not copy-paste. MIN_REPEATS guards against calling two occurrences of
    anything a "pattern". }
  PERIODIC_COVER_PCT = 60;
  MIN_REPEATS        = 3 ;

type
  TTok = record
    Code : Integer; { >0 interned normalized token; <0 unique per-routine barrier }
    FileI: Integer; { index into AFiles; -1 for a barrier }
    Line : Integer; { 1-based source line }
  end;

  TCloneCand = record
    A, B, Len: Integer;
  end;

{ NodeText is only exported from the parser unit's implementation section (not
  visible outside it) -- reimplement the same StartByte/EndByte/UTF8 pattern
  used locally by DRagLint.Diagnostics.DeadCodeChecks.NodeStr. }
function NodeText(const N: TTSNode; const Src: TBytes): string;
var
  S, E, L: Integer;
begin
  Result := '';
  if N.IsNull then Exit;
  S := Integer(N.StartByte); E := Integer(N.EndByte); L := E - S;
  if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
  Result := TEncoding.UTF8.GetString(Src, S, L);
end;

function IsIdentifierType(const ANodeType: string): Boolean;
begin
  { VERIFY against the grammar probe (Step 1) and adjust if needed. }
  Result := (ANodeType = 'identifier');
end;

function IsLiteralType(const ANodeType: string): Boolean;
begin
  { VERIFY against the grammar probe (Step 1) and adjust if needed. }
  Result := (ANodeType = 'literalNumber')
         or (ANodeType = 'literalString')
         or (ANodeType = 'literalChar')
         or (ANodeType = 'char')
         or (ANodeType = 'literalFloat');
end;

function RunEngine(const AFiles: TArray<string>; AMinTokens: Integer): TArray<TLintFinding>;
var
  Toks      : TList<TTok>;
  Interner  : TDictionary<string, Integer>;
  RoutineSeq: Integer;
  W         : Integer;
  Findings  : TList<TLintFinding>;
  Seen      : TDictionary<string, Boolean>;

  procedure AddToken(const N: TTSNode; const Src: TBytes; AFileI: Integer);
  var
    nt, key, txt: string;
    code        : Integer;
    t           : TTok;
  begin
    nt := N.NodeType;
    if IsIdentifierType(nt) then
      key := #1'ID'
    else if IsLiteralType(nt) then
      key := #2'LIT'
    else
    begin
      txt := Trim(NodeText(N, Src));
      if txt = '' then Exit; { whitespace-only terminal }
      key := #3 + LowerCase(txt);
    end;
    if not Interner.TryGetValue(key, code) then
    begin
      code := Interner.Count + 1;
      Interner.Add(key, code);
    end;
    t.Code := code; t.FileI := AFileI; t.Line := Integer(N.StartPoint.Row) + 1;
    Toks.Add(t);
  end;

  procedure CollectLeaves(const ARoot, N: TTSNode; const Src: TBytes; AFileI: Integer);
  var i: Integer;
  begin
    if N.IsNull then Exit;
    if N.IsExtra then Exit; { comments }
    if (not (N = ARoot)) and (N.NodeType = 'defProc') then Exit; { nested routine handled separately }
    if N.ChildCount = 0 then begin AddToken(N, Src, AFileI); Exit; end;
    for i := 0 to N.ChildCount - 1 do
      CollectLeaves(ARoot, N.Child(i), Src, AFileI);
  end;

  procedure EmitBarrier;
  var t: TTok;
  begin
    Inc(RoutineSeq);
    t.Code := -RoutineSeq; t.FileI := -1; t.Line := 0;
    Toks.Add(t);
  end;

  procedure VisitRoutines(const N: TTSNode; const Src: TBytes; AFileI: Integer);
  var i: Integer;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'defProc' then
    begin
      CollectLeaves(N, N, Src, AFileI);
      EmitBarrier;
      for i := 0 to N.ChildCount - 1 do
        VisitRoutines(N.Child(i), Src, AFileI); { nested routines }
    end
    else
      for i := 0 to N.ChildCount - 1 do
        VisitRoutines(N.Child(i), Src, AFileI);
  end;

  function TokensEqual(a, b, Len: Integer): Boolean;
  var k: Integer;
  begin
    Result := True;
    for k := 0 to Len - 1 do
      if Toks[a + k].Code <> Toks[b + k].Code then Exit(False);
  end;

  { v0.85: information-density floor -- the fix for duplicate-code's false positives.

    AddToken maps every identifier to ID and every literal to LIT, so a run of N
    structurally identical statements is token-identical to ANY other such run, in
    any unit, about anything. Three shapes produced most of this rule's findings and
    NONE of them was actionable:
      * a command-dispatch chain   `else if ID = LIT then ID := ID(ID)`
      * a record field-assign run  `ID.ID := ID.ID(LIT).ID;`
      * a parameter-setup block    `ID.ID.ID(LIT).ID := ID;`
    Two dispatchers that dispatch to different things share no extractable routine,
    so the finding could never be cleared -- the same defect class as an object-leak
    reported on a record.

    A genuine clone carries VOCABULARY as well as length. Distinct-token count grows
    roughly with the square root of length (Heaps' law), so the floor scales that way
    too. A flat distinct/length RATIO would be wrong in the other direction: it would
    suppress long genuine clones, whose vocabulary necessarily grows sub-linearly. }
  function DistinctTokenCount(AStart, ALen: Integer): Integer;
  var
    Distinct: TDictionary<Integer, Boolean>;
    k       : Integer;
  begin
    Distinct := TDictionary<Integer, Boolean>.Create;
    try
      for k := AStart to AStart + ALen - 1 do
        if not Distinct.ContainsKey(Toks[k].Code) then Distinct.Add(Toks[k].Code, True);
      Result := Distinct.Count;
    finally
      Distinct.Free;
    end;
  end;

  { Length of the longest contiguous sub-run inside the clone that is EXACTLY
    periodic with some period p and repeats at least MIN_REPEATS times -- i.e. "the
    same statement shape, over and over". This is the primary test, because the
    vocabulary floor alone cannot see repetition: a six-arm dispatch chain carries a
    routine header (`function ID(const ID: ID): ID;`) whose one-off tokens lift the
    distinct count over any floor low enough to keep small genuine clones. }
  function LongestPeriodicRun(AStart, ALen: Integer): Integer;
  var
    p, i, RunStart, Best, Cur: Integer;
  begin
    Best := 0;
    for p := 2 to ALen div MIN_REPEATS do
    begin
      RunStart := AStart;
      for i := AStart to AStart + ALen - p - 1 do
        if Toks[i].Code <> Toks[i + p].Code then RunStart := i + 1
        else
        begin
          Cur := (i - RunStart + 1) + p; { matched prefix plus the trailing period }
          if (Cur >= MIN_REPEATS * p) and (Cur > Best) then Best := Cur;
        end;
    end;
    Result := Best;
  end;

  function IsLowInformation(AStart, ALen: Integer): Boolean;
  var
    Floor: Integer;
  begin
    { (a) mostly one statement shape repeated -- a dispatch chain, a field-assignment
      run, a block of parameter setup. Nothing extractable. }
    if LongestPeriodicRun(AStart, ALen) * 100 >= ALen * PERIODIC_COVER_PCT then Exit(True);
    { (b) too little vocabulary for its length to be a meaningful clone at all. }
    Floor := Round(Sqrt(ALen) * VOCAB_COEFF);
    if Floor < VOCAB_FLOOR_MIN then Floor := VOCAB_FLOOR_MIN;
    Result := DistinctTokenCount(AStart, ALen) < Floor;
  end;

  procedure EmitPair(a, b, Len: Integer);
  var
    ta, tb, anchor, other: TTok;
    key                  : string;
    F                    : TLintFinding;
    aKeyGreater          : Boolean;
  begin
    ta := Toks[a]; tb := Toks[b];
    { anchor = lexicographically greater (FilePath, Line) for deterministic output }
    if AFiles[ta.FileI] > AFiles[tb.FileI] then
      aKeyGreater := True
    else if AFiles[ta.FileI] < AFiles[tb.FileI] then
      aKeyGreater := False
    else
      aKeyGreater := ta.Line >= tb.Line;
    if aKeyGreater then begin anchor := ta; other := tb; end
                   else begin anchor := tb; other := ta; end;

    key := AFiles[anchor.FileI] + '|' + IntToStr(anchor.Line) + '|' +
           AFiles[other.FileI] + '|' + IntToStr(other.Line);
    if Seen.ContainsKey(key) then Exit;
    Seen.Add(key, True);

    F := Default(TLintFinding);
    F.RuleId    := 'duplicate-code';
    F.Severity  := 'info';
    F.FilePath  := AFiles[anchor.FileI];
    F.StartLine := anchor.Line;
    F.StartCol  := 1;
    F.EndLine   := anchor.Line;
    F.EndCol    := 1;
    F.Message   := Format('Duplicated code block (%d tokens) -- also at %s:%d',
                          [Len, AFiles[other.FileI], other.Line]);
    Findings.Add(F);
  end;

  {$OVERFLOWCHECKS OFF} { rolling hash relies on natural UInt64 wraparound (mod 2^64) }
  procedure Match;
  var
    N, i, start, a, b, p, q, L, MaxBucket, cvA, cvB, k: Integer;
    NextBar  : TArray<Integer>;
    Base, PowW, h: UInt64;
    Buckets  : TDictionary<UInt64, TList<Integer>>;
    lst      : TList<Integer>;
    Cands    : TList<TCloneCand>;
    Covered  : TArray<Boolean>;
    cand     : TCloneCand;
  begin
    N := Toks.Count;
    if N < W then Exit;
    Base := UInt64(1000003);
    PowW := 1;
    for i := 1 to W do PowW := PowW * Base; { Base^W (natural mod 2^64) }

    { NextBar[i] = smallest k>=i with Toks[k] a barrier, else N }
    SetLength(NextBar, N + 1);
    NextBar[N] := N;
    for i := N - 1 downto 0 do
      if Toks[i].Code <= 0 then NextBar[i] := i else NextBar[i] := NextBar[i + 1];

    Buckets := TDictionary<UInt64, TList<Integer>>.Create;
    Cands   := TList<TCloneCand>.Create;
    try
      h := 0;
      for i := 0 to N - 1 do
      begin
        h := h * Base + UInt64(Cardinal(Toks[i].Code));
        if i >= W then
          h := h - UInt64(Cardinal(Toks[i - W].Code)) * PowW;
        if i >= W - 1 then
        begin
          start := i - (W - 1);
          if NextBar[start] > i then { window [start..i] barrier-free }
          begin
            if not Buckets.TryGetValue(h, lst) then
            begin lst := TList<Integer>.Create; Buckets.Add(h, lst); end;
            lst.Add(start);
          end;
        end;
      end;

      MaxBucket := 400; { perf guard; log when skipped so it is not a silent cap }
      for lst in Buckets.Values do
      begin
        if lst.Count < 2 then Continue;
        if lst.Count > MaxBucket then
        begin
          Writeln(ErrOutput, Format('duplicate-code: skipped a %d-window hash bucket (> %d cap)', [lst.Count, MaxBucket]));
          Continue;
        end;
        for p := 0 to lst.Count - 2 do
          for q := p + 1 to lst.Count - 1 do
          begin
            a := lst[p]; b := lst[q];
            if not TokensEqual(a, b, W) then Continue; { hash-collision guard }
            { left-maximal: skip if this is a right-shift of a longer aligned match }
            if (a > 0) and (b > 0)
               and (Toks[a - 1].Code > 0) and (Toks[b - 1].Code > 0)
               and (Toks[a - 1].Code = Toks[b - 1].Code) then Continue;
            { extend right within both routines }
            L := W;
            while (a + L < N) and (b + L < N)
                  and (Toks[a + L].Code > 0)
                  and (Toks[a + L].Code = Toks[b + L].Code) do
              Inc(L);
            if Abs(a - b) < L then Continue; { same-region overlap }
            cand.A := a; cand.B := b; cand.Len := L;
            Cands.Add(cand);
          end;
      end;

      { coverage suppression: emit longest clones first; skip a candidate whose BOTH
        occurrences are already >= 50% covered by previously-emitted (longer) clones.
        This collapses the sliding/self-similar overlap family to one finding per
        genuinely-duplicated region-pair. }
      Cands.Sort(TComparer<TCloneCand>.Construct(
        function(const X, Y: TCloneCand): Integer
        begin
          Result := Y.Len - X.Len;
        end));
      SetLength(Covered, N);
      for i := 0 to N - 1 do Covered[i] := False;
      for cand in Cands do
      begin
        a := cand.A; b := cand.B; L := cand.Len;
        cvA := 0; cvB := 0;
        for k := 0 to L - 1 do
        begin
          if Covered[a + k] then Inc(cvA);
          if Covered[b + k] then Inc(cvB);
        end;
        if (cvA * 2 >= L) and (cvB * 2 >= L) then Continue; { both sides already covered }
        { Deliberately does NOT mark Covered: a suppressed low-information run must
          not shadow a genuine clone that overlaps it. }
        if IsLowInformation(a, L) then Continue;
        EmitPair(a, b, L);
        for k := 0 to L - 1 do
        begin
          Covered[a + k] := True;
          Covered[b + k] := True;
        end;
      end;
    finally
      Cands.Free;
      for lst in Buckets.Values do lst.Free;
      Buckets.Free;
    end;
  end;
  {$OVERFLOWCHECKS ON}

var
  fi: Integer;
  PF: TParsedFile;
begin
  Result := nil;
  W := AMinTokens;
  if W < 1 then W := 60;
  Toks     := TList<TTok>.Create;
  Interner := TDictionary<string, Integer>.Create;
  Findings := TList<TLintFinding>.Create;
  Seen     := TDictionary<string, Boolean>.Create;
  try
    RoutineSeq := 0;
    for fi := 0 to High(AFiles) do
    begin
      PF := TAstParseCache.Get(AFiles[fi]);
      if PF.Tree = nil then Continue;
      VisitRoutines(PF.Tree.RootNode, PF.Src, fi);
    end;
    Match;
    Findings.Sort(TComparer<TLintFinding>.Construct(
      function(const L, R: TLintFinding): Integer
      begin
        Result := CompareStr(L.FilePath, R.FilePath);
        if Result = 0 then Result := L.StartLine - R.StartLine;
        if Result = 0 then Result := CompareStr(L.Message, R.Message);
      end));
    Result := Findings.ToArray;
  finally
    Seen.Free; Findings.Free; Interner.Free; Toks.Free;
  end;
end;

class function TCloneChecker.Check(const AFile: string; AMinTokens: Integer): TArray<TLintFinding>;
begin
  Result := RunEngine([AFile], AMinTokens);
end;

class function TCloneChecker.CheckProject(const AFiles: TArray<string>; AMinTokens: Integer): TArray<TLintFinding>;
begin
  Result := RunEngine(AFiles, AMinTokens);
end;

end.
