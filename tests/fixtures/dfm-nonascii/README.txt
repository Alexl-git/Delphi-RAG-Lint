dfm-nonascii -- DELIBERATE non-ASCII fixtures (wave 149 lane DF).
FormAnsi.dfm/.pas: Windows-1252, no BOM; object btn<U-umlaut>ber.
FormUtf8.dfm/.pas: UTF-8 with BOM; object btn<U-umlaut>ber and btn<Cyrillic De-a>.
The .dfm identifiers are the test subject of tests\autotest\run_dfm_nonascii_identifier.ps1:
the DFM extractor must store the FULL identifier, not its ASCII prefix 'btn'.
Listed in run_encoding_guard.ps1 DeliberateFixtures. Never 'fix' the encoding.
