# Performance and power behavior

Codex Pet Dock is a Windows PowerShell + WinForms sidecar. It is designed to
spend work only while the pet is visible and moving, but it is not a
single-digit-megabyte native process. This document records reproducible local
measurements instead of describing it only as "lightweight".

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
| Quota probe during samples | No `node.exe` child process observed |

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
| Peak Node quota probes | 0 | 0 |

The memory footprint includes the Windows PowerShell 5.1 runtime, WinForms,
UI Automation, image resources, and the application itself. It should not be
presented as if the dock itself used only a few megabytes.

The reported read/write transfer deltas are intentionally omitted from the
headline table. Windows process transfer counters include files, devices,
pipes, and console IPC; they are not a reliable measurement of physical disk
writes. During Run B they were about 529 KB read and 646 KB written across
30 seconds, with no error log growth and no Node quota probe.

## Adaptive behavior

The runtime has separate activity levels:

| State | Behavior |
|---|---|
| No visible pet | 1-second discovery interval; dock and detail card hidden; quota probe stopped |
| Visible and still | 64 ms observation timer; unchanged window moves skipped; z-order maintained once per second |
| Moving or settling | Temporary 16 ms timer with damped coordinate convergence |
| Pet identity/window replaced | Fast reacquisition for up to 1.5 seconds; old anchor discarded |
| Quota refresh | Every 5 minutes by default, or on explicit refresh; no continuous Node process |

Continuous motion extends the fast interval by only 400 ms at a time. Once
the pet stops and the base reaches its target, the runtime returns to the
still-state policy.

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
- handles, threads, child processes, and Node probe count;
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
