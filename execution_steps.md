# Comprehensive Project Execution Guide (Screenshot Walkthrough)

*This document outlines the exact sequence of commands to execute during the project's final test runs. It provides the commands needed to capture the screenshots required for your final report, perfectly aligned with the directory structure established in Phase 1.*

## Preparation
Ensure your container root file systems are prepared and that your test binaries (`cpu_hog`, `memory_hog`) are copied into the root environments so the containers can run them natively.

**Terminal 1 (From the project root: `~/Desktop/OS-jackfruit-main`)**
```bash
# Copy the compiled test workloads into the container filesystems
sudo cp boilerplate/cpu_hog rootfs-alpha/
sudo cp boilerplate/cpu_hog rootfs-beta/
sudo cp boilerplate/memory_hog rootfs-alpha/
```

## Task 1 & 2: Multi-Container Supervision & CLI IPC
Demonstrating that the supervisor can manage multiple concurrent containers via the Command Line Interface.

**Terminal 1 (Supervisor Daemon Setup):**
```bash
cd boilerplate
sudo ./engine supervisor ../rootfs-base
```
*(Leave this terminal running. It will print logger activity as it manages IPC requests.)*

**Terminal 2 (CLI Client execution):**
```bash
cd boilerplate
sudo ./engine start alpha ../rootfs-alpha "/bin/sleep 20"
sudo ./engine start beta ../rootfs-beta "/bin/sleep 20"
sudo ./engine ps
```
*Screenshots to capture: 1. Multi-container supervision logs in Terminal 1. 2. `ps` metadata output in Terminal 2. 4. CLI and IPC response.*

## Task 3: Bounded-Buffer Logging
Demonstrating the thread-safe `stdout/stderr` capture pipeline.

**Terminal 2 (CLI Client):**
```bash
# Read the piped stdout/stderr from a running or stopped container
sudo ./engine logs alpha
```
*Screenshot to capture: 3. Bounded-buffer log file contents printing successfully to the screen.*

## Task 4: Kernel Memory Enforcement
Demonstrating the custom Linux kernel module enforcing Resident Set Size (RSS) bounds.

**Terminal 3 (Kernel Setup):**
```bash
# Navigate to boilerplate if you aren't already there
cd ~/Desktop/OS-jackfruit-main/boilerplate

# Load the memory monitor module
sudo insmod monitor.ko
```

**Terminal 2 (Trigger Memory Hog):**
```bash
# Spawn a workload designed to aggressively consume memory and breach limits
sudo ./engine start mem_test ../rootfs-alpha /memory_hog --soft-mib 40 --hard-mib 64
```

**Terminal 3 (Observe Kernel Actions):**
```bash
dmesg | tail
```
*Screenshots to capture: 5. Soft-limit warning in dmesg. 6. Hard-limit SIGKILL enforcement in dmesg, and the `ps` command showing the kill state.*

## Task 5: Scheduler Experiments
Contrasting process cycle allocation utilizing the Linux Completely Fair Scheduler (CFS). 

**Terminal 2 (Spawn Competitor Workloads):**
```bash
# High priority process (-20)
sudo ./engine start cpu_high ../rootfs-alpha /cpu_hog --nice -20

# Low priority process (+19)
sudo ./engine start cpu_low ../rootfs-beta /cpu_hog --nice +19
```

**Terminal 3 (Observe CPU Usage Distribution):**
```bash
top
```
*Screenshot to capture: 7. The `top` console showing a massive discrepancy in CPU cycle percentages between the two processes based on their `nice` weights.*

## Task 6: Clean Teardown
Proving no zombie processes leaked and memory was freed correctly from the system.

**Terminal 2 (Cleanup Containers):**
```bash
sudo ./engine stop alpha
sudo ./engine stop beta
sudo ./engine stop mem_test
sudo ./engine stop cpu_high
sudo ./engine stop cpu_low
```

**Terminal 1 (Shutdown Runtime):**
```bash
# Press Ctrl+C in Terminal 1 to gracefully shutdown the supervisor loop
```

**Terminal 3 (Perform Diagnostics & Unload Kernel Module):**
```bash
# Ensure no engine child processes (zombies) were left orphaned
ps aux | grep engine

# Remove the memory monitor module from the kernel
sudo rmmod monitor
```
*Screenshot to capture: 8. Evidence of a totally clean teardown without zombie processes (`ps aux`), and the `monitor` safely unloaded.*
