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
