# Essential Errands

An Objective-C Foundation command-line scheduler for a small 2020 grocery basket. It reads local JSON errands with `id`, `name`, `minutes`, and `deadline` (integer minutes since a fictional day start), then emits earliest-deadline-first start, finish, and lateness columns. Equal deadlines retain input order.

Created September 2026 retrospectively; this is not historical 2020 work. The calendar author is disclosed as the author of this retrospective artwork, not as a historical source. It offers scheduling arithmetic only, not financial or medical advice.

```sh
cd app
clang -fobjc-arc -framework Foundation main.m -o /tmp/essential-errands
printf '[{"id":"bread","name":"buy bread","minutes":5,"deadline":8}]' | /tmp/essential-errands -
sh test.sh
```

The bounded core accepts at most 100 unique errands, with nonnegative integer minutes and deadlines up to 1,000,000. It validates JSON types and rejects malformed input. Names and IDs are printed as TSV fields; this first stage does not implement CSV escaping, priorities, breaks, or real-world routing.

Optional app-stage scheduling controls are `--start N` (an initial clock offset), `--from ID` (make one named errand the first stop, then continue with the existing stable earliest-deadline order), and the paired `--break-after N --break-for N`. When cumulative service reaches the threshold between errands, the tool inserts a distinct `BREAK` TSV row; a break is never added after the final errand. These options are bounded to 0–1,000,000 minutes, with a positive break duration, and the default output remains unchanged. `--from` must name an errand in the input.

`--json` switches the output to one structured JSON object containing `schema_version`, `start`, ordered `events`, `total_service`, `total_break_time`, `finish`, and `max_lateness`. Errand events include IDs and names; break events use `kind: "break"`. JSON is emitted with Foundation serialization, including Unicode and quoted names safely.
