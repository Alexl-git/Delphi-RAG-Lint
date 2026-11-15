unit DRagLint.V151.MEM;

{ Wave v151 lane MEM -- memory and string-pointer rules (PChar of temporaries, raw memory of managed types, leaks of raw memory and handles, byte vs char counts).
  Scaffold created EMPTY by lane FRAME; lane MEM owns this unit, its
  DRagLint.V151.MEM.Support helpers and DRagLint.Fix.V151.MEM. Called only by
  DRagLint.V151.Dispatch. How-to: C:\TEMP\claude\lanes\v151\FRAME\HOWTO-RULE-LANE.md. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

type
  /// <summary>Checker entry points of v151 lane MEM; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.</remarks>
  TV151MEMRules = class
  public
    /// <summary>Declares every rule id this lane may emit: new ids (V151Rule) and host ids of in-place expansions (V151Host).</summary>
    /// <param name="ADecls">List to append to; owned by the caller.</param>
    /// <remarks>Called ONCE at start-up (unit initialization of DRagLint.V151.Dispatch); must not touch files or stores.</remarks>
    class procedure Catalog(const ADecls: TList<TV151RuleDecl>); static;
    /// <summary>Per-file check of one .pas (parse tree, index, library).</summary>
    /// <param name="ACtx">The file being linted; Store / LibStore may be nil.</param>
    /// <returns>Findings; nil when none.</returns>
    class function CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the .pas unit's sibling form file.</summary>
    /// <param name="ACtx">The file being linted; ACtx.DfmPath is not empty when this is called.</param>
    /// <returns>Findings (FilePath may be the .dfm); nil when none.</returns>
    class function CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the raw bytes of the .pas and of its sibling .dfm, before any decoding.</summary>
    /// <param name="ACtx">The file being linted.</param>
    /// <param name="AFilePath">The file the bytes come from (ACtx.Path or ACtx.DfmPath).</param>
    /// <param name="ABytes">The file content exactly as on disk.</param>
    /// <returns>Findings; nil when none.</returns>
    class function CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>; static;
    /// <summary>Project-wide check, lint-all only, run once after the per-file loop.</summary>
    /// <param name="ACtx">The project; Store is not nil.</param>
    /// <returns>Findings; nil when none.</returns>
    class function CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>; static;
  end;

implementation

uses
  DRagLint.V151.MEM.Support
  , DRagLint.Diagnostics.ParseCache
  ;

{ Rules of the lane (behaviour: DRagLint.V151.MEM.Support):
  pchar-of-temporary -- PChar / PWideChar / PAnsiChar of a concatenation with a literal or of a
    string-function result, STORED by an assignment or POSTED (PostMessage family). Passed straight
    to a synchronous call it is silent: the temporary lives until the statement ends.
  createprocess-readonly-commandline -- CreateProcess(W) arg 2, ..AsUser arg 3, ..WithTokenW arg 4,
    ..WithLogonW arg 6 that may point at read-only memory: a literal, a const, 'lit' + one value,
    a by-value / const string parameter, or a local last assigned one of those without UniqueString.
    The Ansi version copies the buffer and stays silent.
  managed-type-raw-memory -- FillChar / ZeroMemory / FillMemory / Move / CopyMemory / GetMem /
    FreeMem / ReallocMem on a variable (or pointee) whose type holds strings, interfaces, variants
    or dynamic arrays; record fields come from the file, then the project / library index. Silent
    when the routine also calls Initialize / Finalize on it, and for FillChar(V, SizeOf(V)) over a
    directly managed V (the host wrong-size-memory-op reports that one).
  raw-memory-leak / handle-leak -- a LOCAL that receives memory (GetMem, New, AllocMem, GetMemory,
    StrAlloc, StrNew) or a handle (CreateFile, LoadLibrary, GetDC, FindFirst(SR), RegOpenKeyEx, ..)
    and is never released nor handed on (assigned elsewhere, returned, passed to Add / Insert /
    Create / Set.. / a routine whose name says free / release / close) anywhere in the routine.
  char-count-as-bytes -- Length(S) (+/- n) of a UTF-16 string, or StrLen(P) of a PChar, as the byte
    count of Move / CopyMemory / CompareMem / FillChar / ReadBuffer / WriteBuffer / BlockRead /
    ReadFile / WriteFile / GetMem(PChar) whose buffer is S / P. Split from wrong-size-memory-op
    (own id, no autofix): the host's fix is capture-bound and the host keeps its exact shapes.
  unsafe-string-api (expansion) -- an xxxA Windows API fed PAnsiChar(AnsiString(S)) of a UTF-16 S. }

/// <summary>Declares the six new ids of the lane and the host id unsafe-string-api.</summary>
/// <param name="ADecls">List to append to; owned by the caller.</param>
class procedure TV151MEMRules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule('pchar-of-temporary', 'bug-patterns', 'warning', 'PChar of a temporary string is stored or posted'));
  ADecls.Add(V151Rule('createprocess-readonly-commandline', 'bug-patterns', 'warning', 'CreateProcess with a read-only command line'));
  ADecls.Add(V151Rule('managed-type-raw-memory', 'bug-patterns', 'warning', 'FillChar, Move or GetMem on a managed type'));
  ADecls.Add(V151Rule('raw-memory-leak', 'resource-lifetime', 'warning', 'GetMem or New without release'));
  ADecls.Add(V151Rule('handle-leak', 'resource-lifetime', 'warning', 'Windows handle is not closed'));
  ADecls.Add(V151Rule('char-count-as-bytes', 'bug-patterns', 'warning', 'Character count used as a byte count'));
  ADecls.Add(V151Host('unsafe-string-api'));
end;

class function TV151MEMRules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
var
  PF : TParsedFile;
  Run: TMemRun;
  Ctx: TV151FileCtx;
begin
  Result:= nil;
  PF:= TAstParseCache.Get(ACtx.Path);
  if PF.Tree = nil then Exit;
  Ctx:= ACtx;
  Run:= TMemRun.Create(ACtx.Path, PF.Src, ACtx.Store, ACtx.LibStore,
    function(S: string): Boolean begin Result:= Ctx.Wants(S); end);
  try
    Result:= Run.Run(PF.Tree.RootNode);
  finally
    Run.Free;
  end;
end;

class function TV151MEMRules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@51ad -- REVIEWED 2026-11-14 v151 MEM: signature fixed by the v151 lane frame hook; this lane has no DFM / raw-byte / project check
begin
  Result:= nil;
end;

class function TV151MEMRules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@808e -- REVIEWED 2026-11-14 v151 MEM: signature fixed by the v151 lane frame hook; this lane has no DFM / raw-byte / project check
begin
  Result:= nil;
end;

class function TV151MEMRules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@0db8 -- REVIEWED 2026-11-14 v151 MEM: signature fixed by the v151 lane frame hook; this lane has no DFM / raw-byte / project check
begin
  Result:= nil;
end;

end.
