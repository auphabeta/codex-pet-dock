# Performance and power behavior

Codex Pet Dock is a Windows PowerShell + WinForms sidecar. It is designed to
spend work only while the pet is visible and moving, but it is not a
single-digit-megabyte native process. This document records reproducible local
measurements instead of describing it only as "lightweight".

## Plain-language conclusion

On the reference PC, leaving the pet and dock visible but idle used about
`0.21%` of the machine's total CPU capacity and about `170 MB` of memory.
In practical terms, its idle CPU impact was small. It did not keep a quota
probe running in the background; following speeds up temporarily during pet
movement, slows down again after movement stops, and quota probing pauses when
there is no visible pet. Results vary by machine and this is not a battery-life
or hardware-power claim.

## Reference measurement

Measured on 2026-07-29 with commit `3654bed` and the installed
`0.3.0-beta` Preview.

| Item | Value |
|---|---|
| Operating system | Windows 11 Home China, build `10.0.26100` |
| CPU | Intel Core i7-11800H |
| Logical processors | 16 |
| State | Pet and dock visible; no intentional dragging or theme switching |
| Sample duration | 30 seconds per run |
| Quota probe during samples | No quota-probe child process observed |

Two consecutive real-process samples:

| Metric | Run A | Run B |
|---|---:|---:|
| Process CPU time during 30 s | 1.000 s | 1.000 s |
| Average CPU, one logical processor | 3.333% | 3.333% |
| Approximate share of total 16-thread CPU capacity | 0.2083% | 0.2083% |
| Average working set | 170.36 MB | 171.03 MB |
| Peak working set | 170.55 MB | 171.11 MB |
| Average private memory | 135.01 MB | 135.65 MB |
| Peak private memory | 135.20 MB | 135.73 MB |
| Average handles | 668.2 | 664.1 |
| Average threads | 15.1 | 13.5 |
| Peak child processes | 1 (`conhost.exe`) | 1 (`conhost.exe`) |
| Peak quota probes | 0 | 0 |

The memory footprint includes the Windows PowerShell 5.1 runtime, WinForms,
UI Automation, image resources, and the application itself. It should not be
presented as if the dock itself used only a few megabytes.

The reported read/write transfer deltas are intentionally omitted from the
headline table. Windows process transfer counters include files, devices,
pipes, and console IPC; they are not a reliable measurement of physical disk
writes. During Run B they were about 529 KB read and 646 KB written across
30 seconds, with no error log growth and no quota probe.

## Adaptive behavior

The runtime has separate activity levels:

| State | Behavior |
|---|---|
| No visible pet | 1-second discovery interval; dock and detail card hidden; quota probe stopped |
| Visible and still | 64 ms observation timer; unchanged window moves skipped; z-order maintained once per second |
| Moving or settling | Temporary 16 ms timer with damped coordinate convergence |
| Pet identity/window replaced | Fast reacquisition for up to 1.5 seconds; old anchor discarded |
| Quota refresh | Every 15 minutes by default, on a stale detail-card open, or on explicit refresh; no continuous probe process |

Continuous motion extends the fast interval by only 400 ms at a time. Once
the pet stops and the base reaches its target, the runtime returns to the
still-state policy.

## Quota-probe cost and optimization

The quota probe used to query the official app-server and rescan every local
session from the current week on each five-minute refresh. A measured probe
processed 34 sessions and 7,281 Token events:

| Probe state | Wall time | Cache hits | Session files parsed |
|---|---:|---:|---:|
| Before incremental cache | 4.721 s | 0 | all weekly files |
| First indexed run | 4.538 s | 0 | 34 |
| Unchanged warm run | 2.573 s | 34 | 0 |

The before-cache Node process tree peaked at 289.1 MB of working set and
consumed about 5.594 CPU-seconds across Node and its temporary app-server
children.
This is a short-lived refresh cost, not the dock's steady-state memory.

The production probe is now a .NET Framework C# executable and does not require
Node.js. Under the same warm-cache conditions:

| Probe implementation | Wall time | CPU time observed | Peak process-tree working set |
|---|---:|---:|---:|
| Native C# | 3.505 s | 0.891 s | 134.7 MB |
| Node reference | 3.494 s | 0.984 s | 194.7 MB |

The native probe reduced the temporary process-tree working-set peak by about
60 MB (31%) in this sample. Wall time stayed similar because both versions must
briefly start the same official Codex app-server.

After installing the native-probe build, a separate 30-second visible-idle
sample recorded:

| Installed steady-state metric | Result |
|---|---:|
| Approximate share of total 16-thread CPU capacity | 0.2083% |
| Average working set | 167.48 MB |
| Average private memory | 131.86 MB |
| Peak quota-probe processes | 0 |
| Peak Node processes | 0 |

The steady-state memory remains dominated by the Windows PowerShell UI host.
Moving the long-lived window, tray, and UI Automation layer into
`CodexPetDock.exe` is a separate migration; the current native-probe work
reduces periodic refresh cost and removes Node/npm, but does not pretend to
have solved that remaining memory cost.

A controlled C# WinForms tray/message-loop fixture measured 19.1 MB working set
and 20.4 MB private memory on the same PC. That is only a framework baseline,
not a finished-product forecast; the source and limitations are recorded in
[`tests/fixtures/performance/`](../tests/fixtures/performance/README.md).

The new numeric cache was 10,262 bytes in this sample. It stores SHA-256 file
identifiers, sizes, modification times, and Token aggregates only; it does not
store original session paths, messages, account data, or credentials.

Scheduled refreshes now run every 15 minutes instead of every five minutes,
reducing the normal maximum from 12 to four probes per hour while a pet remains
visible. Opening the detail card refreshes data only when it is at least five
minutes old. Failures back off from 15 to 30 and then 60 minutes instead of
repeatedly starting processes while Codex or the network is unavailable.

## Reproduce the measurement

Start the installed Pet Dock, choose the state to measure, then run from the
repository or extracted Preview package:

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned `
  -File .\tests\Measure-CodexPetDockPerformance.ps1 `
  -DurationSeconds 30
```

The script emits JSON containing:

- OS, CPU, logical-processor count, app version, state, and duration;
- process CPU time and one-core/whole-machine percentages;
- average and peak working/private memory;
- handles, threads, child processes, and quota-probe count;
- process I/O transfer deltas and visible-window count.

To measure the waiting state, hide or close the Codex pet, wait until the
dock disappears, and run the same command. The result must say
`waiting-no-visible-pet`; otherwise it is not a valid waiting-state sample.

To measure active following, drag or switch the pet during the full sample
and label the result as an interaction measurement.

## Interpretation limits

- These are local reference measurements, not a guarantee for every machine.
- Antivirus, DPI, theme images, Codex updates, other system load, and active
  pet animation can change the result.
- The whole-machine percentage is CPU time divided by elapsed time and logical
  processor count. It is a capacity approximation, not Task Manager's exact
  sampling algorithm.
- The script does not measure GPU energy, wall power, battery drain, fan
  behavior, or hardware package watts. No claim about those values is made.
- The no-pet and active-drag states should be recorded separately rather than
  inferred from the visible-idle result.
