# zoom-hooks

> DEPRECATED  
> Dropped this custom monitor by an [Hammerspoon](https://www.hammerspoon.org/) [custom script](https://gist.github.com/fopina/af078ef1c03b48c2bcc294da9e282f6a)  
> This was a work in progress anyway — just a detection test, missing configurable commands to run on window creation and destruction

A tiny macOS Swift command-line tool that listens to Zoom window events via the macOS Accessibility (AX) API and logs when a “Zoom Meeting” window is created or destroyed. Useful as a building block to trigger local automations whenever you join/leave a Zoom meeting.

- Language/Build: Swift Package Manager (swift-tools-version: 6.0)
- Target: Executable
- Zoom bundle id monitored: us.zoom.xos

## Requirements

- macOS with Accessibility (AX) permission enabled for your terminal (or the built binary)
- Swift 6 toolchain (SPM)
- Zoom desktop app running (bundle id: us.zoom.xos)

## Install / Build

Clone this repository, then:

- Run directly with SwiftPM:
  ```sh
  swift run zoom-hooks
  ```

- Build a release binary:
  ```sh
  swift build -c release
  # Run:
  .build/release/zoom-hooks
  ```

Note: On first run the tool will request Accessibility permission.

## Permissions (Accessibility)

This tool needs the macOS Accessibility permission to observe window events.

- When prompted, allow access.
- If you don’t see a prompt or the app exits with a permissions message:
  - Open System Settings → Privacy & Security → Accessibility
  - Enable your Terminal app (or the specific built binary you plan to run)
  - Re-run the command

## Usage

1) Start the Zoom desktop app.  
2) In this repository folder, run:
   ```sh
   swift run zoom-hooks
   # or:
   .build/release/zoom-hooks
   ```

Example output:
```
Accessibility permissions granted. (AX monitoring will begin here.)
Found zoom.us PID: 12345
AXObserver for zoom.us established.
Zoom Meeting window CREATED.
Zoom Meeting window DESTROYED.
```

If Zoom is not running, you’ll see:
```
Could not find running zoom.us process.
```

## How it works (technical)

- Ensures AX permission via AXIsProcessTrustedWithOptions (and prompts if needed).
- Locates the running Zoom process (bundle id us.zoom.xos).
- Creates an AXUIElement for the Zoom app and an AXObserver.
- Subscribes to:
  - kAXWindowCreatedNotification
  - kAXUIElementDestroyedNotification
- Tracks AX elements whose role is kAXWindowRole and whose title equals "Zoom Meeting", printing CREATED/DESTROYED events.

Note: Matching relies on the window title “Zoom Meeting”. If your Zoom UI is localized or differs, adjust the title match in Sources/main.swift.

## Troubleshooting

- “Accessibility permissions are required…”:
  - Add Terminal (or the binary) to System Settings → Privacy & Security → Accessibility, then relaunch.
- “Could not find running zoom.us process.”:
  - Ensure the Zoom desktop app is running. Verify the bundle id is us.zoom.xos.
- No events:
  - Join/leave a meeting to create/destroy windows.
  - Confirm the window title in your Zoom version matches “Zoom Meeting”.

## Customization

- Event types: Add/remove AX notifications in Sources/main.swift to track more events.
- Matching logic: Change the role/title check to match different window titles or additional windows.
- Automations: Pipe output to scripts or a Shortcuts/launchd wrapper to trigger actions on CREATED/DESTROYED.

## License

MIT
