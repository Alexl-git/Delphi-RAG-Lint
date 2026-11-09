program GuardedUses;

// Plan fixture (lane 148 CY, fabcyc case 9): GuA's INTERFACE uses GuB inside a single-branch
// conditional region that the build defines (GU_EXTRA); nothing of GuB is used there. GuB's
// implementation uses GuA. The cut removes the guarded entry WITH its guard.

{$APPTYPE CONSOLE}

uses
  GuA in 'GuA.pas',
  GuB in 'GuB.pas';

begin
  GuSay;
end.