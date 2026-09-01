import Foundation
import Darwin

// MARK: - JailbreakDetector
//
// Detects compromised runtime environments that could allow API key extraction,
// memory scraping, or method swizzling of VerbaDoc's security controls.
//
// Signals checked (4 independent vectors)
// ─────────────────────────────────────────
//  1. File system  — presence of jailbreak tooling (Cydia, Substrate, bash, ssh, apt)
//  2. Sandbox      — attempt to write outside the app's sandbox
//  3. Environment  — DYLD_INSERT_LIBRARIES set (Frida / Substrate injection)
//  4. Debugger     — ptrace / sysctl check for PT_TRACED flag
//
// Simulator exemption: always returns .clear in Simulator builds
// (running on simulator for development is legitimate).
//
// Usage
// ─────
//  Call JailbreakDetector.assess() at app launch and before any API call.
//  .clear  → proceed normally
//  .jailbroken(signals:) → block the call, show a warning, do NOT crash silently

enum JailbreakDetector {

    enum Assessment: Equatable {
        case clear
        case jailbroken(signals: [String])
    }

    // MARK: - Main Assessment

    static func assess() -> Assessment {
#if targetEnvironment(simulator) || DEBUG
        // Debug builds run under Xcode's LLDB (P_TRACED) and on devices where
        // /bin/sh exists — skip checks that would always fire during development.
        return .clear
#else
        var signals: [String] = []

        if checkFileSystemArtifacts() { signals.append("jailbreak_files") }
        if checkSandboxEscape()        { signals.append("sandbox_breach") }
        if checkDyldInjection()        { signals.append("dyld_injection") }
        if checkDebuggerAttached()     { signals.append("debugger") }

        return signals.isEmpty ? .clear : .jailbroken(signals: signals)
#endif
    }

    // Convenience: returns true when any jailbreak signal is detected.
    static var isCompromised: Bool {
        if case .jailbroken = assess() { return true }
        return false
    }

    // MARK: - Vector 1: File System Artifacts

    private static func checkFileSystemArtifacts() -> Bool {
        let jailbreakPaths: [String] = [
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/Applications/Zebra.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/Library/MobileSubstrate/DynamicLibraries",
            "/private/var/lib/apt",
            "/private/var/lib/cydia",
            "/private/var/stash",
            "/usr/sbin/sshd",
            "/usr/bin/ssh",
            "/usr/libexec/ssh-keysign",
            "/etc/apt",
            "/bin/bash"
            // Note: /bin/sh exists on stock iOS — not a reliable jailbreak signal
        ]
        let fm = FileManager.default
        return jailbreakPaths.contains { fm.fileExists(atPath: $0) }
    }

    // MARK: - Vector 2: Sandbox Escape

    private static func checkSandboxEscape() -> Bool {
        let path = "/private/VerbaDoc_\(UUID().uuidString)"
        do {
            try "probe".write(toFile: path, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: path)
            return true   // Wrote outside sandbox — jailbroken
        } catch {
            return false  // Expected on a non-jailbroken device
        }
    }

    // MARK: - Vector 3: DYLD Injection

    private static func checkDyldInjection() -> Bool {
        // On stock iOS the kernel strips these before app launch.
        // If they're present, a jailbreak tool has set them.
        let injectionVars = ["DYLD_INSERT_LIBRARIES", "DYLD_LIBRARY_PATH", "_MSSafeMode"]
        return injectionVars.contains { getenv($0) != nil }
    }

    // MARK: - Vector 4: Debugger / PT_TRACED

    private static func checkDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }
}
