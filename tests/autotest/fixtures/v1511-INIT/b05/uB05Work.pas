unit uB05Work;

// Fixture (1.51.1 lane INIT, B05): the routines that touch the file system. Nothing here runs at init.

interface

type
  /// <summary>A hook: a routine passed as a value.</summary>
  TB05Hook = reference to procedure;

  /// <summary>A path reader: a function passed as a value.</summary>
  TB05Fn = reference to function(const pPath: string): string;

  /// <summary>Checks that read a file.</summary>
  TB05Checks = class
  public
    /// <summary>Reads a file.</summary>
    class procedure CheckFile; static;
    /// <summary>Reads the named file.</summary>
    /// <param name="pPath">The file.</param>
    /// <returns>Its text.</returns>
    class function ReadIt(const pPath: string): string; static;
  end;

/// <summary>Reads a file.</summary>
procedure WorkFile;

/// <summary>Keeps a hook for later.</summary>
/// <param name="pHook">The hook; not run here.</param>
procedure AddHook(const pHook: TB05Hook);

/// <summary>Keeps a reader for later.</summary>
/// <param name="pFn">The reader; not run here.</param>
procedure AddFn(const pFn: TB05Fn);

implementation

uses
  System.IOUtils;

var
  GHooks: TArray<TB05Hook>;
  GFns  : TArray<TB05Fn>;

class procedure TB05Checks.CheckFile;
begin
  Writeln(TFile.ReadAllText('b05.txt'));
end;

class function TB05Checks.ReadIt(const pPath: string): string;
begin
  Result:= TFile.ReadAllText(pPath);
end;

procedure WorkFile;
begin
  Writeln(TFile.ReadAllText('b05.txt'));
end;

procedure AddHook(const pHook: TB05Hook);
begin
  GHooks:= GHooks + [pHook];
end;

procedure AddFn(const pFn: TB05Fn);
begin
  GFns:= GFns + [pFn];
end;

end.
