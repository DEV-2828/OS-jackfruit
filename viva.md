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

---

## Additional Deep-Dive Questions

### Task 1 — Containers & Supervisor (Extra)

7. **Why does `clone()` need SIGCHLD in its flags alongside the namespace flags?**
   *A:* Without `SIGCHLD`, the parent (supervisor) would never be notified when the child terminates. The kernel only delivers the death signal specified in the lower byte of the flags argument. Without it, `waitpid()` would hang forever and we'd accumulate zombie processes.

8. **Why do we pass a manually allocated stack to `clone()` instead of letting the kernel allocate one like `fork()` does?**
   *A:* `clone()` is a lower-level primitive than `fork()`. Unlike `fork()`, which uses copy-on-write on the parent's stack, `clone()` requires the caller to explicitly provide a stack pointer for the new process/thread. We `malloc(STACK_SIZE)` and pass `stack_ptr + STACK_SIZE` because stacks grow downward on x86.

9. **Why is the stack freed immediately after `clone()` returns in the parent? Isn't the child still using it?**
   *A:* Because we passed `CLONE_NEWPID | CLONE_NEWNS` (not `CLONE_VM`), the child gets its own copy of the address space (copy-on-write). So the parent's `free()` only affects the parent's mapping; the child retains its own independent copy of the stack pages.

10. **What is `pivot_root` and how does it differ from `chroot`?**
    *A:* `pivot_root` physically swaps the old root mount with a new one and can then unmount the old root entirely. `chroot` merely changes the process's view of `/` but the old root remains fully accessible via `../../..` escape tricks. Production containers (Docker, etc.) use `pivot_root` for stronger isolation.

11. **What would happen if you used `CLONE_VM` alongside the namespace flags?**
    *A:* The child would share the parent's virtual memory space (like a thread), meaning the child's `chroot()` and `mount()` calls could corrupt the parent's address space. We deliberately omit `CLONE_VM` so the child gets its own copy-on-write memory.

### Task 2 — IPC & CLI (Extra)

6. **Why does the event loop use `poll()` with a 200ms timeout rather than a blocking `accept()`?**
   *A:* A blocking `accept()` would prevent the supervisor from checking signal flags (`sigchld_received`, `supervisor_interrupted`). The 200ms poll timeout ensures we periodically regain control to reap zombie children and respond to `SIGINT`, while still being responsive to incoming CLI connections.

7. **Why is the signal handler (`sigchld_handler`) so minimal — just setting a flag?**
   *A:* Signal handlers run in an asynchronous, interrupted context. Only "async-signal-safe" functions (like writing to a `sig_atomic_t`) are allowed. Calling `waitpid()`, `printf()`, or `pthread_mutex_lock()` inside the handler risks deadlock or corruption. So we defer the real work to the main event loop.

8. **What is `MSG_WAITALL` and why is it used on `recv()`?**
   *A:* `MSG_WAITALL` tells the kernel to block until the full `sizeof(req)` bytes have arrived. Without it, `recv()` could return a partial read on a stream socket, leading to deserialization bugs where half a struct is interpreted as a complete request.

9. **What is the `SA_RESTART` flag in `sigaction` and why is it important here?**
   *A:* `SA_RESTART` tells the kernel to automatically restart interrupted system calls (like `poll()`, `accept()`, `read()`) instead of returning `EINTR`. Without it, every signal delivery would cause our `poll()` to return early with an error, requiring us to manually retry everywhere.

10. **Could you replace Unix domain sockets with shared memory for the CLI? What trade-offs?**
    *A:* Yes, but shared memory would require manual synchronization (semaphores/mutexes for the shared region), a notification mechanism (like a futex), and careful memory layout. Unix domain sockets give us built-in framing, blocking, and request-response semantics with zero extra synchronization code.

### Task 3 — Logging (Extra)

5. **Why is the bounded buffer implemented as a circular array (ring buffer) instead of a linked list?**
   *A:* A circular array has fixed memory footprint (`LOG_BUFFER_CAPACITY` items pre-allocated), O(1) push/pop via `head`/`tail` index arithmetic, and excellent cache locality. A linked list would require `malloc`/`free` per item, adding overhead and fragmentation under high throughput.

6. **What does `pthread_cond_signal` do versus `pthread_cond_broadcast`?**
   *A:* `signal` wakes exactly one waiting thread; `broadcast` wakes all of them. We use `signal` during normal push/pop (only one consumer/producer needs to wake), but `broadcast` during shutdown so that *all* blocked threads wake up and can check `shutting_down`.

7. **Why does the producer thread call `pthread_detach` on itself?**
   *A:* A detached thread's resources are automatically reclaimed when it finishes — no one needs to call `pthread_join()`. Since we spawn one producer per container and don't need to synchronize on their termination individually, detaching avoids resource leaks.

8. **What happens if a container writes to stdout faster than the consumer can flush to disk?**
   *A:* The bounded buffer fills up (16 items). The producer thread blocks on `pthread_cond_wait(&not_full, ...)`. Since the pipe between the container and the producer also has a kernel buffer (~64KB), once that fills, the container's own `write()` to stdout will block. This creates natural backpressure all the way to the container process.

9. **Why does the consumer open and close the log file on every write instead of keeping the fd open?**
   *A:* The consumer thread handles logs for *all* containers via a single thread. Since different items may be for different container IDs (different log files), it opens the correct file per-item with `O_APPEND`. A production version could cache open file descriptors per container ID for efficiency.

### Task 4 — Kernel Module (Extra)

4. **What is `copy_from_user` and why can't the kernel just dereference the user pointer directly?**
   *A:* User-space pointers live in virtual address ranges that may be paged out, invalid, or malicious. `copy_from_user` safely copies data while handling page faults and verifying the pointer belongs to the calling process. Directly dereferencing a user pointer from kernel space is a critical security vulnerability (arbitrary kernel read/write).

5. **What are `jiffies` and `HZ`?**
   *A:* `jiffies` is a global kernel counter incremented on every timer interrupt. `HZ` is how many timer interrupts occur per second (commonly 250 or 1000). So `jiffies + 1 * HZ` means "fire one second from now".

6. **Why use `del_timer_sync()` instead of `del_timer()` during module exit?**
   *A:* `del_timer_sync()` guarantees that the timer callback is not currently running on any CPU when it returns. Plain `del_timer()` only dequeues the timer but the callback might still be executing on another core, leading to use-after-free when we immediately `kfree` all nodes.

7. **What is `rcu_read_lock()` in `get_rss_bytes` and why is it needed?**
   *A:* RCU (Read-Copy-Update) is a kernel synchronization mechanism for read-heavy workloads. `rcu_read_lock()` guarantees that the task_struct we look up via `find_vpid()` won't be freed while we hold the RCU read lock. Without it, the process could exit between `find_vpid` and our access, causing a use-after-free.

8. **Could you use a spinlock instead of a mutex for `monitor_lock`? Why or why not?**
   *A:* Not safely. Our critical sections call `kmalloc(GFP_KERNEL)` and `get_task_mm()`, both of which may sleep (wait for memory or page I/O). Spinlocks disable preemption and you **must not sleep** while holding one — doing so would deadlock the CPU. Mutexes allow sleeping, making them the correct choice here.

9. **What is a character device and why did we register one?**
   *A:* A character device (`cdev`) is a kernel interface exposed as a file in `/dev/`. It supports operations like `open`, `read`, `write`, and `ioctl`. We register one (`/dev/container_monitor`) so user-space programs can communicate with our kernel module using standard file system calls — specifically `ioctl()` to register/unregister containers.

### Task 5 — Scheduler (Extra)

3. **What is `vruntime` in CFS?**
   *A:* Virtual runtime is the weighted CPU time a process has consumed. CFS always picks the process with the *smallest* `vruntime` to run next. A process with `nice -20` accumulates `vruntime` very slowly (gets more real CPU), while `nice +19` accumulates fast (gets less CPU).

4. **What is the difference between `nice` and `real-time` scheduling classes?**
   *A:* `nice` adjusts priority *within* the CFS (default) scheduler class. Real-time classes (`SCHED_FIFO`, `SCHED_RR`) preempt CFS entirely — an RT process always runs before any CFS process, regardless of nice values.

5. **Why call `setpriority()` inside the child after `clone()` rather than from the parent?**
   *A:* Setting priority in the child ensures the nice value only applies to the container process. If we set it in the parent before `clone()`, the supervisor itself would inherit the altered priority, which could make the supervisor unresponsive at `nice 19`.

---

## General OS Theory Questions

1. **What is a system call? How does it differ from a regular function call?**
   *A:* A system call is a controlled entry point into the kernel. It triggers a mode switch from user-mode (Ring 3) to kernel-mode (Ring 0) via a software interrupt (`syscall` instruction on x86-64). A regular function call stays entirely in user-space with no privilege change.

2. **What is the difference between a process and a thread?**
   *A:* A process has its own virtual address space, file descriptor table, and PID. Threads within a process share the same address space and resources but have their own stack and program counter. In Linux, both are `task_struct` objects — threads are created with `CLONE_VM | CLONE_FILES | CLONE_SIGHAND`.

3. **Explain the difference between user space and kernel space.**
   *A:* Kernel space has unrestricted access to hardware and all memory. User space is restricted — processes can only access their own virtual memory and must use system calls to request kernel services. This separation prevents buggy or malicious programs from crashing the entire system.

4. **What is a page fault? When does it occur?**
   *A:* A page fault occurs when a process accesses a virtual address that isn't currently mapped to a physical page. The kernel handles it by allocating a physical frame, loading data from disk (if swapped), or killing the process (if the address is invalid — segfault).

5. **What is deadlock? What are the four Coffman conditions?**
   *A:* Deadlock is a state where two or more processes are each waiting for resources held by the others, and none can proceed. The four conditions are: (1) Mutual Exclusion, (2) Hold and Wait, (3) No Preemption, (4) Circular Wait. All four must hold simultaneously for deadlock.

6. **What is a race condition? Give an example from your project.**
   *A:* A race condition occurs when the system's behavior depends on the non-deterministic ordering of concurrent events. Example: if the SIGCHLD handler directly modified `metadata_table` while the CLI thread was iterating it for `ps`, both could corrupt the linked list pointers simultaneously.

7. **What is virtual memory? Why is it important?**
   *A:* Virtual memory gives each process the illusion of a large, contiguous address space. The MMU translates virtual addresses to physical addresses using page tables. It enables process isolation (one process can't access another's memory), memory overcommit, and demand paging.

8. **What is `dup2()` and why is it used in your container's `child_fn`?**
   *A:* `dup2(old_fd, new_fd)` duplicates `old_fd` onto `new_fd`, closing `new_fd` first if open. We call `dup2(cfg->log_write_fd, STDOUT_FILENO)` so that whenever the container writes to stdout (fd 1), it actually goes into our logging pipe — transparently redirecting output without the container knowing.

---

## Tricky Curveball Questions

1. **If a container escapes `chroot` via `../../..`, how would you prevent that?**
   *A:* Use `pivot_root` with a mount namespace instead of plain `chroot`. After `pivot_root`, the old root is unmounted entirely — there's no path to escape to. Additionally, drop capabilities like `CAP_SYS_CHROOT` inside the container to prevent re-calling `chroot`.

2. **Your metadata table is a linked list. What's the time complexity of `ps`? Could you improve it?**
   *A:* It's O(n) where n is the number of containers. For this project with a handful of containers, it's fine. For scale, a hash table keyed on container ID would give O(1) lookups, or a balanced tree for ordered iteration.

3. **What would happen if you forgot to call `close(pipefd[1])` in the parent after `clone()`?**
   *A:* The parent would hold an open reference to the write end of the pipe. When the child exits, the producer thread's `read()` would **never return 0** (EOF), because the kernel only signals EOF when *all* write-end file descriptors are closed. The producer thread would hang indefinitely.

4. **Can SIGKILL be caught or ignored by a process?**
   *A:* No. `SIGKILL` (signal 9) and `SIGSTOP` are the two signals that can never be caught, blocked, or ignored. That's precisely why our kernel monitor and `stop` command use `SIGKILL` — it guarantees termination regardless of what the container process tries to do.

5. **Why does your project need root privileges to run?**
   *A:* Several operations require root: `clone()` with namespace flags creates new namespaces (requires `CAP_SYS_ADMIN`), `chroot()` requires `CAP_SYS_CHROOT`, `mount("proc", ...)` requires `CAP_SYS_ADMIN`, and `insmod`/`rmmod` for the kernel module requires `CAP_SYS_MODULE`. All of these map to root by default.

6. **What's the difference between `exec` and `fork`? Why does your container use `execl` after `clone`?**
   *A:* `fork()/clone()` creates a new process by duplicating the caller. `exec()` replaces the current process's image with a new program. We separate them because we need to set up the namespace environment (chroot, mount, dup2) *before* replacing the process image with the container's command.

7. **If two containers write to stdout simultaneously, can their log entries get interleaved?**
   *A:* Each container has its own pipe and its own producer thread. The producer reads from the pipe and pushes complete chunks into the bounded buffer. Since the consumer pops and writes one complete `log_item_t` at a time per container, entries from different containers won't be interleaved within a single chunk. However, chunks from different containers may be interleaved *across* the log file if you were writing to a single shared log file.

8. **How does Docker differ from your project architecturally?**
   *A:* Docker uses `runc` (which calls `clone` with namespaces + cgroups), an `overlay` filesystem instead of plain `chroot`, `seccomp` filters for syscall restriction, capability dropping, network namespaces with virtual bridges, and a full OCI image specification. Our project demonstrates the same foundational primitives (namespaces, IPC, kernel enforcement) at a minimal educational scale.
