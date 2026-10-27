{ ConvRules.TextEncoding.OpenedStatusText: the status line after File > Open names the book, its
  encoding AND the counts (owner ruling 2026-10-27; cd8cdc07 had dropped the counts). }

procedure TestOpenedStatusText;
begin
  Check('opened.plain',
    OpenedStatusText('C:\x\Book.rules', tlAscii7, '', 12, 3) = 'Loaded Book.rules (ASCII-7): 12 line(s), 3 rule(s)',
    OpenedStatusText('C:\x\Book.rules', tlAscii7, '', 12, 3));
  Check('opened.note',
    OpenedStatusText('B.rules', tlUtf8, 'guessed', 1, 0) = 'Loaded B.rules (UTF-8): 1 line(s), 0 rule(s) -- guessed',
    OpenedStatusText('B.rules', tlUtf8, 'guessed', 1, 0));
end;
