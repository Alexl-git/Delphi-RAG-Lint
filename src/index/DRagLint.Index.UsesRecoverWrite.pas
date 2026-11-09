unit DRagLint.Index.UsesRecoverWrite;

{ Lane 149-HW: the WRITE path of `uses-recover` (spec docs\superpowers\specs\2026-11-08-uses-recover.md,
  "The write path" and "149 HW: as built"). Turns the units the read verb recovered from vendor
  C++Builder headers into index rows: one synthetic files row per header (language 'hpp'), its
  #include lines as unit_uses rows (section interface, origin_path = the header), then the
  unit-uses resolve pass, whose rule C binds the project's rows to those headers. Owner ruling x2:
  no .dcu is read. Also the one #include parser both the read and the write side use. }

interface

uses
  DRagLint.Storage.SQLite;

type
  /// <summary>One `#include &lt;X.hpp&gt;` line of a C++Builder header.</summary>
  THppInclude = record
    UnitName: string;  // X as written
    Line    : Integer; // 1-based line of the #include
    Col     : Integer; // 1-based column of the '#'
    EndCol  : Integer; // 1-based column just past the closing '>' or '"'
  end;

  /// <summary>One recovered unit to store: its canonical name and the header it came from.</summary>
  TRecoveredHeader = record
    UnitName  : string;
    HeaderPath: string;
  end;

/// <summary>The includes of a C++Builder header, in file order.</summary>
/// <param name="pText">The whole .hpp text.</param>
/// <returns>One entry per `#include &lt;X.hpp&gt;` or `#include "X.hpp"` line, with its position;
/// other includes are skipped. No #if evaluation (headers are trusted as generated).</returns>
function ParseHppIncludeLines(const pText: string): TArray<THppInclude>;

/// <summary>True for System and SysInit, which every unit uses implicitly; uses-recover drops them.</summary>
/// <param name="pName">A unit name.</param>
/// <returns>True when pName is System or SysInit (case-insensitive).</returns>
function IsImplicitUnit(const pName: string): Boolean;

/// <summary>Stores the recovered headers in pStore and re-runs the unit-uses resolve pass.</summary>
/// <param name="pStore">A WRITABLE store whose schema is current. Caller owns it.</param>
/// <param name="pHeaders">The units with a header; every other header row the store holds is removed.</param>
/// <param name="pUsesRows">Receives the number of unit_uses rows written for the headers.</param>
/// <returns>The number of header files rows written.</returns>
/// <exception cref="Exception">A header that cannot be read, or any SQLite error (the row
/// transaction is rolled back; see TSQLiteSymbolStore.ReplaceHeaderUnits).</exception>
/// <remarks>Idempotent: the same pHeaders give the same rows. Each header's rows are its
/// includes minus System, SysInit and the unit itself -- exactly the read verb's edges. Not
/// thread-safe.</remarks>
function WriteRecoveredHeaders(const pStore: TSQLiteSymbolStore; const pHeaders: TArray<TRecoveredHeader>;
  out pUsesRows: Integer): Integer;

implementation

uses
  System.SysUtils, System.IOUtils, System.Hash, System.RegularExpressions,
  DRagLint.Core.Model, DRagLint.Core.FileTime;

const
  CIncludePattern = '^[ \t]*(#include[ \t]*[<"]([^<>"]+)\.hpp[>"])';
  CGroupWhole = 1; // the directive, '#' to the closing bracket
  CGroupName = 2;  // the unit name

function ParseHppIncludeLines(const pText: string): TArray<THppInclude>;
var
  LMatch: TMatch;
  LInc: THppInclude;
  LPos, LLine, LLineStart: Integer;
begin
  Result:= nil;
  LPos:= 1;
  LLine:= 1;
  LLineStart:= 1;
  for LMatch in TRegEx.Matches(pText, CIncludePattern, [roMultiLine, roIgnoreCase]) do
  begin
    { Matches come in text order: count the line breaks between the last match and this one. }
    while LPos < LMatch.Groups[CGroupWhole].Index do
    begin
      if pText[LPos] = #10 then
      begin
        Inc(LLine);
        LLineStart:= LPos + 1;
      end;
      Inc(LPos);
    end;
    LInc.UnitName:= LMatch.Groups[CGroupName].Value;
    LInc.Line:= LLine;
    LInc.Col:= LMatch.Groups[CGroupWhole].Index - LLineStart + 1;
    LInc.EndCol:= LInc.Col + LMatch.Groups[CGroupWhole].Length;
    Result:= Result + [LInc];
  end;
end;

function IsImplicitUnit(const pName: string): Boolean;
begin
  Result:= SameText(pName, 'System') or SameText(pName, 'SysInit');
end;

{ The files + unit_uses rows of one header. }
function HeaderRow(const pHeader: TRecoveredHeader): THeaderUnitRow;
var
  LText: string;
  LInc: THppInclude;
  LUse: TUnitUse;
begin
  LText:= TFile.ReadAllText(pHeader.HeaderPath);
  Result.Path:= pHeader.HeaderPath;
  Result.MTime:= FileMTimeUnix(pHeader.HeaderPath);
  Result.Sha256:= THashSHA2.GetHashString(LText);
  Result.Entries:= nil;
  for LInc in ParseHppIncludeLines(LText) do
  begin
    if IsImplicitUnit(LInc.UnitName) or SameText(LInc.UnitName, pHeader.UnitName) then
      Continue;
    LUse:= Default(TUnitUse);
    LUse.UnitName:= LInc.UnitName;
    LUse.Section:= uusInterface;
    LUse.StartLine:= LInc.Line;
    LUse.StartCol:= LInc.Col;
    LUse.EndLine:= LInc.Line;
    LUse.EndCol:= LInc.EndCol;
    LUse.OriginPath:= pHeader.HeaderPath;
    Result.Entries:= Result.Entries + [LUse];
  end;
end;

function WriteRecoveredHeaders(const pStore: TSQLiteSymbolStore; const pHeaders: TArray<TRecoveredHeader>;
  out pUsesRows: Integer): Integer;
var
  LRows: TArray<THeaderUnitRow>;
  LHeader: TRecoveredHeader;
begin
  LRows:= nil;
  for LHeader in pHeaders do
    LRows:= LRows + [HeaderRow(LHeader)];
  pUsesRows:= pStore.ReplaceHeaderUnits(LRows);
  pStore.ResolveUnitUseTargets;
  Result:= Length(LRows);
end;

end.
