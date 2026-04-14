# Project Roadmap: Multi-Container Runtime

This document contains a comprehensive, step-by-step guide for implementing the OS-Jackfruit kernel and user-space runtime project. Use this as a checklist to track your progress.

## Phase 1: Environment Setup & Verification
- `[ ]` Boot into an Ubuntu 22.04 or 24.04 VM with **Secure Boot disabled** (No WSL).
- `[ ]` Install dependencies: `sudo apt update && sudo apt install -y build-essential linux-headers-$(uname -r)`
- `[ ]` Run the environment preflight check: `cd boilerplate && sudo ./environment-check.sh`
- `[ ]` Address any errors reported by the environment check.
- `[ ]` Download the Alpine mini root filesystem tarball.
- `[ ]` Extract the rootfs to a folder named `rootfs-base`.
- `[ ]` Create testing clones of the rootfs: `cp -a ./rootfs-base ./rootfs-alpha`, etc.
- `[ ]` Compile the provided templates: Run `make` inside the `boilerplate` directory and verify it builds `engine` and `monitor.ko` without errors.
- `[ ]` Run GitHub actions smoke test locally: `make -C boilerplate ci`.

## Phase 2: Core Runtime Architecture (User-Space `engine.c`)
- `[ ]` Outline the supervisor daemon logic to stay alive and wait for events.
- `[ ]` Create a thread-safe metadata table (e.g., a linked list or array protected by mutexes) to store container states, IDs, Host PIDs, etc.
- `[ ]` Implement container spawning in the supervisor:
  - `[ ]` Use `clone()` with `CLONE_NEWPID | CLONE_NEWUTS | CLONE_NEWNS` to spawn the child process.
- `[ ]` Implement child initialization (inside the cloned process):
  - `[ ]` Use `chroot()` or `pivot_root()` to change `/` to the container-specific rootfs directory.
  - `[ ]` Make sure the new rootfs is mounted appropriately if using `pivot_root()`.
  - `[ ]` Mount `/proc`: `mount("proc", "/proc", "proc", 0, NULL);`
  - `[ ]` Execute the target binary using `execve()` or similar.
- `[ ]` Implement the supervisor's `SIGCHLD` handler to reap dead child processes via `waitpid()`, preventing zombies, and updating the container's status in the metadata table.
- **📸 Deliverable Checkpoint:**
  - `[ ]` Take **Screenshot 1 (Multi-container supervision)**: Show two or more containers running simultaneously under your supervisor process.
  - `[ ]` *Note for README:* Note down your design choices for isolation (namespaces/chroot) and supervisor architecture for the "Engineering Analysis" section.

## Phase 3: The CLI & Control IPC (Task 2)
- `[ ]` Pick an IPC mechanism for CLI-to-Supervisor communication (UNIX domain socket or FIFO recommended).
- `[ ]` Write the CLI frontend to parse arguments for `start`, `run`, `ps`, `logs`, and `stop`.
- `[ ]` Send parsed commands accurately over the chosen Control IPC channel.
- `[ ]` Setup an IPC listener thread or event loop in the supervisor to accept incoming CLI requests.
- `[ ]` Implement command execution within the supervisor:
  - `[ ]` `start`: Trigger the clone logic from Phase 2.
  - `[ ]` `run`: Same as start, but hold the CLI connection open until the target container exits.
  - `[ ]` `ps`: Iterate through the metadata table and serialize it back to the CLI over IPC.
  - `[ ]` `logs`: Read the contents of the container's log file and send it back over IPC, or return the path to the CLI process.
  - `[ ]` `stop`: Send `SIGTERM` or `SIGKILL` to the target container's PID.
- `[ ]` Send success/fail response codes back to the CLI process so it can exit cleanly.
- **📸 Deliverable Checkpoint:**
  - `[ ]` Take **Screenshot 4 (CLI and IPC)**: Show a CLI command being issued and the supervisor responding properly.
  - `[ ]` Take **Screenshot 2 (Metadata tracking)**: Run your `ps` command and screenshot the output showing the tracked container metadata.
  - `[ ]` *Note for README:* Document why you chose your specific control IPC mechanism (e.g., Sockets over FIFO) and one tradeoff.

## Phase 4: Bounded-Buffer Logging (Task 3)
- `[ ]` Setup two anonymous pipes (`pipe()`) BEFORE calling `clone()` for capturing standard output and standard error.
- `[ ]` Inside the cloned child process, `dup2()` its `stdout` and `stderr` to the write-ends of the pipes.
- `[ ]` Inside the supervisor, close the write-ends and begin reading from the read-ends.
- `[ ]` **Implement the Bounded Buffer**: Create a shared ring-buffer data structure protected by a mutex and condition variables to prevent race conditions.
- `[ ]` **Producer Threads**: Create a thread for each running container that `read()`s from the pipe, and inserts lines/chunks into the bounded buffer.
- `[ ]` **Consumer Threads**: Create one (or multiple) consumer threads that wait for items in the buffer, read them, and write them to `container_id.log` on the host. 
- `[ ]` Ensure proper thread synchronization: producers must block if buffer is full; consumers must block if buffer is empty.
- `[ ]` Ensure threads clean up efficiently when a pipe is closed (container exited).
- **📸 Deliverable Checkpoint:**
  - `[ ]` Take **Screenshot 3 (Bounded-buffer logging)**: Show log file contents captured through your pipeline and evidence of the pipeline operating (producer/consumer activity logs).
  - `[ ]` *Note for README:* Note the race conditions you encountered and why you picked your specific synchronization primitives (mutex vs semaphore).

## Phase 5: Kernel Memory Monitor (`monitor.c`)
- `[ ]` Review `monitor_ioctl.h` and define a struct to pass the PID, Soft Limit, and Hard Limit from user-space to kernel-space.
- `[ ]` In `engine.c`, after `clone()` returns the new PID, write an `ioctl` call to `/dev/container_monitor` sending this information.
- `[ ]` In `monitor.c`, build a kernel linked list to store registered processes. Use spinlocks or mutexes to protect this list.
- `[ ]` Implement a kernel timer or a waitqueue-based kernel thread that fires periodically (e.g., every 1 second).
- `[ ]` In the periodic loop, iterate over the list and calculate the Resident Set Size (RSS) using `get_mm_rss()`, passing `p->mm`.
- `[ ]` Check Soft Limits: If RSS > Soft Limit and no warning was logged yet, use `printk(KERN_WARNING ...)` to log it to `dmesg`.
- `[ ]` Check Hard Limits: If RSS > Hard Limit, terminate the process.
  - `[ ]` Ensure your kernel module sends a real `SIGKILL` (e.g., using `send_sig_info()` or `do_send_sig_info()`).
- `[ ]` Make the kernel module check if processes have naturally died off and remove them from the linked list. 
- `[ ]` Modify `engine.c` to gracefully discern `hard_limit_killed` (if exit status is SIGKILL and stop wasn't asked for explicitly) vs normal exits.
- **📸 Deliverable Checkpoint:**
  - `[ ]` Take **Screenshot 5 (Soft-limit warning)**: Show your terminal running `dmesg` or log output displaying the soft-limit warning event.
  - `[ ]` Take **Screenshot 6 (Hard-limit enforcement)**: Show `dmesg` output reflecting a container being killed, AND your supervisor metadata responding to the kill.
  - `[ ]` *Note for README:* Document why the enforcement mechanism belongs in kernel space rather than purely in user space.

## Phase 6: Scheduler Experiments (Task 5)
- `[ ]` Compile the provided workload binaries (`cpu_hog.c`, `io_pulse.c`, etc.).
- `[ ]` Copy the compiled binaries into your specific `rootfs-X` testing directories.
- `[ ]` Implement CLI argument parsing for `--nice N` and apply `setpriority()` before `execve()` in the container initialization.
- `[ ]` Run Experiment Set 1: Two CPU-bound workloads with contrasting nice values. Record time to completion or relative progress over 30 seconds.
- `[ ]` Run Experiment Set 2: A CPU-bound workload alongside an IO-bound workload. 
- `[ ]` Note all your findings for the README analysis. 
- **📸 Deliverable Checkpoint:**
  - `[ ]` Take **Screenshot 7 (Scheduling experiment)**: Capture terminal output or measurements showing observable differences between your two configurations.
  - `[ ]` *Note for README:* Write up the Scheduler Experiment Results including tables/comparisons of the raw data.

## Phase 7: Clean Teardown (Task 6)
- `[ ]` Verify user-space: when the supervisor gets a `SIGINT` (Ctrl+C), it must elegantly stop all children, wait for their pipes to finish dumping logs, join all logger threads, and gracefully exit.
- `[ ]` Free all dynamically allocated memory in `engine.c`.
- `[ ]` Verify kernel-space module unload: `sudo rmmod monitor`.
- `[ ]` Ensure the module `__exit` function securely tears down the kernel thread/timer, empties the linked list, deletes the device note from `/dev`, and frees memory.
- **📸 Deliverable Checkpoint:**
  - `[ ]` Take **Screenshot 8 (Clean teardown)**: Use commands like `ps aux` to show evidence that no zombies remain, threads exited, and supervisor shut down cleanly.

## Phase 8: Final Submission Wrap-up
- `[ ]` Cleanly replace `README.md` with your written report.
- `[ ]` Fill in **1. Team Information**: Names & SRNs.
- `[ ]` Write **2. Instructions**: Step-by-step commands to build, use, and teardown the runtime.
- `[ ]` Insert and caption all **8 Demo Screenshots** gathered from the phases above.
- `[ ]` Finalize **4. Engineering Analysis**: Verify you answered all 5 required questions using your notes.
- `[ ]` Finalize **5. Design Decisions & Tradeoffs**: Ensure tradeoffs are clearly listed for each major subsystem.
- `[ ]` Insert **6. Scheduler Experiment Results**: Add your tables/markdown comparisons and final explanation.
- `[ ]` Review repo contents: ensure `rootfs-base` and `rootfs-*` are ignored by `.gitignore` or deleted.
- `[ ]` Verify `make -C boilerplate ci` still works on your code.
- `[ ]` Commit and push everything cleanly to GitHub.
