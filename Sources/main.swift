//  main.swift
//  ZoomHooks

@preconcurrency import Cocoa
@preconcurrency import ApplicationServices
import Darwin

@MainActor
@discardableResult
func ensureAccessibilityPermissions(prompt: Bool = true) -> Bool {
    // Use the public constant directly; no dlopen/dlsym or force unwraps.
    let options = [("kAXTrustedCheckOptionPrompt" as CFString): prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

@MainActor
final class ZoomAXMonitor {
    private let pid: pid_t
    private var observer: AXObserver?
    private let appElement: AXUIElement
    private var openWindows = Set<UnsafeRawPointer>()

    init(pid: pid_t) {
        self.pid = pid
        self.appElement = AXUIElementCreateApplication(pid)
    }

    func start() throws {
        var obs: AXObserver?
        let err = AXObserverCreate(pid, { _, element, notification, refcon in
            guard let refcon = refcon else { return }
            let monitor = Unmanaged<ZoomAXMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.handle(element: element, notification: notification as String)
        }, &obs)
        guard err == .success, let axObs = obs else {
            throw MonitorError.createObserverFailed
        }
        observer = axObs

        // Subscribe to window create/destroy
        for notif in [kAXWindowCreatedNotification, kAXUIElementDestroyedNotification] as [CFString] {
            let e = AXObserverAddNotification(axObs, appElement, notif, Unmanaged.passUnretained(self).toOpaque())
            if e != .success {
                fputs("Error subscribing to \(notif): \(e.rawValue)\n", stderr)
            }
        }

        // Add observer to run loop
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(axObs), .defaultMode)
    }

    deinit {
        if let obs = observer {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
    }

    private func handle(element: AXUIElement, notification: String) {
        let key = Unmanaged.passUnretained(element).toOpaque()
        let role = attribute(element, kAXRoleAttribute as CFString) as? String ?? ""
        let title = attribute(element, kAXTitleAttribute as CFString) as? String ?? ""

        if notification == (kAXWindowCreatedNotification as String) {
            if role == (kAXWindowRole as String) && title == "Zoom Meeting" {
                openWindows.insert(key)
                print("Zoom Meeting window CREATED.")
            }
        } else if notification == (kAXUIElementDestroyedNotification as String) {
            if openWindows.remove(key) != nil {
                print("Zoom Meeting window DESTROYED.")
            }
        }
    }

    private func attribute(_ element: AXUIElement, _ attr: CFString) -> AnyObject? {
        var value: AnyObject?
        _ = AXUIElementCopyAttributeValue(element, attr, &value)
        return value
    }

    enum MonitorError: Error { case createObserverFailed }
}

@MainActor
@main
struct ZoomHooksMain {
    static func main() {
        guard ensureAccessibilityPermissions(prompt: true) else {
            fputs("Accessibility permissions are required. Grant access in System Settings > Privacy & Security > Accessibility and re-launch.\n", stderr)
            exit(EXIT_FAILURE)
        }

        if let zoom = NSRunningApplication.runningApplications(withBundleIdentifier: "us.zoom.xos").first,
           !zoom.isTerminated {
            runMonitor(for: zoom.processIdentifier)
        } else {
            waitForZoomAndRun()
        }
    }

    private static func runMonitor(for pid: pid_t) {
        do {
            let monitor = ZoomAXMonitor(pid: pid)
            try monitor.start()
            print("AXObserver for zoom.us established (PID \(pid)).")
            trapSIGINTForCleanExit()
            CFRunLoopRun()
        } catch {
            fputs("Failed to create AXObserver: \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    private static func waitForZoomAndRun() {
        let center = NSWorkspace.shared.notificationCenter
        let token = center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "us.zoom.xos" else { return }
            Task { @MainActor in
                runMonitor(for: app.processIdentifier)
            }
        }
        print("Waiting for Zoom (us.zoom.xos) to launch…")
        trapSIGINTForCleanExit()
        CFRunLoopRun()
        center.removeObserver(token)
    }

    private static func trapSIGINTForCleanExit() {
        signal(SIGINT) { _ in
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
    }
}