//  main.swift
//  ZoomHooks

import Cocoa
import ApplicationServices

import Darwin

@MainActor
func ensureAccessibilityPermissions() {
    let handle = dlopen(nil, RTLD_NOW)
    let sym = dlsym(handle, "kAXTrustedCheckOptionPrompt")
    let ptr = sym!.assumingMemoryBound(to: CFString?.self)
    let prompt = ptr.pointee!
    let options: NSDictionary = [prompt: true]
    let trusted = AXIsProcessTrustedWithOptions(options)
    if !trusted {
        print("Accessibility permissions are required. Please grant access in System Preferences > Security & Privacy > Privacy > Accessibility, then re-launch the app.")
        exit(1)
    }
}

@MainActor
func main() {
    ensureAccessibilityPermissions()
    print("Accessibility permissions granted. (AX monitoring will begin here.)")

    // 1. Find zoom.us process
    guard let zoomApp = NSRunningApplication.runningApplications(withBundleIdentifier: "us.zoom.xos").first,
          zoomApp.isTerminated == false else {
        print("Could not find running zoom.us process.")
        exit(1)
    }
    print("Found zoom.us PID: \(zoomApp.processIdentifier)")

    // 2. Create AXUIElement for zoom.us
    let zoomAXApp = AXUIElementCreateApplication(zoomApp.processIdentifier)

    // 3. Set up AXObserver for window events
    var observer: AXObserver?

    // TRACKING: Store open Zoom Meeting windows by AXUIElementRef hash
    final class WindowTracker {
        var openZoomWindows = Set<Int>()
    }
    let tracker = WindowTracker()
    let trackerPtr = Unmanaged.passUnretained(tracker).toOpaque()

    let callback: AXObserverCallback = { observer, element, notification, refcon in
        guard let refcon = refcon else { return }
        let tracker = Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue()

        // Query AX role
        var value: AnyObject?
        _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        let role = value as? String ?? "(nil)"

        // Query AX title
        var title: AnyObject?
        _ = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
        let windowTitle = title as? String ?? "(no title)"

        let notif = notification as String

        // Simple hash for AXUIElementRef identity
        let elementPtr = Unmanaged.passUnretained(element).toOpaque()
        let elementHash = elementPtr.hashValue

        if notif == kAXWindowCreatedNotification as String {
            if role == kAXWindowRole as String && windowTitle == "Zoom Meeting" {
                tracker.openZoomWindows.insert(elementHash)
                print("Zoom Meeting window CREATED.")
            } else {
                print("Window created with title: \(windowTitle) (role: \(role))")
            }
        } else if notif == kAXUIElementDestroyedNotification as String {
            if tracker.openZoomWindows.contains(elementHash) {
                tracker.openZoomWindows.remove(elementHash)
                print("Zoom Meeting window DESTROYED.")
            } else {
                print("Window destroyed (role: \(role), title: \(windowTitle))")
            }
        } else {
            print("AX Notification: \(notification) for: \(windowTitle) (role: \(role))")
        }
    }

    let pid = zoomApp.processIdentifier
    let result = AXObserverCreate(pid, callback, &observer)
    guard result == .success, let axObserver = observer else {
        print("Failed to create AXObserver for zoom.us")
        exit(1)
    }

    // 4. Subscribe to window creation & destruction
    let notifications = [kAXWindowCreatedNotification, kAXUIElementDestroyedNotification]
    for notif in notifications {
        let error = AXObserverAddNotification(axObserver, zoomAXApp, notif as CFString, trackerPtr)
        if error != .success {
            print("Error subscribing to \(notif): \(error.rawValue)")
        }
    }

    // 5. Add observer to run loop
    CFRunLoopAddSource(CFRunLoopGetCurrent(),
                       AXObserverGetRunLoopSource(axObserver),
                       CFRunLoopMode.defaultMode)
    print("AXObserver for zoom.us established.")

    // Keep the runloop going indefinitely
    CFRunLoopRun()
}

// Entry point for CLI
main()