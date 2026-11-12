unit DRagLint.Refactor.LazyInit;

// ---------------------------------------------------------------------------
// `lazy-init` (E-REFACTOR-6, first phase): names what a unit's initialization section does and, with --apply, moves its
// body VERBATIM into a run-once routine the section calls. Order and effects stay as they were; nothing starts later yet.
// Spec: docs\superpowers\specs\2026-11-06-extract-interface-lazy-init.md
// ---------------------------------------------------------------------------

interface

uses
  System.SysUtils, DRagLint.Core.Interfaces;

type
  /// <summary>The flags of one `lazy-init` run.</summary>
  TLazyInitOptions = record
    /// <summary>--unit: the unit's name; '' with All.</summary>
    UnitName: string;
    /// <summary>--all: every section the heavy-initialization rule reports; plan only.</summary>
    All: Boolean;
    /// <summary>--name: the routine's name; '' = Ensure + the unit's name without dots + Initialized.</summary>
    RoutineName: string;
    /// <summary>--project: required with --apply; bounds the edit to the project's own roots.</summary>
    Project: string;
    /// <summary>--platform, '' = win64.</summary>
    Platform: string;
    /// <summary>--rsvars, '' = the Studio the registry / BDS names.</summary>
    RsVars: string;
    /// <summary>--build-timeout in whole seconds, as typed; '' or '0' = no limit.</summary>
    BuildTimeout: string;
    /// <summary>--apply: write through the scratch build and the compile gate; otherwise the plan is printed.</summary>
    Apply: Boolean;
    /// <summary>--no-backup (apply only).</summary>
    NoBackup: Boolean;
    /// <summary>--no-compile: legal on the plan only; refused with --apply.</summary>
    NoCompile: Boolean;
    /// <summary>--format json.</summary>
    Json: Boolean;
    /// <summary>--defer (phase 2, opt-in, one --unit): the section no longer calls the run-once routine; every routine of
    /// the unit that touches a global the section writes calls it first, so the work runs on first use, once.</summary>
    Defer: Boolean;
  end;

/// <summary>Runs the verb: prints the plan and, with --apply, writes through ApplyThroughScratch.</summary>
/// <param name="pStore">The project's index; must be a SQLite store.</param>
/// <param name="pOpts">The flags.</param>
/// <returns>0: plan (a refusal included, named in it), or applied and built. 1: --apply refused or a gate refused, the project is
/// unchanged. 2: bad flags, no such unit, or a rollback that failed.</returns>
/// <remarks>Refusals, in this order: include-file, stale-file, outside-roots, no-section, ifdef-around-section, empty-section,
/// include-in-section, unbalanced-ifdef, name-taken. The plan's lazy_candidate is true for a global the section writes that is
/// declared in the implementation section and read by no other unit: a later phase could rewrite it inside one file.
/// The run-once guard is a plain Boolean: the section, on one thread, is the routine's only caller in this phase.
/// <para>With Defer (phase 2) these refusals follow name-taken: no-lazy-global (the section writes no global, so nothing
/// marks a first use), global-read-elsewhere (a global it writes is not a lazy_candidate: another unit could read it before
/// any routine here runs), reader-outside-routine / asm-reader (a use the call cannot be put in front of), parse-failed, and
/// no-entry-point (nothing outside the section touches what it writes: the work would never run). Accepted, the routine gets a
/// forward declaration after the implementation uses clause, each entry point calls it as its first statement, the section
/// keeps no call, and finalization runs its body only when the work ran. Not thread-safe: the guard stays a plain Boolean set
/// before the work (a re-entrant call returns at once); a unit first used from two threads at once must call the routine from
/// the application's start instead. Effects other units rely on without touching the globals (a registration, a print) move
/// with the work: the plan lists every statement so the reader can see them.</para></remarks>
function RunLazyInit(const pStore: ISymbolStore; const pOpts: TLazyInitOptions): Integer;

implementation

uses
  System.Classes, System.IOUtils, System.JSON, System.StrUtils, System.RegularExpressions,
  System.Generics.Collections, System.Generics.Defaults, System.Math, Winapi.Windows,
  FireDAC.Comp.Client,
  DRagLint.Core.Model, DRagLint.Project.OwnRoots, DRagLint.Report.CyclePlan, DRagLint.Refactor.CompileGate,
  DRagLint.Refactor.VerbShape, DRagLint.Refactor.RedundantCast, DRagLint.Storage.SQLite, DRagLint.Lint.InitSections,
  TreeSitter, DRagLint.Diagnostics.ParseCache;

const
  CExitOk      = 0;
  CExitRefused = 1;
  CExitError   = 2;
  CVerb        = 'lazy-init';
  CSchema      = 'lazy-init/1';

type
  TSectionStatement = record
    Line: Integer;
    Text: string;
    Heavy: Boolean;
  end;

  TSectionGlobal = record
    Name, Section: string;
    ReadersInUnit, ReadersElsewhere: Integer;
    LazyCandidate: Boolean;
  end;

  // --defer: a routine that gets the call, and where.
  TEntryPoint = record
    Name: string;
    Line: Integer;
    InsertAt: Integer;      // 1-based offset just past the body's `begin`
    Indent: string;
  end;

  TSectionPlan = record
    UnitName, FilePath, RoutineName, RefusalKind, RefusalReason, Evidence: string;
    Line: Integer;
    Heavy: Boolean;
    Deferred: Boolean;
    Statements: TArray<TSectionStatement>;
    Globals: TArray<TSectionGlobal>;
    EntryPoints: TArray<TEntryPoint>;
    Inserted: string;       // the routine, as inserted
    NewText: string;        // the whole file after the edit; '' on a refusal
    Enc: TEncoding;
  end;

function FindUnit(pConn: TFDConnection; const pName: string; out pPath: string; out pUnit: string): Boolean;
begin
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= pConn;
    Q.SQL.Text:= 'SELECT f.path, s.name FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.kind = ''unit'' AND s.name = :n COLLATE NOCASE';
    Q.ParamByName('n').AsWideString:= pName;
    Q.Open;
    Result:= not Q.Eof;
    pPath:= if Result then Q.Fields[0].AsString else '';
    pUnit:= if Result then Q.Fields[1].AsString else '';
  finally
    Q.Free;
  end;
end;

// The top-level statements in [pFrom, pTo): a `;` outside begin/try/case ... end ends one.
function SplitStatements(pSource: TMaskedSource; pFrom, pTo: Integer; const pHeavyLines: TDictionary<Integer, Boolean>): TArray<TSectionStatement>;
begin
  var Found: TArray<TSectionStatement>:= nil;
  var Depth:= 0;
  var Start:= pFrom;
  var Close_:= procedure(pEnd: Integer)
    begin
      var Raw:= Copy(pSource.Masked, Start, pEnd - Start);
      if Trim(Raw) = '' then Exit;
      var S:= Default(TSectionStatement);
      var First:= Start;
      while (First < pEnd) and CharInSet(pSource.Masked[First], [' ', #9, #13, #10]) do Inc(First);
      S.Line:= pSource.LineOf(First);
      var Last:= pSource.LineOf(pEnd - 1);
      S.Text:= Trim(Copy(pSource.Text, First, pSource.LineEnd(S.Line) - First));
      for var L:= S.Line to Last do
        if pHeavyLines.ContainsKey(L) then S.Heavy:= True;
      Found:= Found + [S];
    end;
  for var M in TRegEx.Matches(Copy(pSource.Masked, pFrom, pTo - pFrom), '\b(begin|try|case|asm|end)\b|;', [roIgnoreCase]) do
  begin
    var Pos_:= pFrom + M.Index - 1;
    if M.Value = ';' then
    begin
      if Depth = 0 then
      begin
        Close_(Pos_ + 1);
        Start:= Pos_ + 1;
      end;
    end
    else if SameText(M.Value, 'end') then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        { `end` closing a block ends the statement at its `;`, which comes next; a bare `end` before finalization ends here }
        var Next:= Pos_ + Length(M.Value);
        while (Next < pTo) and CharInSet(pSource.Masked[Next], [' ', #9, #13, #10]) do Inc(Next);
        if (Next >= pTo) or (pSource.Masked[Next] <> ';') then
        begin
          Close_(Next);
          Start:= Next;
        end;
      end;
    end
    else Inc(Depth);
  end;
  Close_(pTo);
  Result:= Found;
end;

// What the section writes among the unit's globals, and who reads them.
function ReadGlobals(pConn: TFDConnection; const pPath: string; pFirstLine, pLastLine: Integer): TArray<TSectionGlobal>;
begin
  Result:= nil;
  var Q:= TFDQuery.Create(nil);
  var R:= TFDQuery.Create(nil);
  try
    Q.Connection:= pConn;
    R.Connection:= pConn;
    Q.SQL.Text:= 'SELECT DISTINCT s.id, s.name, COALESCE(s.section, '''') FROM refs r JOIN files f ON f.id = r.file_id ' +
      'JOIN symbols s ON s.file_id = r.file_id AND s.name = r.name_text COLLATE NOCASE ' +
      'JOIN symbols u ON u.id = s.parent_id AND u.kind = ''unit'' ' +
      'WHERE f.path = :p COLLATE NOCASE AND r.kind = ''write'' AND r.start_line BETWEEN :a AND :b AND s.kind IN (''variable'', ''var'', ''field'', ''global_var'') ORDER BY s.name';
    Q.ParamByName('p').AsWideString:= pPath;
    Q.ParamByName('a').AsInteger:= pFirstLine;
    Q.ParamByName('b').AsInteger:= pLastLine;
    Q.Open;
    R.SQL.Text:= 'SELECT SUM(f.path = :p COLLATE NOCASE AND NOT (r.start_line BETWEEN :a AND :b)), SUM(f.path <> :p COLLATE NOCASE) ' +
      'FROM refs r JOIN files f ON f.id = r.file_id WHERE r.name_text = :n COLLATE NOCASE AND r.kind <> ''write''';
    while not Q.Eof do
    begin
      var G:= Default(TSectionGlobal);
      G.Name:= Q.Fields[1].AsString;
      G.Section:= Q.Fields[2].AsString;
      R.Close;
      R.ParamByName('p').AsWideString:= pPath;
      R.ParamByName('a').AsInteger:= pFirstLine;
      R.ParamByName('b').AsInteger:= pLastLine;
      R.ParamByName('n').AsWideString:= G.Name;
      R.Open;
      G.ReadersInUnit:= R.Fields[0].AsInteger;
      G.ReadersElsewhere:= R.Fields[1].AsInteger;
      G.LazyCandidate:= SameText(G.Section, 'implementation') and (G.ReadersElsewhere = 0);
      Result:= Result + [G];
      Q.Next;
    end;
  finally
    R.Free;
    Q.Free;
  end;
end;

// The smallest routine implementation (defProc) whose span holds pByte; null when none does.
procedure InnermostProcAt(const pNode: TTSNode; pByte: Int64; var pBest: TTSNode);
begin
  if pNode.IsNull or (Int64(pNode.StartByte) > pByte) or (Int64(pNode.EndByte) < pByte) then Exit;
  if (pNode.NodeType = 'defProc') and
     (pBest.IsNull or (Int64(pNode.EndByte) - Int64(pNode.StartByte) < Int64(pBest.EndByte) - Int64(pBest.StartByte))) then
    pBest:= pNode;
  for var I: Integer:= 0 to Integer(pNode.NamedChildCount) - 1 do
    InnermostProcAt(pNode.NamedChild(I), pByte, pBest);
end;

// --defer: every routine of the file that touches a global the section writes, outside the section and finalization lines
// [pSkipFrom, pSkipTo]. False with pKind / pReason set on a use the call cannot be put in front of.
function FindEntryPoints(pConn: TFDConnection; pSource: TMaskedSource; const pPath: string; const pGlobals: TArray<TSectionGlobal>;  // dl:ok too-many-parameters@0563, deep-nesting@28ee -- the section's read-only context plus three outs; the nesting is one query loop per global, kept in one routine so each refusal exits with its reason
  pSkipFrom, pSkipTo: Integer; out pPoints: TArray<TEntryPoint>; out pKind, pReason: string): Boolean;
const
  CLineFeed = 10;   // the byte that ends a line in PF.Src
begin
  Result:= False;
  pPoints:= nil;
  pKind:= '';
  pReason:= '';
  var PF:= TAstParseCache.Get(pPath);
  if PF.Tree = nil then
  begin
    pKind:= 'parse-failed';
    pReason:= 'the file did not parse';
    Exit;
  end;
  var LineBytes:= TList<Int64>.Create;   // 1-based: LineBytes[L] = byte offset of line L
  LineBytes.AddRange([0, 0]);
  for var B:= 0 to Length(PF.Src) - 1 do
    if PF.Src[B] = CLineFeed then LineBytes.Add(Int64(B) + 1);
  var Seen:= TDictionary<Int64, Boolean>.Create;
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= pConn;
    Q.SQL.Text:= 'SELECT r.start_line, r.start_col, r.name_text FROM refs r JOIN files f ON f.id = r.file_id ' +
      'WHERE f.path = :p COLLATE NOCASE AND r.name_text = :n COLLATE NOCASE ORDER BY r.start_line, r.start_col';
    for var G in pGlobals do
    begin
      Q.Close;
      Q.ParamByName('p').AsWideString:= pPath;
      Q.ParamByName('n').AsWideString:= G.Name;
      Q.Open;
      while not Q.Eof do
      begin
        var L:= Q.Fields[0].AsInteger;
        if ((L < pSkipFrom) or (L > pSkipTo)) and (L >= 1) and (L < LineBytes.Count) then
        begin
          var Proc:= Default(TTSNode);
          InnermostProcAt(PF.Tree.RootNode, LineBytes[L] + Max(Q.Fields[1].AsInteger - 1, 0), Proc);
          if Proc.IsNull then
          begin
            pKind:= 'reader-outside-routine';
            pReason:= Format('%s is used on line %d outside any routine', [Q.Fields[2].AsString, L]);
            Exit;
          end;
          if not Seen.ContainsKey(Int64(Proc.StartByte)) then
          begin
            Seen.Add(Int64(Proc.StartByte), True);
            var Body:= Proc.ChildByField('body');
            var BL:= if Body.IsNull then 0 else Integer(Body.StartPoint.Row) + 1;
            var At:= 0;
            if (BL >= 1) and (BL < Length(pSource.Starts)) then
              for var M in TRegEx.Matches(Copy(pSource.Masked, pSource.Starts[BL], pSource.LineEnd(BL) - pSource.Starts[BL]), '\bbegin\b', [roIgnoreCase]) do
                if M.Index <= Integer(Body.StartPoint.Column) + 1 then At:= pSource.Starts[BL] + M.Index - 1 + M.Length;
            if At = 0 then
            begin
              pKind:= 'asm-reader';
              pReason:= Format('%s is used on line %d in a routine whose body is not a begin block', [Q.Fields[2].AsString, L]);
              Exit;
            end;
            var P:= Default(TEntryPoint);
            P.Line:= Integer(Proc.StartPoint.Row) + 1;
            var H:= TRegEx.Match(Copy(pSource.Text, pSource.Starts[P.Line], pSource.LineEnd(P.Line) - pSource.Starts[P.Line]),
              '\b(procedure|function|constructor|destructor|operator)\s+([\w.]+)', [roIgnoreCase]);
            P.Name:= if H.Success then H.Groups[2].Value else Format('line %d', [P.Line]);
            P.InsertAt:= At;
            var LineText:= Copy(pSource.Text, pSource.Starts[BL], pSource.LineEnd(BL) - pSource.Starts[BL]);
            P.Indent:= Copy(LineText, 1, Length(LineText) - Length(LineText.TrimLeft)) + '  ';
            pPoints:= pPoints + [P];
          end;
        end;
        Q.Next;
      end;
    end;
  finally
    Q.Free;
    Seen.Free;
    LineBytes.Free;
  end;
  if Length(pPoints) = 0 then
  begin
    pKind:= 'no-entry-point';
    pReason:= 'no routine outside the section touches what it writes: deferred, the work would never run';
    Exit;
  end;
  TArray.Sort<TEntryPoint>(pPoints, TComparer<TEntryPoint>.Construct(
    function(const pA, pB: TEntryPoint): Integer begin Result:= pA.InsertAt - pB.InsertAt; end));
  Result:= True;
end;

function PlanSection(const pStore: ISymbolStore; const pConn: TFDConnection; const pOwn: TOwnRoots; const pOpts: TLazyInitOptions;  // dl:ok too-many-exit-points@004d -- one guard per named refusal, in the documented order: the exits are the contract
  const pPath, pUnit: string; const pHeavy: TArray<TLintFinding>): TSectionPlan;

  procedure Refuse(var pPlan: TSectionPlan; const pKind, pReason: string);
  begin
    pPlan.RefusalKind:= pKind;
    pPlan.RefusalReason:= pReason;
  end;

begin
  Result:= Default(TSectionPlan);
  Result.UnitName:= pUnit;
  Result.FilePath:= pPath;
  var HeavyLines:= TDictionary<Integer, Boolean>.Create;
  var Source: TMaskedSource:= nil;
  try
    for var F in pHeavy do
      if SameText(F.FilePath, pPath) then
      begin
        HeavyLines.AddOrSetValue(F.StartLine, True);
        Result.Heavy:= True;
        Result.Evidence:= F.Message;
      end;
    if not MatchText(ExtractFileExt(pPath), ['.pas', '.dpr', '.dpk']) then
    begin
      Refuse(Result, 'include-file', 'an include file compiles in every unit that includes it');
      Exit;
    end;
    if not TFile.Exists(pPath) or not IsFileCurrent(pStore, pPath) then
    begin
      Refuse(Result, 'stale-file', 'the file changed since it was indexed; re-index');
      Exit;
    end;
    if (pOpts.Project <> '') and not pOwn.IsOurs(pPath) then
    begin
      Refuse(Result, 'outside-roots', 'the file lies outside the project''s own roots');
      Exit;
    end;
    Source:= TMaskedSource.Create(pPath);
    var Keyword:= TRegEx.Matches(Source.Masked, '^[ \t]*initialization\b', [roIgnoreCase, roMultiLine]);
    var Impl:= TRegEx.Match(Source.Masked, '^[ \t]*implementation\b', [roIgnoreCase, roMultiLine]);
    if (Keyword.Count <> 1) or not Impl.Success or (Keyword[0].Index < Impl.Index) then
    begin
      Refuse(Result, 'no-section', 'the unit has no initialization keyword after its implementation (the `begin ... end.` form is not taken)');
      Exit;
    end;
    var KeyStart:= Keyword[0].Index;
    var BodyStart:= KeyStart + Keyword[0].Length;
    Result.Line:= Source.LineOf(BodyStart - 1);
    if Source.CondAt[Result.Line] then
    begin
      Refuse(Result, 'ifdef-around-section', 'the initialization keyword is inside a conditional region');
      Exit;
    end;
    var FinalM:= TRegEx.Match(Source.Masked, '^[ \t]*finalization\b', [roIgnoreCase, roMultiLine]);
    var EndM:= TRegEx.Matches(Source.Masked, '\bend\s*\.', [roIgnoreCase]);
    if EndM.Count = 0 then
    begin
      Refuse(Result, 'no-section', 'the unit has no closing `end.`');
      Exit;
    end;
    var BodyEnd:= if FinalM.Success and (FinalM.Index > BodyStart) then FinalM.Index else EndM[EndM.Count - 1].Index;
    var Body:= Copy(Source.Text, BodyStart, BodyEnd - BodyStart);
    if Trim(Body) = '' then
    begin
      Refuse(Result, 'empty-section', 'there is nothing to move');
      Exit;
    end;
    if TRegEx.IsMatch(Body, '\{\$(I|INCLUDE)\s', [roIgnoreCase]) then
    begin
      Refuse(Result, 'include-in-section', 'an included file''s statements cannot be seen or moved');
      Exit;
    end;
    var Opens:= TRegEx.Matches(Body, '\{\$(IFDEF|IFNDEF|IF|IFOPT)\b', [roIgnoreCase]).Count;
    var Closes:= TRegEx.Matches(Body, '\{\$(ENDIF|IFEND)\b', [roIgnoreCase]).Count;
    if Opens <> Closes then
    begin
      Refuse(Result, 'unbalanced-ifdef', 'a conditional opens or closes across the section''s edge');
      Exit;
    end;
    Result.Statements:= SplitStatements(Source, BodyStart, BodyEnd, HeavyLines);
    Result.Globals:= ReadGlobals(pConn, pPath, Result.Line, Source.LineOf(BodyEnd));
    var Name:= if pOpts.RoutineName <> '' then pOpts.RoutineName else 'Ensure' + pUnit.Replace('.', '') + 'Initialized';
    Result.RoutineName:= Name;
    var Q:= TFDQuery.Create(nil);
    try
      Q.Connection:= pConn;
      Q.SQL.Text:= 'SELECT 1 FROM symbols WHERE name = :n COLLATE NOCASE AND kind NOT IN (''param'', ''local_var'')';
      Q.ParamByName('n').AsWideString:= Name;
      Q.Open;
      if not Q.Eof then
      begin
        Refuse(Result, 'name-taken', Format('%s already exists: this section was extracted, or pass --name', [Name]));
        Exit;
      end;
    finally
      Q.Free;
    end;
    var Eol:= if Source.Text.Contains(#13#10) then #13#10 else #10;
    var Guard:= 'G' + Name + 'Done';
    var Kept:= Body.TrimRight;
    while StartsStr(#13, Kept) or StartsStr(#10, Kept) do Kept:= Copy(Kept, 2, MaxInt);
    var Tail:= Copy(Source.Text, BodyEnd, MaxInt);
    var Head:= Copy(Source.Text, 1, KeyStart - 1);
    var Section:= 'initialization' + Eol + '  ' + Name + ';' + Eol + Eol;
    if pOpts.Defer then
    begin
      Result.Deferred:= True;
      if Length(Result.Globals) = 0 then
      begin
        Refuse(Result, 'no-lazy-global', 'the section writes no global of the unit: no routine marks a first use');
        Exit;
      end;
      var Shared:= '';
      for var G in Result.Globals do
        if not G.LazyCandidate then Shared:= Shared + IfThen(Shared <> '', ', ') + G.Name;
      if Shared <> '' then
      begin
        Refuse(Result, 'global-read-elsewhere', Format('%s: declared in the interface or read by another unit, which could read it before the work ran', [Shared]));
        Exit;
      end;
      var EndAt:= EndM[EndM.Count - 1].Index;
      var FinalBody:= if BodyEnd < EndAt then Copy(Source.Text, BodyEnd + FinalM.Length, EndAt - BodyEnd - FinalM.Length) else '';
      if TRegEx.Matches(FinalBody, '\{\$(IFDEF|IFNDEF|IF|IFOPT)\b', [roIgnoreCase]).Count <> TRegEx.Matches(FinalBody, '\{\$(ENDIF|IFEND)\b', [roIgnoreCase]).Count then
      begin
        Refuse(Result, 'unbalanced-ifdef', 'a conditional opens or closes across the finalization section''s edge');
        Exit;
      end;
      var Kind, Reason: string;
      if not FindEntryPoints(pConn, Source, pPath, Result.Globals, Result.Line, Source.LineOf(EndAt), Result.EntryPoints, Kind, Reason) then
      begin
        Refuse(Result, Kind, Reason);
        Exit;
      end;
      for var I:= High(Result.EntryPoints) downto 0 do
        Insert(Eol + Result.EntryPoints[I].Indent + Name + ';', Head, Result.EntryPoints[I].InsertAt);
      var ImplEnd:= Impl.Index + Impl.Length;
      var UsesM:= TRegEx.Match(Copy(Source.Masked, ImplEnd, KeyStart - ImplEnd), '\A\s*uses\b[^;]*;', [roIgnoreCase]);
      Insert(Eol + Eol + 'procedure ' + Name + '; forward;', Head, ImplEnd + (if UsesM.Success then UsesM.Length else 0));
      var KeptFinal:= FinalBody.TrimRight;
      while StartsStr(#13, KeptFinal) or StartsStr(#10, KeptFinal) do KeptFinal:= Copy(KeptFinal, 2, MaxInt);
      Section:= if KeptFinal = '' then '' else
        'initialization' + Eol + Eol + 'finalization' + Eol + '  if ' + Guard + ' then' + Eol + '  begin' + Eol + KeptFinal + Eol + '  end;' + Eol;
      Tail:= Copy(Source.Text, EndAt, MaxInt);
    end;
    Result.Inserted:=
      'var' + Eol +
      '  ' + Guard + ': Boolean;' + Eol + Eol +
      '/// <summary>Runs what the initialization section of ' + pUnit + ' ran, once per process (drag-lint lazy-init' +
      IfThen(pOpts.Defer, ' --defer: on first use') + ').</summary>' + Eol +
      'procedure ' + Name + ';' + Eol +
      'begin' + Eol +
      '  if ' + Guard + ' then Exit;' + Eol +
      '  ' + Guard + ':= True;' + Eol +
      Kept + Eol +
      'end;' + Eol + Eol;
    Result.NewText:= Head + Result.Inserted + Section + Tail;
    Result.Enc:= Source.Enc;
  finally
    Source.Free;
    HeavyLines.Free;
  end;
end;

procedure PrintPlanText(const pP: TSectionPlan; pApply: Boolean);
begin
  if pP.RefusalKind <> '' then
    Writeln(Format('lazy-init: %s refused: %s -- %s', [pP.UnitName, pP.RefusalKind, pP.RefusalReason]))
  else
    Writeln(Format('lazy-init: %s:%d  %s: %d statement(s)%s, routine %s%s', [pP.FilePath, pP.Line, pP.UnitName, Length(pP.Statements),
      if pP.Heavy then ', heavy' else ', not reported heavy', pP.RoutineName, if pApply then '' else ' (plan; add --apply --project <X.dproj> to write)']));
  for var S in pP.Statements do Writeln(Format('  %s line %d  %s', [if S.Heavy then 'heavy' else 'light', S.Line, S.Text]));
  for var E in pP.EntryPoints do Writeln(Format('  entry point %s line %d calls %s first (--defer)', [E.Name, E.Line, pP.RoutineName]));
  for var G in pP.Globals do
    Writeln(Format('  global %s (%s section): %d reader(s) in the unit, %d elsewhere, lazy_candidate=%s',
      [G.Name, G.Section, G.ReadersInUnit, G.ReadersElsewhere, LowerCase(BoolToStr(G.LazyCandidate, True))]));
end;

function PlanJson(const pP: TSectionPlan): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('unit', pP.UnitName);
  Result.AddPair('file', pP.FilePath);
  Result.AddPair('line', TJSONNumber.Create(pP.Line));
  Result.AddPair('heavy', TJSONBool.Create(pP.Heavy));
  if pP.Evidence <> '' then Result.AddPair('evidence', pP.Evidence);
  if pP.RefusalKind <> '' then
  begin
    var R:= TJSONObject.Create;
    R.AddPair('kind', pP.RefusalKind);
    R.AddPair('reason', pP.RefusalReason);
    Result.AddPair('refusal', R);
  end
  else
  begin
    Result.AddPair('routine', pP.RoutineName);
    Result.AddPair('text', pP.Inserted);
  end;
  if pP.Deferred then
  begin
    Result.AddPair('deferred', TJSONBool.Create(True));
    var Es:= TJSONArray.Create;
    Result.AddPair('entry_points', Es);
    for var E in pP.EntryPoints do
    begin
      var O:= TJSONObject.Create;
      O.AddPair('name', E.Name);
      O.AddPair('line', TJSONNumber.Create(E.Line));
      Es.AddElement(O);
    end;
  end;
  var Ss:= TJSONArray.Create;
  Result.AddPair('statements', Ss);
  for var S in pP.Statements do
  begin
    var O:= TJSONObject.Create;
    O.AddPair('line', TJSONNumber.Create(S.Line));
    O.AddPair('text', S.Text);
    O.AddPair('heavy', TJSONBool.Create(S.Heavy));
    Ss.AddElement(O);
  end;
  var Gs:= TJSONArray.Create;
  Result.AddPair('globals', Gs);
  for var G in pP.Globals do
  begin
    var O:= TJSONObject.Create;
    O.AddPair('name', G.Name);
    O.AddPair('section', G.Section);
    O.AddPair('readers_in_unit', TJSONNumber.Create(G.ReadersInUnit));
    O.AddPair('readers_elsewhere', TJSONNumber.Create(G.ReadersElsewhere));
    O.AddPair('lazy_candidate', TJSONBool.Create(G.LazyCandidate));
    Gs.AddElement(O);
  end;
end;

function RunLazyInit(const pStore: ISymbolStore; const pOpts: TLazyInitOptions): Integer;  // dl:ok too-many-exit-points@ea4e -- one guard per named refusal, in the documented order: the exits are the contract

  function Fail(const pMessage: string): Integer;
  begin
    Result:= ReportVerbError(pOpts.Json, CSchema, pMessage);
  end;

begin
  if (pOpts.UnitName = '') = not pOpts.All then Exit(Fail(CVerb + ' needs --unit <name> or --all'));
  if pOpts.Apply and pOpts.All then Exit(Fail(CVerb + ' --apply takes one --unit, not --all'));
  if pOpts.Defer and pOpts.All then Exit(Fail(CVerb + ' --defer takes one --unit, not --all'));
  if pOpts.Apply and pOpts.NoCompile then Exit(Fail(CVerb + ' --apply cannot take --no-compile: every applied rewrite is built'));
  if pOpts.Apply and (pOpts.Project = '') then Exit(Fail(CVerb + ' --apply needs --project <X.dproj>: the gates build it'));
  if pStore is not TSQLiteSymbolStore then Exit(Fail(CVerb + ' needs a SQLite index'));
  Result:= CExitOk;
  var Conn:= (pStore as TSQLiteSymbolStore).GetConnection;
  var Own: TOwnRoots:= Default(TOwnRoots);
  if pOpts.Project <> '' then Own:= TOwnRoots.Load(ExtractFilePath(ExpandFileName(pOpts.Project)));
  var Heavy:= CollectHeavyInitialization(pStore);
  var Plans: TArray<TSectionPlan>:= nil;
  if pOpts.All then
  begin
    var Done:= TDictionary<string, Boolean>.Create;
    try
      for var F in Heavy do
        if not Done.ContainsKey(LowerCase(F.FilePath)) then
        begin
          Done.Add(LowerCase(F.FilePath), True);
          var UnitName:= TPath.GetFileNameWithoutExtension(F.FilePath);
          Plans:= Plans + [PlanSection(pStore, Conn, Own, pOpts, F.FilePath, UnitName, Heavy)];
        end;
    finally
      Done.Free;
    end;
  end
  else
  begin
    var Path, UnitName: string;
    if not FindUnit(Conn, pOpts.UnitName, Path, UnitName) then Exit(Fail(Format('%s: the index has no unit %s', [CVerb, pOpts.UnitName])));
    Plans:= [PlanSection(pStore, Conn, Own, pOpts, Path, UnitName, Heavy)];
  end;
  var Gate:= Default(TGateOutcome);
  var Ran:= False;
  if pOpts.Apply then
    if Plans[0].RefusalKind <> '' then Result:= CExitRefused
    else
    begin
      var Args:= Default(TOneFileApplyArgs);
      Args.Verb:= CVerb;
      Args.HeaderTail:= Plans[0].RoutineName;
      Args.Project:= pOpts.Project;
      Args.Platform:= pOpts.Platform;
      Args.RsVars:= pOpts.RsVars;
      Args.BuildTimeout:= pOpts.BuildTimeout;
      Args.NoBackup:= pOpts.NoBackup;
      Args.FilePath:= Plans[0].FilePath;
      Gate:= ApplyOneFileThroughScratch(Conn, Args, EncodeSource(Plans[0].NewText, Plans[0].Enc));
      Ran:= True;
      if not Gate.Applied then Result:= if Gate.RollbackFailed then CExitError else CExitRefused;
    end;
  if pOpts.Json then
  begin
    var J:= TJSONObject.Create;
    try
      J.AddPair('schema', CSchema);
      J.AddPair('applied', TJSONBool.Create(Ran and Gate.Applied));
      var Arr:= TJSONArray.Create;
      J.AddPair('sections', Arr);
      for var P in Plans do Arr.AddElement(PlanJson(P));  // dl:ok duplicate-code@bae4 -- sibling verb plumbing (lazy-init / extract-interface / deps share the refactor-verb shape); a shared helper is a 148 row (147 INT sweep)
      if Ran then
      begin
        var G:= TJSONObject.Create;
        G.AddPair('refusal', Gate.Refusal);
        G.AddPair('detail', Gate.Detail);
        G.AddPair('rolled_back', TJSONBool.Create(Gate.RolledBack));
        G.AddPair('rollback_failed', TJSONBool.Create(Gate.RollbackFailed));
        J.AddPair('gate', G);
      end;
      Writeln(J.Format(2));
    finally
      J.Free;
    end;
  end
  else
  begin
    for var P in Plans do PrintPlanText(P, pOpts.Apply);
    if Length(Plans) = 0 then Writeln('lazy-init: no section reported heavy');
    if Ran then
      if Gate.Applied then Writeln('applied and built; re-index the project')
      else Writeln(Format('refused [%s]: %s', [Gate.Refusal, Gate.Detail]));
  end;
end;

end.
