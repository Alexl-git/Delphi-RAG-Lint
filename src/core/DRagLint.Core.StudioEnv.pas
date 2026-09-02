unit DRagLint.Core.StudioEnv;

{ THE ONE PLACE THIS REPO IS ALLOWED TO NAME A RAD STUDIO PATH.

  WHY THIS UNIT EXISTS
  --------------------
  Eight sites across four units named the Studio installation, and they did not
  agree on how to find it. Three separate strategies were in the tree at once:

    * env only            -- CLI.pas, check-unit: $BDS or a literal
    * registry then fixed -- LSP.Proxy.pas: RootDir or a literal
    * literal only        -- CompileCheck.pas, and the $(BDS) macro expansion

  Four of the eight stored a path they could have COMPOSED -- bin\rsvars.bat is
  the root plus a known suffix, and storing it separately means a machine with
  Studio somewhere else got the right root and the wrong rsvars.

  So: one accessor, and every caller composes from it with TPath.Combine. A
  second Studio literal anywhere in this repo is a defect, and
  hardcoded-absolute-path is what catches it.

  RESOLUTION ORDER, AND WHY THE FALLBACK IS EXISTENCE-CHECKED
  -----------------------------------------------------------
    1. $BDS      -- Embarcadero's own variable; rsvars.bat sets it, so anything
                    running inside a RAD build environment already has it.
    2. HKCU\Software\Embarcadero\BDS\37.0, value RootDir -- what the IDE itself
                    writes at install time.
    3. the single compiled-in fallback, ONLY IF THAT DIRECTORY EXISTS.

  Step 3 is the owner's ruling of 2026-09-02. An unconditional fallback is what
  the old code did, and it turns "Studio is not installed" into a wrong path
  handed to dcc, which then fails with a message about units rather than about
  Studio. Gating it on TDirectory.Exists keeps the tool working on a box with
  nothing configured -- the common case -- while making a genuinely absent
  Studio a loud, attributable error at the point of truth.

  Steps 1 and 2 are deliberately NOT existence-checked. Both are explicit
  statements of intent by the user or the installer; silently stepping past a
  wrong one to a different Studio would be worse than failing while naming it.

  PINNED TO 37.0
  --------------
  Delphi 13 Florence is the only Studio this product supports, and
  drag-lint-switch writes the same registry root. A version bump touches this
  unit and that one, deliberately. }

interface

uses
  System.SysUtils;

type
  /// <summary>Raised when no RAD Studio installation can be resolved from any
  /// of the three sources.</summary>
  /// <remarks>The message names all three sources and what was tried, because
  /// the whole point of raising here rather than degrading is that the person
  /// reading it can act on it.</remarks>
  EStudioNotFound = class(Exception);

  /// <summary>Resolves the RAD Studio 37.0 installation root and everything
  /// composed from it.</summary>
  /// <remarks>Stateless and thread-safe: every call re-reads the environment
  /// and the registry. Both are cheap and neither is called in a loop, so no
  /// cache is kept -- a cached root would go stale across an install without
  /// any way to notice.</remarks>
  TStudioEnv = class
  strict private
    const
      /// <summary>The IDE's own key; RootDir under it is written at install.</summary>
      REG_KEY = 'Software\Embarcadero\BDS\37.0';
      REG_VALUE = 'RootDir';
      /// <summary>The ONE Studio path literal in this repository. Every other
      /// Studio path is composed from TStudioEnv.Root.</summary>
      FALLBACK_ROOT = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'; // dl:ok hardcoded-absolute-path@fec3 -- the single fallback the owner ruled to keep, 2026-09-02; existence-checked before use, and the only Studio literal in the repo
    /// <summary>Reads HKCU RootDir, or '' if the key, the value or the read
    /// fails.</summary>
    /// <returns>The recorded installation root, or an empty string.</returns>
    /// <remarks>Never raises: a missing key is the normal state on a machine
    /// with no IDE, and the caller has a further source to try.</remarks>
    class function ReadRegistryRoot: string; static;
  public
    /// <summary>Resolves the Studio root without raising.</summary>
    /// <param name="ARoot">Receives the root with any trailing delimiter
    /// removed, or an empty string when the function returns False.</param>
    /// <param name="ADiagnostic">Receives a message naming every source that
    /// was tried, or an empty string on success. Suitable for printing
    /// verbatim.</param>
    /// <returns>True when a root was resolved.</returns>
    /// <remarks>For callers that own their own failure mode -- an exit code, a
    /// degraded-but-working path. Callers that simply cannot proceed should use
    /// <see cref="DRagLint.Core.StudioEnv.TStudioEnv.Root"/> instead.</remarks>
    class function TryRoot(out ARoot: string; out ADiagnostic: string): Boolean; static;
    /// <summary>The Studio root, or an empty string when none resolves.</summary>
    /// <returns>The root with no trailing path delimiter, or ''.</returns>
    /// <remarks>For the two callers that legitimately degrade: a $(BDS) macro
    /// expansion, where an empty root makes the path fail its own existence
    /// check and drop out, and a constructor that must not raise. Anywhere the
    /// absence is actually fatal, use
    /// <see cref="DRagLint.Core.StudioEnv.TStudioEnv.Root"/> so the failure
    /// names Studio.</remarks>
    class function RootOrEmpty: string; static;
    /// <summary>The RAD Studio installation root: $BDS, else the registry, else
    /// the existence-checked fallback.</summary>
    /// <returns>The root, with no trailing path delimiter.</returns>
    /// <exception cref="EStudioNotFound">Raised when no source resolves. The
    /// message names all three.</exception>
    /// <remarks>The single place this repo is allowed to name a Studio path.
    /// Everything under it -- bin\rsvars.bat, lib\&lt;plat&gt;\release -- is
    /// composed with TPath.Combine by the caller, never stored as its own
    /// literal.</remarks>
    class function Root: string; static;
    /// <summary>The batch file that loads the Embarcadero build environment.</summary>
    /// <returns>&lt;Root&gt;\bin\rsvars.bat.</returns>
    /// <exception cref="EStudioNotFound">Propagated from
    /// <see cref="DRagLint.Core.StudioEnv.TStudioEnv.Root"/>.</exception>
    /// <remarks>Composed, never stored. Its existence is NOT checked here --
    /// callers pass it to cmd.exe, whose own failure names the file.</remarks>
    class function RsvarsBat: string; static;
    /// <summary>Checks the parts of the contract a test can control: that $BDS
    /// wins, that a trailing delimiter and surrounding whitespace are
    /// normalised away, and that RsvarsBat is COMPOSED from Root rather than
    /// being a second literal.</summary>
    /// <param name="AFailure">On False, which assertion failed and with what
    /// values; '' on success.</param>
    /// <returns>True when every assertion holds.</returns>
    /// <remarks>Lives here rather than in the CLI so that the only unit naming
    /// a Studio path is also the only unit naming one in its test --
    /// tests\autotest\run_studio_root_guard.ps1 enforces exactly that, and an
    /// assertion written elsewhere would have to be exempted from the guard it
    /// exists to support. Reached through `drag-lint selftest studio-root`.
    ///
    /// NOT thread-safe, unlike the rest of this class: it sets and restores the
    /// process-wide BDS variable. It is a test entry point, called once from a
    /// single-purpose CLI verb.</remarks>
    class function SelfTest(out AFailure: string): Boolean; static;
  end;

implementation

uses
  System.IOUtils,
  System.Win.Registry,
  Winapi.Windows;

{ TStudioEnv }

class function TStudioEnv.ReadRegistryRoot: string;
var
  Reg: TRegistry;
begin
  Result:= '';
  Reg:= TRegistry.Create(KEY_READ);
  try
    try
      Reg.RootKey:= HKEY_CURRENT_USER;
      if Reg.OpenKeyReadOnly(REG_KEY) and Reg.ValueExists(REG_VALUE) then
        Result:= Trim(Reg.ReadString(REG_VALUE));
    except
      { A missing or unreadable key is not exceptional -- it is the expected
        state without an IDE, and the caller still has the fallback to try. }
      on E: Exception do Result:= '';
    end;
  finally
    Reg.Free;
  end;
end; // function

class function TStudioEnv.TryRoot(out ARoot: string; out ADiagnostic: string): Boolean;
begin
  ADiagnostic:= '';

  ARoot:= Trim(GetEnvironmentVariable('BDS'));
  if ARoot = '' then ARoot:= ReadRegistryRoot;

  if ARoot = '' then
    if TDirectory.Exists(FALLBACK_ROOT) then ARoot:= FALLBACK_ROOT;

  if ARoot <> '' then
  begin
    ARoot:= ExcludeTrailingPathDelimiter(ARoot);
    Exit(True);
  end;

  ADiagnostic:= 'RAD Studio 37.0 not found. Looked at the BDS environment ' +
                'variable, then HKCU\' + REG_KEY + '\' + REG_VALUE + ', then ' +
                FALLBACK_ROOT + ' (which does not exist). Set BDS to the ' +
                'Studio installation root.';
  Result:= False;
end; // function

class function TStudioEnv.RootOrEmpty: string;
var
  Diagnostic: string;
begin
  if not TryRoot(Result, Diagnostic) then Result:= '';
end; // function

class function TStudioEnv.Root: string;
var
  Diagnostic: string;
begin
  if not TryRoot(Result, Diagnostic) then raise EStudioNotFound.Create(Diagnostic);
end; // function

class function TStudioEnv.RsvarsBat: string;
begin
  Result:= TPath.Combine(Root, 'bin\rsvars.bat');
end; // function

class function TStudioEnv.SelfTest(out AFailure: string): Boolean;
const
  { A path that cannot exist, so a machine's real Studio can never make a
    failing assertion pass by coincidence. }
  PROBE = 'C:\SelfTestStudio';  // dl:ok hardcoded-absolute-path@73e1 -- a deliberately non-existent probe root, so a real Studio install cannot make a failing assertion pass by coincidence
var
  SavedBds: string;
  Restore : Boolean;

  function Expect(const ADesc, AActual, AExpected: string): Boolean;
  begin
    Result:= AActual = AExpected;
    if not Result then
      AFailure:= ADesc + ' -- got "' + AActual + '", expected "' + AExpected + '"';
  end;

begin
  AFailure:= '';

  { Put BDS back the way it was. GetEnvironmentVariable cannot tell "absent"
    from "defined but empty", and the two differ to SetEnvironmentVariable -- so
    an empty reading is restored by UNDEFINING it, which is the state TryRoot
    treats identically anyway. }
  SavedBds:= GetEnvironmentVariable('BDS');
  Restore := SavedBds <> '';
  try
    SetEnvironmentVariable('BDS', PChar(PROBE));
    if not Expect('BDS wins over the registry and the fallback', Root, PROBE) then Exit(False);
    if not Expect('RsvarsBat is composed from Root, not stored separately',
                  RsvarsBat, PROBE + '\bin\rsvars.bat') then Exit(False);
    if not Expect('RootOrEmpty agrees with Root when a root resolves',
                  RootOrEmpty, PROBE) then Exit(False);

    { A trailing delimiter is normalised away, so a caller that concatenates
      cannot produce a doubled separator. }
    SetEnvironmentVariable('BDS', PChar(PROBE + '\'));
    if not Expect('a trailing delimiter is stripped from Root', Root, PROBE) then Exit(False);
    if not Expect('a trailing delimiter does not double in RsvarsBat',
                  RsvarsBat, PROBE + '\bin\rsvars.bat') then Exit(False);

    { Surrounding whitespace is a typo in an env var, never part of a path. }
    SetEnvironmentVariable('BDS', PChar('  ' + PROBE + '  '));
    if not Expect('BDS is trimmed', Root, PROBE) then Exit(False);
  finally
    if Restore then SetEnvironmentVariable('BDS', PChar(SavedBds))
    else SetEnvironmentVariable('BDS', nil);
  end;

  Result:= True;
end; // function

end.
