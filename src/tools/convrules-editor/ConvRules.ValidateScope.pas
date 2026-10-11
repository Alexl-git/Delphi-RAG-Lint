unit ConvRules.ValidateScope;

{ Which convert-validate diagnostics a Save or a Validate KEEPS, and which rule
  line each kept one marks.

  Why this exists (2026-10-05): with --from/--to the engine checks EVERY #convert
  block of a book against that ONE pair, so validating a multi-block book with the
  active block's pair reported 145 false errors on BDE-to-FireDAC.rules. Without a
  pair it is syntax-only. Owner ruling: "The edited saved block should be
  validated. Stuff that is unchanged is presumed validated earlier." So a save runs
  one syntax pass over the whole text plus one pass per CHANGED block with that
  block's own pair, keeping only the diagnostics on that block's lines (and on the
  lines of the #mapping definitions it #applies).

  Pure: no UI, no engine. The engine call is injected (TValidateFn), so the model
  tests drive every decision here with captured real output. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , ConvRules.Model
  ;

type
  /// <summary>One diagnostic line from convert-validate's text output.</summary>
  /// <remarks>Line is 1-based in the validated text; 0 for a diagnostic that names
  /// no line (a FATAL, an unexpected message) -- such a line is never dropped by a
  /// block filter and, unless it starts "warning:", counts as an error.</remarks>
  TValidateDiag = record
    /// <summary>1-based line in the validated text; 0 when the line names none.</summary>
    Line     : Integer;
    /// <summary>True for "line N: warning: ..." (or a bare "warning: ...").</summary>
    IsWarning: Boolean;
    /// <summary>The engine's line, trimmed.</summary>
    Text     : string ;
  end;

  /// <summary>One #convert block to validate with its OWN From/To pair.</summary>
  TValidateJob = record
    /// <summary>The header's From type, as written.</summary>
    FromType    : string;
    /// <summary>The header's To type, as written; never '' in a job.</summary>
    ToType      : string;
    /// <summary>1-based line of the #convert header in the validated text.</summary>
    FirstLine   : Integer;
    /// <summary>1-based last line of the block (the line before the next header,
    /// or the last line of the text).</summary>
    LastLine    : Integer;
    /// <summary>Lines of every #mapping line whose name the block #applies --
    /// a diagnostic there belongs to this block's pass too.</summary>
    MappingLines: TArray<Integer>;
    /// <summary>The block's identity across saves: its header line plus how many
    /// identical headers precede it. What ChangedBlockJobs compares and what a
    /// pending-validation set holds.</summary>
    Key         : string;
  end;

  /// <summary>The engine call: validate AText, with the pair when AFrom and ATo are
  /// both non-empty, syntax-only when they are both ''. Returns the raw output
  /// (stdout and stderr together); the exit code is deliberately not consulted.</summary>
  TValidateFn = reference to function(const AText, AFrom, ATo: string): string;

  /// <summary>Has the user cancelled? Polled before and after every engine call.</summary>
  TCancelledFn = reference to function: Boolean;

  /// <summary>Everything one scoped validation produced.</summary>
  TScopedValidation = record
    /// <summary>Every diagnostic of the syntax-only pass.</summary>
    Syntax  : TArray<TValidateDiag>;
    /// <summary>Per job (same index as the jobs passed in): the diagnostics kept
    /// for that block.</summary>
    JobDiags: TArray<TArray<TValidateDiag>>;
    /// <summary>Syntax + every job's kept diagnostics, de-duplicated on (Line, Text).</summary>
    Kept    : TArray<TValidateDiag>;
    /// <summary>Errors among Kept.</summary>
    Errors  : Integer;
    /// <summary>Warnings among Kept.</summary>
    Warnings: Integer;
    /// <summary>The syntax pass ran to completion (False when cancelled).</summary>
    SyntaxDone: Boolean;
    /// <summary>Per job: its pass ran to completion. A job that is not done
    /// contributes no diagnostics and its block keeps its earlier marks.</summary>
    JobDone   : TArray<Boolean>;
    /// <summary>The run was cancelled before every pass completed.</summary>
    Cancelled : Boolean;
    /// <summary>From types of the jobs not done, in job order.</summary>
    NotChecked: TArray<string>;
  end;

/// <summary>Is ALine output noise rather than a diagnostic?</summary>
/// <param name="ALine">One output line, untrimmed.</param>
/// <returns>True for a blank line, the bare "OK", the "(loaded defaults from ...)"
/// banner, the engine's "resolver: edges were derived by ..." advisory and a line that,
/// trimmed, starts with exactly "NOTE:" (case-sensitive; "line N: NOTE: ..." and
/// "note: ..." are not noise). Engine 1.26.x prints "NOTE: --from and --to not both
/// given -- the book was PARSED only; ..." on every syntax-only pass.</returns>
function IsValidateNoise(const ALine: string): Boolean;

/// <summary>Parse convert-validate's text output into diagnostics.</summary>
/// <param name="AOutput">Raw output, any line endings.</param>
/// <returns>One entry per non-noise line, in output order. "line N: warning: ..."
/// is a warning on N; "line N: ..." an error on N; "warning: ..." a warning on line
/// 0; anything else non-noise (FATAL, ERROR, usage) an error on line 0.</returns>
function ParseValidateOutput(const AOutput: string): TArray<TValidateDiag>;

/// <summary>Every #convert block of AText that has a To type, as a job.</summary>
/// <param name="AText">The text to be validated (SaveCompleteToString's output).</param>
/// <returns>Jobs in file order. A From-only block (no To) is not a job: the
/// syntax pass already reports it.</returns>
function BlockJobs(const AText: string): TArray<TValidateJob>;

/// <summary>The blocks of ANewText that changed since AOldText.</summary>
/// <param name="AOldText">The last loaded / saved canonical text ('' for a new book).</param>
/// <param name="ANewText">The text about to be validated.</param>
/// <returns>Jobs (with ANewText line numbers) for each block whose header is new,
/// whose emitted text differs from the old block with the same header, or which
/// #applies a #mapping whose lines changed. Blocks are keyed by their header line
/// (plus its occurrence number, so a repeated header still pairs up in order).
/// From-only blocks are never returned.</returns>
/// <param name="APending">Keys (TValidateJob.Key) of blocks whose last validation
/// did not complete (NextPending); such a block is returned even when unchanged.</param>
function ChangedBlockJobs(const AOldText, ANewText: string; const APending: TArray<string> = nil): TArray<TValidateJob>;

/// <summary>The pending-validation set after a run.</summary>
/// <param name="APending">The set before the run.</param>
/// <param name="AJobs">The jobs the run was given.</param>
/// <param name="AResult">What RunScopedValidation returned for them.</param>
/// <returns>APending minus the keys of the jobs that completed, plus the keys of the
/// jobs that did not -- so a cancelled block is validated on the next save even
/// though it no longer differs from the snapshot.</returns>
function NextPending(const APending: TArray<string>; const AJobs: TArray<TValidateJob>; const AResult: TScopedValidation): TArray<string>;

/// <summary>The job for the block whose header is on line AHeaderLine.</summary>
/// <param name="AText">The text to be validated.</param>
/// <param name="AHeaderLine">1-based line of a #convert header in AText.</param>
/// <param name="AJob">The job; Default when the result is False.</param>
/// <returns>False when no header is on that line or the block has no To type.</returns>
function JobAtLine(const AText: string; AHeaderLine: Integer; out AJob: TValidateJob): Boolean;

/// <summary>The diagnostics that belong to AJob's block.</summary>
/// <param name="ADiags">A pair pass's diagnostics (every block checked against
/// the job's pair).</param>
/// <param name="AJob">The block.</param>
/// <returns>Those on the block's lines, on its applied #mapping lines, or on line 0.</returns>
function DiagsForJob(const ADiags: TArray<TValidateDiag>; const AJob: TValidateJob): TArray<TValidateDiag>;

/// <summary>Run the syntax pass and one pass per job, keeping what each owns.</summary>
/// <param name="AText">The text to validate.</param>
/// <param name="AJobs">The blocks to check with their own pair.</param>
/// <param name="AValidate">The engine call; called 1 + Length(AJobs) times unless
/// cancelled.</param>
/// <param name="ACancelled">Polled before and after each call; nil = never. A
/// pass during or after which it answers True is NOT done, and no further pass
/// starts.</param>
/// <returns>The kept diagnostics and their counts, from completed passes only.
/// OK/failed is Errors = 0 -- never the exit code.</returns>
function RunScopedValidation(const AText: string; const AJobs: TArray<TValidateJob>; const AValidate: TValidateFn; const ACancelled: TCancelledFn = nil): TScopedValidation;

/// <summary>The status-line verdict for a scoped validation.</summary>
/// <param name="AResult">What RunScopedValidation returned.</param>
/// <returns>"OK"; "OK, N warning(s) -- see marked rules"; or the first kept
/// error, then " (+N more)" when other diagnostics were kept, then
/// " -- see marked rules". A cancelled run reads "cancelled -- N changed block(s)
/// not checked: T1, T2" (plus "; syntax not checked" when that pass did not
/// complete), followed by "; checked so far: " and the verdict above when any
/// pass completed.</returns>
function ValidateVerdict(const AResult: TScopedValidation): string;

/// <summary>Replace validation marks after a scoped validation.</summary>
/// <param name="ABookNodes">Every node of the book (dropped blocks included).
/// Syntax marks are cleared on all of them.</param>
/// <param name="ALineNodes">The line map from TRuleBook.SaveCompleteWithMap for the
/// SAME text that was validated.</param>
/// <param name="AJobs">The jobs given to the run. Block marks are cleared on the
/// lines and applied #mapping lines of the jobs that COMPLETED only; every other
/// node -- a cancelled job's included -- keeps its block marks. Syntax marks are
/// replaced only when the syntax pass completed.</param>
/// <param name="AResult">What RunScopedValidation returned for those jobs.</param>
/// <remarks>Marks never touch Emit, Snapshot or Dirty. A job diagnostic whose text
/// the syntax pass already put on the node is not added twice; a line-0
/// diagnostic marks nothing.</remarks>
procedure ApplyValidateMarks(const ABookNodes, ALineNodes: TArray<TRuleNode>; const AJobs: TArray<TValidateJob>; const AResult: TScopedValidation);

/// <summary>The nodes whose marks belong to a block: its header, body, and every
/// #mapping line it #applies.</summary>
/// <param name="ABook">The book.</param>
/// <param name="AHeaderIdx">Index of a #convert header in ABook.Nodes.</param>
/// <returns>Borrowed nodes; [] for an index that is not a header.</returns>
function BlockMarkNodes(ABook: TRuleBook; AHeaderIdx: Integer): TArray<TRuleNode>;

/// <summary>Count and list the marks on ANodes.</summary>
/// <param name="ANodes">Nodes to read.</param>
/// <param name="AErrors">Error marks.</param>
/// <param name="AWarnings">Warning marks.</param>
/// <returns>Every mark's text, one per line (CRLF), errors first; '' when none.</returns>
function MarksText(const ANodes: TArray<TRuleNode>; out AErrors, AWarnings: Integer): string;

/// <summary>A short marker for a list row: '' / "2 err" / "3 warn" / "1 err, 2 warn".</summary>
/// <param name="AErrors">Error count.</param>
/// <param name="AWarnings">Warning count.</param>
/// <returns>The marker text.</returns>
function MarkerText(AErrors, AWarnings: Integer): string;

implementation

const
  CRLF = #13#10;
  /// <summary>Every engine diagnostic that names a line starts with this.</summary>
  LINE_PREFIX = 'line ';
  /// <summary>The engine's warning marker, after "line N: " or on its own.</summary>
  WARNING_PREFIX = 'warning:';
  /// <summary>The engine's informational marker, case-sensitive (noise, see IsValidateNoise).</summary>
  NOTE_PREFIX = 'NOTE:';

type
  /// <summary>One #convert block as found in a text.</summary>
  TBlockScan = record
    Key    : string        ; // header line + occurrence number
    Job    : TValidateJob  ; // ToType may be '' here; jobs never carry one
    Text   : string        ; // the block's lines, CRLF-joined
    Applies: TArray<string>; // upper-cased #apply names
  end;

  /// <summary>Every line of one #mapping name, wherever they sit.</summary>
  TMapScan = record
    Name : string         ; // upper-cased
    Text : string         ; // its lines, CRLF-joined
    Lines: TArray<Integer>; // 1-based
  end;

function FindMap(const AMaps: TArray<TMapScan>; const AName: string): Integer;
var
  i: Integer;
begin
  for i:= 0 to High(AMaps) do
    if AMaps[i].Name = AName then
      Exit(i);
  Result:= -1;
end;

function MapText(const AMaps: TArray<TMapScan>; const AName: string): string;
var
  i: Integer;
begin
  i:= FindMap(AMaps, AName);
  if i >= 0 then
    Result:= AMaps[i].Text
  else
    Result:= '';
end;

{ Parse AText line by line through the model (one node per physical line, so node
  i is line i + 1) and collect its blocks and its #mapping lines. }
procedure ScanText(const AText: string; out ABlocks: TArray<TBlockScan>; out AMaps: TArray<TMapScan>);
var
  Book: TRuleBook;
  N   : TRuleNode;
  Line: string   ;
  Cur : Integer  ;
  i   : Integer  ;
  k   : Integer  ;
  M   : Integer  ;
begin
  ABlocks:= nil;
  AMaps  := nil;
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString(AText);
    Cur:= -1;
    for i:= 0 to Book.Nodes.Count - 1 do
    begin
      N:= Book.Nodes[i];
      Line:= N.Emit; // a freshly parsed node is not Dirty: this is the line verbatim
      if N.Kind = rnkConvert then
      begin
        SetLength(ABlocks, Length(ABlocks) + 1);
        Cur:= High(ABlocks);
        ABlocks[Cur].Key          := Line;
        ABlocks[Cur].Job.FromType := Trim(N.FromType);
        ABlocks[Cur].Job.ToType   := Trim(N.ToType);
        ABlocks[Cur].Job.FirstLine:= i + 1;
        ABlocks[Cur].Job.LastLine := i + 1;
        ABlocks[Cur].Text         := Line;
      end
      else if Cur >= 0 then
      begin
        ABlocks[Cur].Text         := ABlocks[Cur].Text + CRLF + Line;
        ABlocks[Cur].Job.LastLine := i + 1;
        if N.Kind = rnkApply then
          ABlocks[Cur].Applies:= ABlocks[Cur].Applies + [UpperCase(Trim(N.ApplyName))];
      end;
      if N.Kind = rnkMapping then
      begin
        M:= FindMap(AMaps, UpperCase(Trim(N.MapName)));
        if M < 0 then
        begin
          SetLength(AMaps, Length(AMaps) + 1);
          M:= High(AMaps);
          AMaps[M].Name:= UpperCase(Trim(N.MapName));
        end;
        AMaps[M].Text := AMaps[M].Text + Line + CRLF;
        AMaps[M].Lines:= AMaps[M].Lines + [i + 1];
      end;
    end; // for
  finally
    Book.Free;
  end; // try

  // A header repeated in one book still pairs up with its old self, in order:
  // the key is the header line plus how many identical headers came before it.
  // Counted from the right, so each comparison is against an unsuffixed key.
  for i:= High(ABlocks) downto 0 do
  begin
    M:= 0;
    for k:= 0 to i - 1 do
      if ABlocks[k].Key = ABlocks[i].Key then
        Inc(M);
    ABlocks[i].Key:= ABlocks[i].Key + #0 + IntToStr(M);
    ABlocks[i].Job.Key:= ABlocks[i].Key;
  end;

  for i:= 0 to High(ABlocks) do
    for Line in ABlocks[i].Applies do
    begin
      M:= FindMap(AMaps, Line);
      if M >= 0 then
        ABlocks[i].Job.MappingLines:= ABlocks[i].Job.MappingLines + AMaps[M].Lines;
    end;
end; // procedure

function IsJob(const AJob: TValidateJob): Boolean;
begin
  Result:= (AJob.FromType <> '') and (AJob.ToType <> '');
end;

function IsValidateNoise(const ALine: string): Boolean;
var
  T: string;
begin
  T:= Trim(ALine);
  // "resolver: edges were derived by ..." is the engine's advisory about the
  // library index's resolve stamp -- about the DB, never about the book.
  // "NOTE: --from and --to not both given -- the book was PARSED only; ..." (engine
  // 1.26.x, stderr, every syntax-only pass) is information about the pass, not a
  // diagnostic; FATAL / ERROR lines stay errors.
  Result:= (T = '') or SameText(T, 'OK') or T.StartsWith('(loaded defaults from', True) or T.StartsWith('resolver:', True)
    or T.StartsWith(NOTE_PREFIX); // case-SENSITIVE: the engine writes it upper-case
end;

function ParseValidateOutput(const AOutput: string): TArray<TValidateDiag>;
var
  Raw  : string       ;
  T    : string       ;
  Rest : string       ;
  ColonP: Integer     ;
  LineNo: Integer     ;
  D    : TValidateDiag;
begin
  Result:= nil;
  for Raw in AOutput.Replace(CRLF, #10).Split([#10]) do
  begin
    if IsValidateNoise(Raw) then
      Continue;
    T:= Trim(Raw);
    D:= Default(TValidateDiag);
    D.Text:= T;
    ColonP:= Pos(':', T);
    if T.StartsWith(LINE_PREFIX, True) and (ColonP > Length(LINE_PREFIX) + 1)
       and TryStrToInt(Copy(T, Length(LINE_PREFIX) + 1, ColonP - Length(LINE_PREFIX) - 1), LineNo) and (LineNo > 0) then
    begin
      D.Line:= LineNo;
      Rest:= Trim(Copy(T, ColonP + 1, MaxInt));
      D.IsWarning:= Rest.StartsWith(WARNING_PREFIX, True);
    end
    else
      D.IsWarning:= T.StartsWith(WARNING_PREFIX, True); // FATAL / ERROR / anything else: an error
    Result:= Result + [D];
  end;
end; // function

function BlockJobs(const AText: string): TArray<TValidateJob>;
var
  Blocks: TArray<TBlockScan>;
  Maps  : TArray<TMapScan>  ;
  B     : TBlockScan        ;
begin
  Result:= nil;
  ScanText(AText, Blocks, Maps);
  for B in Blocks do
    if IsJob(B.Job) then
      Result:= Result + [B.Job];
end;

function InKeys(const AKeys: TArray<string>; const AKey: string): Boolean;
var
  K: string;
begin
  for K in AKeys do
    if K = AKey then
      Exit(True);
  Result:= False;
end;

function ChangedBlockJobs(const AOldText, ANewText: string; const APending: TArray<string>): TArray<TValidateJob>;
var
  OldBlocks: TArray<TBlockScan>;
  OldMaps  : TArray<TMapScan>  ;
  NewBlocks: TArray<TBlockScan>;
  NewMaps  : TArray<TMapScan>  ;
  B        : TBlockScan        ;
  O        : TBlockScan        ;
  Name     : string            ;
  Found    : Boolean           ;
  Changed  : Boolean           ;
begin
  Result:= nil;
  ScanText(AOldText, OldBlocks, OldMaps);
  ScanText(ANewText, NewBlocks, NewMaps);
  for B in NewBlocks do
  begin
    if not IsJob(B.Job) then
      Continue;
    Found:= False;
    Changed:= True;
    for O in OldBlocks do
      if O.Key = B.Key then
      begin
        Found:= True;
        Changed:= O.Text <> B.Text;
        Break;
      end;
    if Found and not Changed and InKeys(APending, B.Key) then
      Changed:= True; // its last validation was cancelled: still owed
    if Found and not Changed then
      for Name in B.Applies do
        if MapText(OldMaps, Name) <> MapText(NewMaps, Name) then
        begin
          Changed:= True;
          Break;
        end;
    if Changed then
      Result:= Result + [B.Job];
  end; // for
end; // function

function NextPending(const APending: TArray<string>; const AJobs: TArray<TValidateJob>; const AResult: TScopedValidation): TArray<string>;
var
  Done: TArray<string>;
  K   : string        ;
  i   : Integer       ;
begin
  Done:= nil;
  Result:= nil;
  for i:= 0 to High(AJobs) do
    if (i <= High(AResult.JobDone)) and AResult.JobDone[i] then
      Done:= Done + [AJobs[i].Key]
    else if not InKeys(Result, AJobs[i].Key) then
      Result:= Result + [AJobs[i].Key];
  for K in APending do
    if not InKeys(Done, K) and not InKeys(Result, K) then
      Result:= Result + [K];
end; // function

function JobAtLine(const AText: string; AHeaderLine: Integer; out AJob: TValidateJob): Boolean;
var
  Blocks: TArray<TBlockScan>;
  Maps  : TArray<TMapScan>  ;
  B     : TBlockScan        ;
begin
  AJob:= Default(TValidateJob);
  ScanText(AText, Blocks, Maps);
  for B in Blocks do
    if B.Job.FirstLine = AHeaderLine then
    begin
      if not IsJob(B.Job) then
        Exit(False);
      AJob:= B.Job;
      Exit(True);
    end;
  Result:= False;
end;

function DiagsForJob(const ADiags: TArray<TValidateDiag>; const AJob: TValidateJob): TArray<TValidateDiag>;
var
  D   : TValidateDiag;
  L   : Integer      ;
  Keep: Boolean      ;
begin
  Result:= nil;
  for D in ADiags do
  begin
    Keep:= (D.Line = 0) or ((D.Line >= AJob.FirstLine) and (D.Line <= AJob.LastLine));
    if not Keep then
      for L in AJob.MappingLines do
        if L = D.Line then
        begin
          Keep:= True;
          Break;
        end;
    if Keep then
      Result:= Result + [D];
  end;
end; // function

procedure AddUnique(var ADiags: TArray<TValidateDiag>; const AAdd: TArray<TValidateDiag>);
var
  D    : TValidateDiag;
  X    : TValidateDiag;
  Found: Boolean      ;
begin
  for D in AAdd do
  begin
    Found:= False;
    for X in ADiags do
      if (X.Line = D.Line) and (X.Text = D.Text) then
      begin
        Found:= True;
        Break;
      end;
    if not Found then
      ADiags:= ADiags + [D];
  end;
end; // procedure

function IsCancelled(const ACancelled: TCancelledFn): Boolean;
begin
  Result:= Assigned(ACancelled) and ACancelled();
end;

function RunScopedValidation(const AText: string; const AJobs: TArray<TValidateJob>; const AValidate: TValidateFn; const ACancelled: TCancelledFn): TScopedValidation;
var
  i: Integer      ;
  D: TValidateDiag;
begin
  Result:= Default(TScopedValidation);
  SetLength(Result.JobDiags, Length(AJobs));
  SetLength(Result.JobDone, Length(AJobs));
  // A pass is done only when no cancel came before OR during it: a cancel kills
  // the engine mid-run, so its output is partial and must not replace any mark.
  if not IsCancelled(ACancelled) then
  begin
    var LOut: string:= AValidate(AText, '', '');
    if not IsCancelled(ACancelled) then
    begin
      Result.Syntax:= ParseValidateOutput(LOut);
      Result.SyntaxDone:= True;
      for i:= 0 to High(AJobs) do
      begin
        if IsCancelled(ACancelled) then
          Break;
        LOut:= AValidate(AText, AJobs[i].FromType, AJobs[i].ToType);
        if IsCancelled(ACancelled) then
          Break;
        Result.JobDiags[i]:= DiagsForJob(ParseValidateOutput(LOut), AJobs[i]);
        Result.JobDone[i]:= True;
      end;
    end;
  end;
  Result.Cancelled:= not Result.SyntaxDone;
  for i:= 0 to High(AJobs) do
    if not Result.JobDone[i] then
    begin
      Result.Cancelled:= True;
      Result.NotChecked:= Result.NotChecked + [AJobs[i].FromType];
    end;
  AddUnique(Result.Kept, Result.Syntax);
  for i:= 0 to High(Result.JobDiags) do
    AddUnique(Result.Kept, Result.JobDiags[i]);
  for D in Result.Kept do
    if D.IsWarning then
      Inc(Result.Warnings)
    else
      Inc(Result.Errors);
end; // function

function CompletedVerdict(const AResult: TScopedValidation): string; forward;

function ValidateVerdict(const AResult: TScopedValidation): string;
begin
  if not AResult.Cancelled then
    Exit(CompletedVerdict(AResult));
  Result:= Format('cancelled -- %d changed block(s) not checked', [Length(AResult.NotChecked)]);
  if Length(AResult.NotChecked) > 0 then
    Result:= Result + ': ' + string.Join(', ', AResult.NotChecked);
  if not AResult.SyntaxDone then
    Result:= Result + '; syntax not checked'
  else
    Result:= Result + '; checked so far: ' + CompletedVerdict(AResult);
end; // function

function CompletedVerdict(const AResult: TScopedValidation): string;
var
  D: TValidateDiag;
begin
  if AResult.Errors = 0 then
  begin
    if AResult.Warnings = 0 then
      Exit('OK');
    Exit(Format('OK, %d warning(s) -- see marked rules', [AResult.Warnings]));
  end;
  Result:= '';
  for D in AResult.Kept do
    if not D.IsWarning then
    begin
      Result:= D.Text;
      Break;
    end;
  if Length(AResult.Kept) > 1 then
    Result:= Result + Format(' (+%d more)', [Length(AResult.Kept) - 1]);
  Result:= Result + ' -- see marked rules';
end; // function

procedure RemoveMarks(ANode: TRuleNode; AFromSyntax: Boolean);
var
  Kept: TArray<TRuleMark>;
  M   : TRuleMark        ;
begin
  Kept:= nil;
  for M in ANode.Marks do
    if M.FromSyntax <> AFromSyntax then
      Kept:= Kept + [M];
  ANode.Marks:= Kept;
end;

procedure AddMarks(const ALineNodes: TArray<TRuleNode>; const ADiags: TArray<TValidateDiag>; AFromSyntax: Boolean);
var
  D    : TValidateDiag;
  M    : TRuleMark    ;
  N    : TRuleNode    ;
  Found: Boolean      ;
begin
  for D in ADiags do
  begin
    if (D.Line < 1) or (D.Line > Length(ALineNodes)) then
      Continue; // a line-0 diagnostic reaches the status line, not a rule
    N:= ALineNodes[D.Line - 1];
    Found:= False;
    for M in N.Marks do
      if M.Text = D.Text then
      begin
        Found:= True;
        Break;
      end;
    if Found then
      Continue;
    M:= Default(TRuleMark);
    M.Text      := D.Text;
    M.IsWarning := D.IsWarning;
    M.FromSyntax:= AFromSyntax;
    N.Marks:= N.Marks + [M];
  end; // for
end; // procedure

procedure ApplyValidateMarks(const ABookNodes, ALineNodes: TArray<TRuleNode>; const AJobs: TArray<TValidateJob>; const AResult: TScopedValidation);
var
  N   : TRuleNode   ;
  Job : TValidateJob;
  L   : Integer     ;
  MapL: Integer     ;
  i   : Integer     ;
begin
  if AResult.SyntaxDone then
    for N in ABookNodes do
      RemoveMarks(N, True);
  for i:= 0 to High(AJobs) do
  begin
    if (i > High(AResult.JobDone)) or not AResult.JobDone[i] then
      Continue; // not validated: its block keeps the marks it had
    Job:= AJobs[i];
    for L:= Job.FirstLine to Job.LastLine do
      if (L >= 1) and (L <= Length(ALineNodes)) then
        RemoveMarks(ALineNodes[L - 1], False);
    for MapL in Job.MappingLines do
      if (MapL >= 1) and (MapL <= Length(ALineNodes)) then
        RemoveMarks(ALineNodes[MapL - 1], False);
  end;
  AddMarks(ALineNodes, AResult.Syntax, True);
  for i:= 0 to High(AResult.JobDiags) do
    AddMarks(ALineNodes, AResult.JobDiags[i], False);
end; // procedure

function BlockMarkNodes(ABook: TRuleBook; AHeaderIdx: Integer): TArray<TRuleNode>;
var
  L: TList<TRuleNode>;
  N: TRuleNode       ;
  X: TRuleNode       ;
begin
  if (AHeaderIdx < 0) or (AHeaderIdx >= ABook.Nodes.Count) or (ABook.Nodes[AHeaderIdx].Kind <> rnkConvert) then
    Exit(nil);
  L:= TList<TRuleNode>.Create;
  try
    L.Add(ABook.Nodes[AHeaderIdx]);
    for N in ABook.NodesInBlock(AHeaderIdx) do
      L.Add(N);
    for N in ABook.NodesInBlock(AHeaderIdx) do
      if N.Kind = rnkApply then
        for X in ABook.MappingNodesNamed(Trim(N.ApplyName)) do
          if not L.Contains(X) then
            L.Add(X);
    Result:= L.ToArray;
  finally
    L.Free;
  end; // try
end; // function

function MarksText(const ANodes: TArray<TRuleNode>; out AErrors, AWarnings: Integer): string;
var
  SB  : TStringBuilder;
  N   : TRuleNode     ;
  M   : TRuleMark     ;
  Pass: Boolean       ;
begin
  AErrors  := 0;
  AWarnings:= 0;
  SB:= TStringBuilder.Create;
  try
    for Pass in [False, True] do // errors first, then warnings
      for N in ANodes do
        for M in N.Marks do
          if M.IsWarning = Pass then
          begin
            if Pass then
              Inc(AWarnings)
            else
              Inc(AErrors);
            if SB.Length > 0 then
              SB.Append(CRLF);
            SB.Append(M.Text);
          end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end; // try
end; // function

function MarkerText(AErrors, AWarnings: Integer): string;
begin
  if (AErrors > 0) and (AWarnings > 0) then
    Result:= Format('%d err, %d warn', [AErrors, AWarnings])
  else if AErrors > 0 then
    Result:= Format('%d err', [AErrors])
  else if AWarnings > 0 then
    Result:= Format('%d warn', [AWarnings])
  else
    Result:= '';
end;

end.
