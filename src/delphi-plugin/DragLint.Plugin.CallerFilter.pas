unit DragLint.Plugin.CallerFilter;

{ Chooses which "CALLED FROM" rows belong to the symbol actually hovered.

  WHY THIS EXISTS (2026-08-18). Hovering `TEurekaExceptionInfo.Create` listed
  55 call sites: TMemIniFile.Create, TTimer.Create, TStringList.Create,
  Exception.Create -- every `Create` in the project except the one asked about.

  The old code was already trying to prevent that. It filtered the name-matched
  rows down to source lines qualified by the target's own class, and then, when
  that filter matched nothing, FELL BACK TO THE UNFILTERED LIST. DataCopy never
  constructs TEurekaExceptionInfo, so the filter correctly matched zero -- and
  the fallback then presented every unrelated Create as a caller.

  That is the failure worth naming: a fail-open fallback produces its most
  confident garbage exactly when the precise answer is EMPTY. "No call sites"
  is a true and useful answer; 55 wrong ones train the user to distrust the
  panel entirely.

  The fallback was not gratuitous, which is why it cannot simply be deleted. A
  method called through an instance variable reads `Thing.DoStuff(...)`, not
  `TThing.DoStuff(...)`, so the class-qualified filter misses genuine callers;
  the fallback existed to avoid hiding those.

  The way out is to stop guessing from source text alone. `find-callers
  --resolved` returns edges keyed by TARGET_QNAME -- an exact symbol identity,
  not a name match. That answers the question the text filter could only
  approximate, and it also distinguishes the two cases the old code conflated:

    * the name resolves to other symbols but never to ours  -> genuinely no
      callers; return nothing.
    * the name resolves NOWHERE (the resolver is lossy for qualified
      constructors and generic `TFoo<T>.Create`) -> we know nothing, so the
      old permissive behaviour is still the least-bad answer.

  Kept free of ToolsAPI so a console harness can link and test it, following
  DRagLint.Plugin.DbProbe. }

interface

uses
  System.SysUtils;

type
  /// <summary>One candidate call site, from either the resolved-edge query or
  /// the name index.</summary>
  /// <remarks>TargetQName is populated only for resolved rows; name-index rows
  /// leave it empty, and CodeText is populated only for name-index rows.</remarks>
  TDLCallerRow = record
    FilePath   : string ;
    Line       : Integer;
    CodeText   : string ;   { source line, name-index rows only }
    TargetQName: string ;   { exact callee identity, resolved rows only }
  end;

  TDLCallerRows = TArray<TDLCallerRow>;

  /// <summary>Which branch produced the returned rows. Reported so the caller
  /// can log it and a test can assert the POLICY, not merely the row count --
  /// two branches can both legitimately return zero rows.</summary>
  TDLCallerSource = (
    csResolved,      { exact target_qname matches }
    csClassQualified,{ source line qualified by the target's own class }
    csNoneResolved,  { the name resolves elsewhere, never to us -> empty }
    csUnresolvedAll  { the name resolves nowhere -> permissive fallback }
  );

/// <summary>Maximum rows returned; the popup cannot usefully show more.</summary>
const
  DL_MAX_CALLERS = 200;

/// <summary>Picks the call sites belonging to ATargetQName.</summary>
/// <param name="AResolved">Rows from `find-callers --resolved` (any target).</param>
/// <param name="ANameRows">Rows from the name index, with CodeText filled.</param>
/// <param name="ATargetQName">Fully qualified name of the hovered symbol.</param>
/// <param name="AClassQual">"Class.Member" form used for the text filter.</param>
/// <param name="ASource">Which branch decided the result.</param>
/// <returns>De-duplicated by (file, line), capped at DL_MAX_CALLERS.</returns>
/// <remarks>Pure: no I/O, no globals. WHEN a resolved edge names ATargetQName
/// THE selection SHALL return only those rows. IF the name resolves to other
/// targets but never to ATargetQName THEN the selection SHALL return no rows
/// rather than every same-named row.</remarks>
function SelectCallers(const AResolved, ANameRows: TDLCallerRows;
  const ATargetQName, AClassQual: string; out ASource: TDLCallerSource): TDLCallerRows;

/// <summary>"Class.Member" for a dotted qualified name, else the name itself.</summary>
/// <remarks>Unit names are themselves dotted (DRagLint.LSP.Server.TLSPServer.HandleHover),
/// so this takes the LAST TWO segments rather than counting dots.</remarks>
function ClassQualifierOf(const AQName: string): string;

implementation

function ClassQualifierOf(const AQName: string): string;
var
  DotP: Integer;
  Head: Integer;
begin
  Result:= AQName;
  DotP:= LastDelimiter('.', AQName);
  if DotP <= 1 then Exit;
  Head:= LastDelimiter('.', Copy(AQName, 1, DotP - 1));
  if Head > 0 then Result:= Copy(AQName, Head + 1, MaxInt);
end;

function SameSite(const A, B: TDLCallerRow): Boolean;
begin
  Result:= (A.Line = B.Line) and SameText(A.FilePath, B.FilePath);
end;

function SameCallSite(const A, B: TDLCallerRow): Boolean;
{ Compares a name-index row (full path) against a resolved row (bare file name)
  by line plus BASE NAME. Comparing the paths whole would never match, and
  matching on line alone would pull in an unrelated file's line 120. }
begin
  Result:= (A.Line = B.Line) and
           SameText(ExtractFileName(A.FilePath), ExtractFileName(B.FilePath));
end;

function AppendUnique(var ADest: TDLCallerRows; const ARow: TDLCallerRow): Boolean;
var
  K: Integer;
begin
  Result:= False;
  if ARow.FilePath = '' then Exit;
  for K:= 0 to High(ADest) do
    if SameSite(ADest[K], ARow) then Exit;
  SetLength(ADest, Length(ADest) + 1);
  ADest[High(ADest)]:= ARow;
  Result:= True;
end;

function Capped(const ARows: TDLCallerRows): TDLCallerRows;
begin
  Result:= ARows;
  if Length(Result) > DL_MAX_CALLERS then SetLength(Result, DL_MAX_CALLERS);
end;

function SelectCallers(const AResolved, ANameRows: TDLCallerRows;
  const ATargetQName, AClassQual: string; out ASource: TDLCallerSource): TDLCallerRows;
var
  I   : Integer      ;
  J   : Integer      ;
  Acc : TDLCallerRows;
  Mine: TDLCallerRows;
begin
  SetLength(Acc, 0);

  { 1. Exact symbol identity. Nothing else is as trustworthy, so it wins.

    The resolved query reports a BARE FILE NAME and no source text, which is
    not enough to drive a clickable list, so the resolved rows are used as a
    (file, line) FILTER over the name-index rows -- those carry the full path
    and the code line. Only when there are no name rows to filter (the caller
    skipped that second query) are the resolved rows returned directly. }
  SetLength(Mine, 0);
  if Trim(ATargetQName) <> '' then
    for I:= 0 to High(AResolved) do
      if SameText(Trim(AResolved[I].TargetQName), Trim(ATargetQName)) then
        AppendUnique(Mine, AResolved[I]);

  if Length(Mine) > 0 then
  begin
    for I:= 0 to High(ANameRows) do
      for J:= 0 to High(Mine) do
        if SameCallSite(ANameRows[I], Mine[J]) then
        begin
          AppendUnique(Acc, ANameRows[I]);
          Break;
        end;
    { No name row covered them -- show the resolved rows rather than nothing.
      Degraded (bare file name, no code text) but still the right symbol. }
    if Length(Acc) = 0 then
      for I:= 0 to High(Mine) do AppendUnique(Acc, Mine[I]);
    ASource:= csResolved;
    Exit(Capped(Acc));
  end;

  { 2. Source line qualified by the target's own class -- "TGroup.Create". Text,
       but SPECIFIC text: it cannot match another class's Create. }
  if Trim(AClassQual) <> '' then
    for I:= 0 to High(ANameRows) do
      if Pos(AClassQual, ANameRows[I].CodeText) > 0 then
        AppendUnique(Acc, ANameRows[I]);
  if Length(Acc) > 0 then
  begin
    ASource:= csClassQualified;
    Exit(Capped(Acc));
  end;

  { 3. The resolver knew this name and never pointed it at us. That is a real
       answer -- "nothing calls this" -- and it is the case that used to dump
       every same-named row into the panel. }
  if Length(AResolved) > 0 then
  begin
    ASource:= csNoneResolved;
    SetLength(Result, 0);
    Exit;
  end;

  { 4. The resolver produced nothing for this name at all, so we have no
       evidence either way. Stay permissive rather than assert a false zero. }
  for I:= 0 to High(ANameRows) do
    AppendUnique(Acc, ANameRows[I]);
  ASource:= csUnresolvedAll;
  Result:= Capped(Acc);
end;

end.
