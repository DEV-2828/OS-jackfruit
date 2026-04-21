# Viva Preparation Guide: OS-Jackfruit Project

This document contains targeted theory and code-specific questions to help you prepare for a viva/interview on your Multi-Container Runtime project, broken down by the core OS tasks.

---

## Task 1: Multi-Container Runtime & Supervisor
**Container Theory Questions:**
1. **What exactly is a "Container"?**
   *A:* A container is a standardized unit of software that tightly packages an application alongside its required libraries and dependencies so it can run securely and consistently on any Linux environment. 
2. **What real-world problems do containers solve?**
   *A:* They solve the "it works on my machine" problem, eliminate dependency conflicts between apps, and are vastly more lightweight and faster to boot than full Virtual Machines.
3. **What is the fundamental difference between VMs and Containers?**
   *A:* VMs emulate hardware and run a full, heavy guest OS kernel. Containers share the host computer's kernel and only isolate processes at the user-space level using OS mechanisms like namespaces.
4. **What are Linux Namespaces?**
   *A:* Kernel features that wrap global system resources into an abstraction that makes a process believe it has its own isolated instance of the resource (e.g., PID, UTS, Mount).
5. **How do namespaces differ from `cgroups` (control groups)?**
   *A:* Namespaces isolate what a process can *see* (like hiding other processes or folders). `cgroups` isolate what a process can *use* (like capping memory or CPU usage). 
6. **What is a Zombie Process, and how does your supervisor prevent it?**
   *A:* A child process that has finished execution but still has an entry in the process table because the parent hasn't read its exit status. We prevent it by having the supervisor catch `SIGCHLD` and call `waitpid()`.

**Code-Level Questions (engine.c):**
1. **Which flags did you pass to `clone()` to achieve isolation?**
   *A:* `CLONE_NEWPID | CLONE_NEWUTS | CLONE_NEWNS`.
2. **Why do we call `chdir("/")` and `chroot(cfg->rootfs)` inside the `child_fn`?**
   *A:* `chroot` changes the perceived root of the filesystem to the container's private path. We `chdir("/")` immediately after to ensure the process's working directory is not left outside the new root.
3. **Why did you explicitly `mount("proc", "/proc", "proc", 0, NULL)`?**
   *A:* Without this, tools like `ps` inside the container wouldn't work because they rely on the `/proc` psuedo-filesystem to read running process data. The mount namespace isolates it, but doesn't auto-populate it.

---

## Task 2: Supervisor CLI and IPC
**IPC Theory Questions:**
1. **What is IPC (Inter-Process Communication) and why is it mandatory here?**
   *A:* In operating systems, standard processes have isolated memory address spaces and cannot directly read each other's RAM. IPC provides kernel-facilitated channels (like sockets or pipes) for them to pass messages and synchronize safely.
2. **Contrast Shared Memory versus Message Passing.**
   *A:* Shared memory maps the same physical RAM slice to two processes; it's extremely fast but requires manual synchronization like mutexes to prevent corruption. Message passing (sockets/pipes) copies data between process spaces via the kernel, which handles synchronization natively.
3. **What IPC method did you choose for the CLI to talk to the Supervisor?**
   *A:* UNIX Domain Sockets (`AF_UNIX`).
4. **Why use UNIX Domain Sockets instead of normal network sockets (TCP/UDP) or FIFOs?**
   *A:* UNIX Domain sockets are faster than TCP/UDP because they bypass the network stack entirely, routing strictly within the local kernel. They are better than FIFOs because they naturally support full-duplex communication (request/reply) on a unified channel.
5. **Why must the metadata table be protected by a lock?**
   *A:* The metadata table is accessed asynchronously. A CLI thread might be iterating through it for `ps`, while simultaneously a `SIGCHLD` is updating a container's status to `EXITED`, causing a race condition or crash.

**Code-Level Questions (engine.c):**
1. **How is the metadata structure organized?**
   *A:* It is a linked list of `container_record_t` nodes protected by `pthread_mutex_lock(&ctx->metadata_lock)`.
2. **When the CLI types `stop`, how does the container actually stop?**
   *A:* The supervisor finds the matching `host_pid` in the metadata table and issues a `kill(rec->host_pid, SIGKILL)` standard POSIX call.

---

## Task 3: Bounded-Buffer Logging
**Theory Questions:**
1. **Explain the Producer-Consumer problem in your project.**
   *A:* Producers (threads reading from container pipes) want to put strings into the buffer. Consumers (threads writing to `.log` files) want to take strings out. They must be synchronized so producers wait if the buffer is full, and consumers wait if it's empty.
2. **Compare Pipes and Sockets for this logging task.**
   *A:* Pipes are perfect here because they are unidirectional, lightweight byte streams implicitly linking parents and children. Sockets are bidirectional and slightly heavier, which is overkill for simple `stdout` streaming.
3. **Why did you use Condition Variables instead of Semaphores?**
   *A:* Condition variables naturally integrate with mutexes (`pthread_cond_wait`), allowing an atomic release of the mutex before going to sleep, which prevents deadlock.
4. **What would happen if the buffer was UNBOUNDED?**
   *A:* If a container prints logs infinitely faster than the hard drive can write them, the Supervisor's RAM usage would grow unchecked until the host OS killed the runtime (Out Of Memory).

**Code-Level Questions (engine.c):**
1. **How does the container send logs to the supervisor?**
   *A:* In `engine.c`, we call `pipe(pipefd)` *before* cloning. In the child, we use `dup2(cfg->log_write_fd, STDOUT_FILENO)` replacing standard output with the pipe. 
2. **In `bounded_buffer_pop`, why use a `while` loop for `pthread_cond_wait` instead of an `if` statement?**
   *A:* To protect against "Spurious Wakeups". Sometimes a thread wakes up from a condition variable without being explicitly signaled, so it must re-check the condition (`buffer->count == 0`) inside a while loop.

---

## Task 4: Kernel Memory Monitor (monitor.ko)
**Theory Questions:**
1. **Why enforce memory limits in Kernel space instead of User space?**
   *A:* While user-space polling works, the kernel has direct, immediate access to process structures (`get_mm_rss`). In a robust production environment, the kernel can enforce limits faster and cannot be bypassed or delayed by user-space scheduler lag.
2. **What is RSS (Resident Set Size)?**
   *A:* The amount of physical RAM (pages) actively held by the process in memory, excluding swapped pages.
3. **What happens under the hood when a Hard Limit is hit?**
   *A:* The kernel module sends a `SIGKILL` directly to the process control block. `SIGKILL` cannot be caught or ignored by the container, enforcing absolute security.

**Code-Level Questions (monitor.c):**
1. **How do you safely iterate through the kernel list?**
   *A:* We use `list_for_each_entry_safe()`. The `_safe` variant is critical because we are deleting items inside the loop via `list_del()`. Standard iteration would crash due to use-after-free reading the `next` pointer of a deleted node.
2. **What lock primitive did you use in kernel space?**
   *A:* `DEFINE_MUTEX`. Kernel mutexes are sleeping locks. You can't use spinlocks here because taking a spinlock disables preempt/sleeping, and if we perform complex tasks or wait, a spinlock would freeze the CPU core.
3. **How does the Supervisor talk to the Monitor?**
   *A:* We defined character device operations (`fops`) supporting `unlocked_ioctl`. The supervisor calls `ioctl(fd, MONITOR_REGISTER, &req)`.

---

## Task 5: Scheduler Experiments
**Theory Questions:**
1. **What is `nice` value in Linux?**
   *A:* A completely arbitrary mapping (-20 to 19) representing "niceness" to other processes. A process with `-20` is extremely greedy (highest priority), while `19` is the nicest (lowest priority).
2. **How did Linux CFS (Completely Fair Scheduler) treat your experiments?**
   *A:* When competing CPU hogs ran, the one with `nice -20` was granted vastly more execution time slices than the `nice +19` task, reflecting CFS's weighted virtual runtime (`vruntime`) scaling.

**Code-Level Questions (engine.c):**
1. **Where is nice applied in the code?**
   *A:* Inside `child_fn`, just before calling `execve`, we execute `setpriority(PRIO_PROCESS, 0, cfg->nice_value)`. 

---

## Task 6: Cleanup and Teardown
**Theory Questions:**
1. **Why is it critical to thoroughly free memory in a Kernel Module (`monitor.exit`)?**
   *A:* User-space applications have their memory reclaimed by the OS when they exit. A Kernel Module *is* the OS. If `kfree()` is omitted inside `__exit`, that RAM is lost forever until the computer reboots (Kernel Memory Leak).
   
**Code-Level Questions (monitor.c & engine.c):**
1. **How do you ensure the `logging_threads` exit?**
   *A:* We set `buffer->shutting_down = 1` and call `pthread_cond_broadcast()` on the condition variables to purposefully wake up any threads sleeping on an empty buffer so they can check the shutdown flag and return.
2. **What happens during `rmmod monitor`?**
   *A:* The kernel invokes our `monitor_exit()` function. It deletes the timer (`del_timer_sync`), iterates our `list_head` running `kfree` on every node, unregisters the `cdev`, and destroys the `/dev` device node.
