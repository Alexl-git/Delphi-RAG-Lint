program HubSurface;

// Fixture (lane 148 HP2, spec 2026-11-08-hub-scc-phased P2): a hub-shaped circular group. HubMain
// owns the global HubMainForm; the three spokes read it in their implementation and HubMain calls
// them back. Every spoke use is `HubMainForm.<member>`: cycles --plan --hub-surface plans the
// IHubMainHub surface, --apply writes it and the group breaks.

{$APPTYPE CONSOLE}

uses
  HubMain in 'HubMain.pas',
  HubSpokeA in 'HubSpokeA.pas',
  HubSpokeB in 'HubSpokeB.pas',
  HubSpokeC in 'HubSpokeC.pas';

begin
  Run;
end.
