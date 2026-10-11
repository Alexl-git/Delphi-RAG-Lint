unit Foo;

interface

type
  TFoo = class
  public
  /// <summary>Does the first thing.</summary>
  /// <remarks>
  /// Who writes this field (drag-lint report who-writes) for FOO.ONE, asked on 2026-10-10 14:32, engine 1.27.0.
  /// COMMAND who-writes -Target "FOO.ONE" -Project "C:\P\A.dproj" -Depth 3
  ///
  /// Totals: 2 write sites / 2 routines.
  /// TFoo.Bar (Foo.pas:10)
  /// </remarks>
    procedure One;
  /// <summary>Does the second thing.</summary>
  /// <remarks>
  /// Who calls this routine (drag-lint report who-calls) for TFoo.Two, asked on 2026-10-10 14:32, engine 1.27.0.
  /// COMMAND who-calls -Target "TFoo.Two" -Project "C:\P\A.dproj" -Depth 3
  ///
  /// Totals: 2 write sites / 2 routines.
  /// TFoo.Bar (Foo.pas:10)
  /// </remarks>
    procedure Two;
  end;

implementation

end.
