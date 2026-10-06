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
function EngineClassLookup(AEngine: TEngineAdapter; const ADb: string; const APairs: TArray<TTypePair>): TClassLookup;  // dl:ok unused-public-symbol@d8b1 -- REVIEWED 2026-10-05 called by the model tests (lookup.live.*, coderefs.live.*) only until the C8 Convert-tab task (Task 6) passes it to AnalyzeUnit; drop this marker when it does

/// <summary>A TCodeUseLookup over the project index: ListCodeRefs mapped through
/// CodeUseName, one TCodeUse per ref row (Line = refs.start_line).</summary>
/// <param name="AEngine">The adapter to ask; must outlive the returned lookup. Not owned.</param>
/// <param name="ADb">The PROJECT index only.</param>
/// <returns>A lookup answering False (unknown, never "no uses") when the engine could
/// not answer, the answer was stale, or the unit is not in the index; AError then
/// holds the engine-side failure text.</returns>
function EngineCodeUses(AEngine: TEngineAdapter; const ADb: string): TCodeUseLookup;  // dl:ok unused-public-symbol@b06b -- REVIEWED 2026-10-05 called by the model tests (coderefs.live.analysis) only until the C8 Convert-tab task (Task 6) passes it to AnalyzeUnit; drop this marker when it does

implementation

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
