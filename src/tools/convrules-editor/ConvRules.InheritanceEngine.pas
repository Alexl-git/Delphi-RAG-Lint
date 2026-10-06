unit ConvRules.InheritanceEngine;

{ C8: binds TEngineAdapter's project-index reads (LookupClass, ListClassFields,
  ListCodeRefs) to ConvRules.Inheritance's function types (TClassLookup,
  TCodeUseLookup). The ONE place that binding is made: the model tests drive it
  against a fixture index, and the Convert tab passes the same binders to
  AnalyzeUnit, so what the tests prove is what the editor runs. }

interface

uses
  ConvRules.Engine
  , ConvRules.Inheritance
  ;

/// <summary>A TClassLookup over the project index: LookupClass for the class's
/// declaring unit and first ancestor, then ListClassFields for the fields it declares
/// itself whose type is one of APairs' From types.</summary>
/// <param name="AEngine">The adapter to ask; must outlive the returned lookup. Not owned.</param>
/// <param name="ADb">The PROJECT index only -- never a library or another project's DB
/// (authority: a class not in it is outside).</param>
/// <param name="APairs">The checked books' pairs; their From types filter the fields.</param>
/// <returns>A lookup answering Found (exactly one declaring file), not Found (absent,
/// or ambiguous: two or more files), or Failed (the engine could not answer either
/// read; Found is then False and Error holds the engine's failure text, naming the DB).
/// The fields are read from the declaring file LookupClass found.</returns>
/// <remarks>Each call spawns up to two `sql` engine processes; wrap the result in
/// CachingLookup. Not thread-safe beyond what TEngineAdapter is.</remarks>
function EngineClassLookup(AEngine: TEngineAdapter; const ADb: string; const APairs: TArray<TTypePair>): TClassLookup;

/// <summary>A TCodeUseLookup over the project index: ListCodeRefs mapped through
/// CodeUseName, one TCodeUse per ref row (Line = refs.start_line).</summary>
/// <param name="AEngine">The adapter to ask; must outlive the returned lookup. Not owned.</param>
/// <param name="ADb">The PROJECT index only.</param>
/// <returns>A lookup answering False (unknown, never "no uses") when the engine could
/// not answer, the answer was stale, or the unit is not in the index; AError then
/// holds the engine-side failure text.</returns>
function EngineCodeUses(AEngine: TEngineAdapter; const ADb: string): TCodeUseLookup;

type
  /// <summary>Analyses a set of listed units (AnalyzeUnits with the pass's lookups bound).</summary>
  TUnitsAnalyzer = reference to function(const APaths: TArray<string>): TArray<TUnitInheritance>;

  /// <summary>Refreshes the project index (TEngineAdapter.IndexProject of the editor's OWN
  /// project, ProjectFileForDb of its DB); False with AError when it failed.</summary>
  TIndexRefresh = reference to function(out AError: string): Boolean;

/// <summary>PURE: True when AError is a C8 read's failure on a STALE index (the engine
/// marked the answer stale -- INDEX_STALE_MARKER), the one failure a reindex can fix.</summary>
/// <param name="AError">A TUnitInheritance.Error, or any engine failure text.</param>
/// <returns>Case-insensitive match on INDEX_STALE_MARKER.</returns>
function IsStaleIndexError(const AError: string): Boolean;

/// <summary>PURE: analyses APaths; when a unit is unknown because the index was STALE,
/// refreshes the index ONCE and analyses those units ONCE more.</summary>
/// <param name="APaths">Listed .pas paths.</param>
/// <param name="AAnalyze">The analysis pass (fresh caches per call).</param>
/// <param name="AReindex">The incremental reindex; called at most once, and only when a
/// unit came back stale.</param>
/// <returns>One analysis per path, APaths order. A unit still unknown after the retry
/// keeps the retry's Error; when the reindex itself failed the stale units are not
/// re-analysed and their Error gains '; reindex failed: &lt;why&gt;'.</returns>
function AnalyzeRetryingStale(const APaths: TArray<string>; const AAnalyze: TUnitsAnalyzer; const AReindex: TIndexRefresh): TArray<TUnitInheritance>;

implementation

uses
  System.StrUtils
  ;

function IsStaleIndexError(const AError: string): Boolean;
begin
  Result:= ContainsText(AError, INDEX_STALE_MARKER);
end;

function AnalyzeRetryingStale(const APaths: TArray<string>; const AAnalyze: TUnitsAnalyzer; const AReindex: TIndexRefresh): TArray<TUnitInheritance>;
var
  LStale  : TArray<string>;
  LAt     : TArray<Integer>;
  LRetry  : TArray<TUnitInheritance>;
  LError  : string;
begin
  Result:= AAnalyze(APaths);
  LStale:= nil;
  LAt   := nil;
  for var I: Integer:= 0 to High(Result) do
    if not Result[I].Known and IsStaleIndexError(Result[I].Error) then
    begin
      LStale:= LStale + [Result[I].UnitPas];
      LAt   := LAt + [I];
    end;
  if Length(LStale) = 0 then
    Exit;
  if not AReindex(LError) then
  begin
    for var I: Integer in LAt do
      Result[I].Error:= Result[I].Error + '; reindex failed: ' + LError;
    Exit;
  end;
  LRetry:= AAnalyze(LStale);
  for var I: Integer:= 0 to High(LAt) do
    if I <= High(LRetry) then
      Result[LAt[I]]:= LRetry[I];
end;

function EngineClassLookup(AEngine: TEngineAdapter; const ADb: string; const APairs: TArray<TTypePair>): TClassLookup;
var
  LFrom: TArray<string>;
begin
  LFrom:= nil;
  for var LPair: TTypePair in APairs do
    LFrom:= LFrom + [LPair.FromType];
  Result:= function(const AClassName: string): TClassInfo
    var
      LPath, LParent, LError: string;
      LFields               : TArray<TEngineField>;
      LDecl                 : TFieldDecl;
    begin
      Result:= Default(TClassInfo);
      case AEngine.LookupClass(ADb, AClassName, LPath, LParent, LError) of
        cloFound:
          if AEngine.ListClassFields(ADb, AClassName, LPath, LFrom, LFields, LError) then
          begin
            Result.Found      := True;
            Result.PasPath    := LPath;
            Result.ParentClass:= LParent;
            for var LField: TEngineField in LFields do
            begin
              LDecl.Name    := LField.Name;
              LDecl.TypeName:= LField.TypeName;
              Result.Fields := Result.Fields + [LDecl];
            end;
          end
          else
          begin
            Result.Failed:= True;
            Result.Error := LError;
          end;
        cloFailed:
        begin
          Result.Failed:= True;
          Result.Error := LError;
        end;
        cloAbsent, cloAmbiguous:
          Result.Found:= False;
      end; // case
    end;
end;

function EngineCodeUses(AEngine: TEngineAdapter; const ADb: string): TCodeUseLookup;
begin
  Result:= function(const AUnitPas, AClassName: string; out AUses: TArray<TCodeUse>; out AError: string): Boolean
    var
      LRefs: TArray<TEngineCodeRef>;
      LUse : TCodeUse;
    begin
      AUses := nil;
      Result:= AEngine.ListCodeRefs(ADb, AUnitPas, AClassName, LRefs, AError);
      for var LRef: TEngineCodeRef in LRefs do
      begin
        LUse.Name:= CodeUseName(LRef.Name, LRef.Receiver);
        LUse.Line:= LRef.Line;
        AUses    := AUses + [LUse];
      end;
    end;
end;

end.
