========================================================================
Minimal repro: RAD Studio 37 IDE crashes when opening a form in the
Designer if a USED datamodule has a TdxComponentPrinter whose report link
targets a control on ANOTHER form (a cross-module report link).
========================================================================

ENVIRONMENT
  RAD Studio 13 Florence (37.0.59082.6021), both 32-bit and 64-bit IDE.
  DevExpress VCL 2026.1.3.0.
  Windows 11 (build 26200).

SUMMARY
  Form1 (a TdxRibbonForm) USES a datamodule DMStyles. DMStyles contains a
  TdxComponentPrinter (dxPrinter) whose report link (GridReportLink1:
  TdxGridReportLink) has Component = Form2.cxGrid1 -- i.e. the link points
  at a control that lives on a DIFFERENT form/module (Form2, Unit2).

  Opening Form1 in the RAD Studio Form Designer crashes the IDE. The crash
  occurs while the design-time load resolves the cross-module report-link
  Component reference; it faults inside the DevExpress printing-system /
  cxLibrary object-link machinery with an access violation at address 0
  (a call through a nil/dangling pointer).

FILES
  PrinterCrashRepro.dpr/.dproj  - the project (Win32, Debug)
  Unit1.pas/.dfm                - Form1, TdxRibbonForm, USES DMStyles  <-- OPEN THIS IN DESIGNER
  Unit2.pas/.dfm                - Form2, hosts cxGrid1 (the report-link target)
  DMStyles.pas/.dfm             - datamodule with dxPrinter + the CROSS-FORM report link

  The load-bearing line is in DMStyles.dfm:
      object GridReportLink1: TdxGridReportLink
        Component = Form2.cxGrid1        <-- cross-module reference
      end

REPRO STEPS
  1. Open PrinterCrashRepro.dproj in RAD Studio 37.
  2. Build once (so all three forms/units are compiled and known).
  3. In the Project Manager, open Unit1 (Form1) and switch to the FORM
     view (the Designer) -- e.g. click the "Design" tab of the editor.
  4. The IDE crashes (access violation / IDE terminates).

  Closing Form1's designer, or switching TO its design view, both trip it
  in the original real-world project. If step 3 alone does not reproduce
  on your machine, also try: open Form1 designer, then close it; or open
  Unit2's designer first, then Unit1's.

  Confirmed workaround in the original project: deleting the cross-form
  report link (the TdxGridReportLink whose Component points at another
  form) stops the crash. Rebuilding/refreshing the dxPrinter's links also
  cleared it.

CRASH DETAILS (from a full user-mode dump of the 64-bit IDE)
  Exception    : 0xC0000005 access violation (also seen as 0xC000041D,
                 STATUS_FATAL_USER_CALLBACK_EXCEPTION)
  Fault address: 0x0000000000000000  (rip=0 -> call through nil pointer)
  Adjacent frames (release BPLs, nearest-export symbols):
     cxLibraryRS37!Dxhooks.TdxHookProc
     cxLibraryRS37!Generics.Collections.TDictionary<TcxObjectLink,Integer>.GetBucketIndex
     dxCoreRS37!Dxcoreclasses.TcxIUnknownObject...
     dxPScxPivotGridLnkRS37 / dxPSdxOCLnkRS37 / dxPSdxFCLnkRS37  (printing-system link pkgs)
     ... during Vcl.Forms.TCustomForm.DestroyHandle / TFormContainerForm teardown
        (designer surface: VCLSurface.TVclDesignSurface, VCLFormContainer)
  A second capture on the same project showed the IDE VCL-Styles theming
  path (Vcl.Themes.TStyleManager.GetStyle / GetStyleName / SourceLoaded
  recursing, IDETheme.IDEStyleHooks) while switching to the design view;
  disabling the IDE Dark theme did NOT stop the crash, so the theming
  frames are secondary -- the cross-module report link is the trigger.

WHY WE THINK IT IS A DEVEXPRESS DESIGN-TIME ISSUE
  - No user/third-party IDE plugin is loaded at crash time (verified).
  - The fault is inside cxLibrary's TdxHookProc + a TcxObjectLink dictionary
    lookup, invoked by the printing-system report link.
  - Removing the cross-module report link deterministically fixes it.

NOTE ON THE SANITIZED SAMPLE
  This sample is reduced from a large production form ("uMain") that USES a
  styles datamodule ("uStyles" / TdmStyles) carrying the component printer.
  The sample keeps only: a ribbon form that uses the datamodule, the
  datamodule with the printer + one cross-form grid report link, and the
  second form owning the grid. If the sample does not reproduce on a clean
  DevExpress install, the difference is likely additional design-time
  packages or a specific report-link type in the original; we can supply
  the full dump (bds.exe.*.dmp, ~2.2 GB) on request.
