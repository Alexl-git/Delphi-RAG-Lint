unit ConvRules.MigrateRun;

{ A4 #migrate slice 1 (D8 = B): which of a Convert run's migrate-check items belong to the
  book open in the editor. Pure. A unit of its own because it reads the runner's rows
  (ConvRules.ConvertRunner), and the runner already uses ConvRules.Migrate for its notes. }

interface

uses
  ConvRules.ConvertRun
  , ConvRules.ConvertRunner
  ;

/// <summary>The migrate-check items of a run's CONVERTED rows whose book is ABookPath (D8 B:
/// the host marks the open book's lines with the rule-level ones, AddMigrateCheckMarks).</summary>
/// <param name="ARows">The run's rows.</param>
/// <param name="ABookPath">The open book's path; compared as a file (ExpandFileName, '/' as '\', SameFileName).</param>
/// <returns>Book order of the rows; [] when no row of that book converted.</returns>
function MigrateChecksForBook(const ARows: TArray<TConvertRow>; const ABookPath: string): TArray<TApplyItem>;

implementation

uses
  System.SysUtils
  ;

// One file, however spelt: ExpandFileName folds '..' and '/' to '\', SameFileName the case.
function SameFile(const A, B: string): Boolean;
begin
  Result:= SameFileName(ExpandFileName(A.Replace('/', '\')), ExpandFileName(B.Replace('/', '\')));
end;

function MigrateChecksForBook(const ARows: TArray<TConvertRow>; const ABookPath: string): TArray<TApplyItem>;
begin
  Result:= nil;
  for var LRow: TConvertRow in ARows do
    if (LRow.Status = csConverted) and SameFile(LRow.Book, ABookPath) then
      Result:= Result + LRow.Apply.MigrateChecks;
end;

end.