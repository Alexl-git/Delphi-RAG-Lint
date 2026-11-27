# ask: sent-not-handled

**Protocol commands this project sends that the other side never handles.** A question over two indexes (client and server), not a lint rule. One of the questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

Answered in-process by the engine (`drag-lint ask`) (see [Charts and the IDE](Charts-and-the-IDE)).

```
drag-lint ask sent-not-handled --target project --db <client.sqlite> --counterpart-db <server.sqlite>
```

`--counterpart-db` is required (or a pairing in `report-pairs.json`); without the far side "never handled" cannot be told from "handled elsewhere", so the question is refused and names the missing flag. `--cap N` bounds the commands drawn (default 40); never-handled commands are drawn first, so the cap cannot cut the finding.

## You select

`project` for every sent command, or one command constant's name to ask about it alone.

## The chart shows

One box per sent command: red when the counterpart never handles it, green when it does, with the number of routines that send it; each box is anchored to the first place it is sent. The footer states the counts and the two definitions below.

## It stands on

* **Sent**: a command (an enum constant) named in a routine that also calls a routine of a transport unit (unit name `Pipes.*`, `uPipe*` or `uBroadcast*`, the same convention [`crosses-boundary`](ask-crosses-boundary) uses). Routines inside the transport units themselves do not count.
* **Handled**: the counterpart index names the same command (by name, case-blind) in a routine outside the transport units.

## Read it carefully

* "Handled" means named, not proven dispatched: a counterpart routine that only sends the command back counts as handling it, so the list can miss a command whose only far-side use is another send. It never reports a command the far side does name.
* A command is matched by its constant name; two enums with the same constant name in the two indexes are one command.
* A sender that passes the command through a variable (not as a named constant) is not seen.
* Zero never-handled commands is an answer ("every command sent here is handled"), not an error; zero sent commands is refused, because the transport convention probably does not match this project.
