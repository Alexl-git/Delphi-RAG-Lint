object dmStyles: TdmStyles
  Height = 300
  Width = 400
  object dxPrinter: TdxComponentPrinter
    CurrentLink = JobListPrinterLink1
    PreviewOptions.WindowState = wsMaximized
    PrintTitle = '@@@'
    Version = 1
    Left = 48
    Top = 12
    PixelsPerInch = 96
    object JobListPrinterLink1: TdxGridReportLink
      PageNumberFormat = pnfNumeral
      PrinterPage.DMPaper = 1
      PrinterPage.Footer = 200
      PrinterPage.Header = 200
      PrinterPage.Margins.Bottom = 500
      PrinterPage.Margins.Left = 500
      PrinterPage.Margins.Right = 500
      PrinterPage.Margins.Top = 500
      PrinterPage.Orientation = poLandscape
      PrinterPage.PageSize.X = 8500
      PrinterPage.PageSize.Y = 11000
      PrinterPage.ScaleMode = smFit
      PrinterPage._dxMeasurementUnits_ = 0
      PrinterPage._dxLastMU_ = 1
      ReportDocument.Caption = 'Job List'
      ShrinkToPageWidth = True
      TimeFormat = 0
      PixelsPerInch = 96
      BuiltInReportLink = True
    end
  end
end
