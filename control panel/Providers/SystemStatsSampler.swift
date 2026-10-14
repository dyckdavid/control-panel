import Foundation
import Darwin

/// One reading of processor, memory, and load.
nonisolated struct SystemStatsSample: Sendable {
    /// Fraction of total CPU time spent busy since the previous sample, 0…1.
    let cpuBusy: Double
    let cpuUser: Double
    let cpuSystem: Double
    /// "Memory Used" as Activity Monitor defines it: app memory + wired + compressed.
    let memoryUsed: UInt64
    let memoryTotal: UInt64
    let loadAverage: (one: Double, five: Double, fifteen: Double)

    var memoryFraction: Double {
        memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0
    }
}

/// Reads CPU, memory, and load straight from the kernel.
///
/// This replaces running `top -l 1` every few seconds, which cost about half
/// a second of CPU per sample and then had to be scraped as text. The Mach
/// host calls here return the same counters in microseconds.
///
/// CPU usage is a rate, so it needs two readings: each `sample()` compares the
/// tick counters with the previous call. The first call therefore reports the
/// average since boot.
nonisolated final class SystemStatsSampler: @unchecked Sendable {
    private let host = mach_host_self()
    private let lock = NSLock()
    private var previousTicks: CPUTicks?

    deinit {
        mach_port_deallocate(mach_task_self_, host)
    }

    func sample() -> SystemStatsSample? {
        guard let ticks = readCPUTicks(), let memory = readMemory() else { return nil }

        lock.lock()
        let previous = previousTicks
        previousTicks = ticks
        lock.unlock()

        let delta = previous.map { ticks.since($0) } ?? ticks
        let total = Double(delta.total)

        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)

        return SystemStatsSample(
            cpuBusy: total > 0 ? Double(delta.user + delta.system + delta.nice) / total : 0,
            cpuUser: total > 0 ? Double(delta.user + delta.nice) / total : 0,
            cpuSystem: total > 0 ? Double(delta.system) / total : 0,
            memoryUsed: memory.used,
            memoryTotal: memory.total,
            loadAverage: (loads[0], loads[1], loads[2])
        )
    }

    // MARK: CPU

    private struct CPUTicks {
        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        var nice: UInt64 = 0

        var total: UInt64 { user + system + idle + nice }

        /// The kernel keeps 32-bit counters that wrap, so differences use
        /// wrapping arithmetic on each counter.
        func since(_ earlier: CPUTicks) -> CPUTicks {
            CPUTicks(
                user: UInt64(UInt32(truncatingIfNeeded: user) &- UInt32(truncatingIfNeeded: earlier.user)),
                system: UInt64(UInt32(truncatingIfNeeded: system) &- UInt32(truncatingIfNeeded: earlier.system)),
                idle: UInt64(UInt32(truncatingIfNeeded: idle) &- UInt32(truncatingIfNeeded: earlier.idle)),
                nice: UInt64(UInt32(truncatingIfNeeded: nice) &- UInt32(truncatingIfNeeded: earlier.nice))
            )
        }
    }

    /// Sums the per-core tick counters reported by `host_processor_info`.
    private func readCPUTicks() -> CPUTicks? {
        var coreCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &coreCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }

        // The kernel allocates this array in our address space; hand it back.
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            )
        }

        var ticks = CPUTicks()
        let stride = Int(CPU_STATE_MAX)
        for core in 0..<Int(coreCount) {
            let base = core * stride
            // Counters are unsigned in practice; reinterpret to avoid sign
            // extension when a core's count passes 2^31.
            ticks.user += UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            ticks.system += UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            ticks.idle += UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            ticks.nice += UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
        }
        return ticks
    }

    // MARK: Memory

    private func readMemory() -> (used: UInt64, total: UInt64)? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        host_page_size(host, &pageSize)
        let page = UInt64(pageSize)

        // Activity Monitor's "Memory Used": app memory (anonymous pages that
        // are not purgeable) plus wired plus compressed.
        let appPages = UInt64(stats.internal_page_count) - min(UInt64(stats.purgeable_count), UInt64(stats.internal_page_count))
        let usedPages = appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)

        return (usedPages * page, ProcessInfo.processInfo.physicalMemory)
    }
}
