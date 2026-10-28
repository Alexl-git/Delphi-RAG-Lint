# GATELEAK (2026-10-27): the VCL needs two GLOBAL atoms per process -- 'Delphi<pid %.8X>' (WindowAtom) and
# 'ControlOfs<HInstance %.8X><main thread id %.8X>' (ControlAtom); Vcl.Dialogs adds a third, 'WndProcPtr<same>'. FindControl maps a window handle to its VCL
# control through them. A process that is KILLED (every GUI driver kills the editor and its engine children on
# exit) never deletes them, so they leak until logoff; this desktop had ~3000 of them (~1000 of each) and the global
# atom table ran out. An editor started while the table is full gets atom 0, FindControl answers nil for every window, and
# every button is dead: a posted BM_CLICK focuses the button but never reaches OnClick, a posted WM_COMMAND is
# dropped by DoControlMsg. Menu commands still work (they dispatch by item ID), so the run looks healthy until
# the first button click ('add.dialog: no Open dialog after two Add... clicks', 2 of 5 runs).
#
# Usage (dot-source, then call):
#   . "$PSScriptRoot\vcl-atoms.ps1"
#   VclAtomsReclaim                       -> deletes the leaked atoms of DEAD processes / threads; returns a count line
#   VclAtomsOf $procId $mainWnd           -> @{ Control = <atom or 0>; Window = <atom or 0>; Names = '...' }
# Reclaim only deletes an atom whose owner is gone: 'Delphi<pid>' when no process has that id, 'ControlOfs..<tid>'
# / 'WndProcPtr..<tid>' when no thread has that id (a reused id keeps the atom: conservative). Atoms of live processes (the IDE, other
# editors, other lanes' runs) are never touched.
Add-Type -TypeDefinition @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class VclAtoms {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern ushort GlobalFindAtom(string s);
  [DllImport("kernel32.dll")] static extern ushort GlobalDeleteAtom(ushort a);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern uint GlobalGetAtomName(ushort a, StringBuilder b, int n);
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenThread(uint access, bool inherit, uint tid);
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
  [DllImport("kernel32.dll")] static extern bool GetExitCodeThread(IntPtr h, out uint code);
  [DllImport("kernel32.dll")] static extern bool GetExitCodeProcess(IntPtr h, out uint code);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  const uint QUERY_LIMITED = 0x1000, STILL_ACTIVE = 259;
  const int ERROR_INVALID_PARAMETER = 87;
  // Alive unless the OS says the id names nothing (ERROR_INVALID_PARAMETER) or an exited object.
  static bool ThreadAlive(uint tid) {
    IntPtr h = OpenThread(QUERY_LIMITED, false, tid);
    if (h == IntPtr.Zero) return Marshal.GetLastWin32Error() != ERROR_INVALID_PARAMETER;
    uint c; bool ok = GetExitCodeThread(h, out c); CloseHandle(h); return !ok || c == STILL_ACTIVE;
  }
  static bool ProcessAlive(uint pid) {
    IntPtr h = OpenProcess(QUERY_LIMITED, false, pid);
    if (h == IntPtr.Zero) return Marshal.GetLastWin32Error() != ERROR_INVALID_PARAMETER;
    uint c; bool ok = GetExitCodeProcess(h, out c); CloseHandle(h); return !ok || c == STILL_ACTIVE;
  }
  public static string Reclaim() {
    int seen = 0, freed = 0; var sb = new StringBuilder(256);
    for (int a = 0xC000; a <= 0xFFFF; a++) {
      sb.Clear(); if (GlobalGetAtomName((ushort)a, sb, 256) == 0) continue;
      string s = sb.ToString(); uint id; bool dead;
      if ((s.StartsWith("ControlOfs") || s.StartsWith("WndProcPtr")) && s.Length >= 18 + 8 && uint.TryParse(s.Substring(s.Length - 8), System.Globalization.NumberStyles.HexNumber, null, out id)) dead = !ThreadAlive(id);
      else if (s.StartsWith("Delphi") && s.Length == 14 && uint.TryParse(s.Substring(6), System.Globalization.NumberStyles.HexNumber, null, out id)) dead = !ProcessAlive(id);
      else continue;
      seen++; if (!dead) continue;
      for (int k = 0; k < 8 && GlobalFindAtom(s) != 0; k++) GlobalDeleteAtom(GlobalFindAtom(s));
      if (GlobalFindAtom(s) == 0) freed++;
    }
    return "vcl-atoms: " + seen + " VCL atom(s), " + freed + " leaked by dead processes reclaimed";
  }
  public static ushort Find(string s) { return GlobalFindAtom(s); }
  public static uint Tid(IntPtr wnd) { uint p; return GetWindowThreadProcessId(wnd, out p); }
}
'@
function VclAtomsReclaim { [VclAtoms]::Reclaim() }
# The editor's own two atoms. $wrongName (driver -ProofAtomCheck only) asks for a name no process registers,
# so the check that uses this must FAIL: the proof it can.
function VclAtomsOf($procId, $mainWnd, [switch]$WrongName) {
  $base = (Get-Process -Id $procId).MainModule.BaseAddress.ToInt64()
  $tid  = if ($WrongName) { 0 } else { [VclAtoms]::Tid($mainWnd) }
  $ctl  = 'ControlOfs{0:X8}{1:X8}' -f $base, $tid
  $win  = 'Delphi{0:X8}' -f $procId
  @{ Control = [int][VclAtoms]::Find($ctl); Window = [int][VclAtoms]::Find($win); Names = "$ctl / $win" }
}
