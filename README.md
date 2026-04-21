# Multi-Container Runtime (OS-Jackfruit)

A custom, lightweight Linux container runtime implemented in C, featuring a long-running user-space supervisor daemon and a strict kernel-space memory monitor (LKM).

> **Important Note:** This repository contains the complete source code and technical implementation details of the project. For a comprehensive overview, including architectural diagrams, execution flowcharts, engineering analysis, empirical scheduling data, and system screenshots, **please strongly refer to the [`final_report_draft.md`](final_report_draft.md) file.** It is highly recommended to view the report file for a better representation of the project capabilities.

## Overview

This project bypasses enterprise container abstraction layers (like Docker) to interact directly with core Linux constructs. It solves multiple crucial system programming problems:

1. **Process Isolation:** Uses `clone()` and `chroot` to jail processes into isolated CPU, PID, Mount, and UTS namespaces.
2. **Concurrent IPC & Daemonization:** Employs a single Unix Domain Socket (`SOCK_STREAM`) to route asynchronous CLI instructions to a continuous Supervisor daemon managing multiple containers simultaneously.
3. **Bounded-Buffer Logging:** Implements a thread-safe Producer-Consumer pipeline using `pthread_mutex_t` and POSIX Condition Variables to stream stdout/stderr without race conditions.
4. **Kernel-Space Enforcement:** Utilizes a custom Loadable Kernel Module (`monitor.ko`) via `ioctl` interfaces to actively poll the Resident Set Size (RSS) of tracked PIDs. If hard limits are surpassed, the kernel injects an absolute `SIGKILL` to prevent resource starvation.

## Empirical Scheduling Analysis

This repository includes experimental testbeds used to contrast standard workloads (`cpu_hog` vs `io_pulse`). We manipulated execution priorities across multiple containers utilizing `setpriority()` (`nice` values from -20 to +19) to observe execution cycle counts under the Linux Completely Fair Scheduler (CFS). 

Detailed experiment logs, bar charts, line graphs, and deep analysis are documented exclusively in the [project report](final_report_draft.md).

## Getting Started

To explore the codebase and compile the environment on an Ubuntu Linux system (Secure Boot explicitly OFF):

```bash
cd boilerplate
make
```

### Component Structure
- `engine.c`: The core User-Space CLI router, Supervisor loops, thread synchronizers, and namespace spawners.
- `monitor.c`: The Kernel-Space `get_mm_rss()` loop and `SIGKILL` enforcer.
- `cpu_hog.c` / `io_pulse.c` / `memory_hog.c`: Custom binaries used for the performance and kernel enforcement experiments.

## Further Documentation

Please read the **[Final Project Report](final_report_draft.md)** to examine all Phases of Development alongside their corresponding visual executions and architecture diagrams.
