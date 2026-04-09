//
//  TerminalJumper.swift
//  ClaudeIsland
//
//  Unified terminal jumping service.
//  Detects which terminal app hosts a Claude session and activates the correct window/tab.
//

import AppKit
import Foundation

actor TerminalJumper {
    static let shared = TerminalJumper()

    /// Timestamp of the last jump — used to suppress notifications briefly after jumping
    @MainActor static var lastJumpTime: Date = .distantPast

    private init() {}

    /// Jump to the terminal hosting the given session.
    /// Tries strategies in order: tmux+Yabai → AppleScript → generic activate.
    func jump(to session: SessionState) async -> Bool {
        await MainActor.run {
            Self.lastJumpTime = Date()
            AppDelegate.shared?.windowController?.viewModel.notchClose()
        }
        let cwd = session.cwd
        let pid = session.pid
        let terminalApp = session.terminalApp ?? ""
        DebugLogger.log("Jump", "termApp=\(terminalApp) entry=\(session.entrypoint ?? "nil") cwd=\(cwd) sid=\(session.sessionId.prefix(8))")

        // Pikabot/SDK sessions run via web app — jump to Safari localhost tab
        if let entry = session.entrypoint,
           entry.contains("sdk") || entry.contains("pikabot") {
            return await jumpToSafariLocalhost()
        }

        // 1. Tmux + Yabai (most precise for tmux sessions)
        if session.isInTmux {
            if let pid = pid {
                if await YabaiController.shared.focusWindow(forClaudePid: pid) {
                    return true
                }
            }
            if await YabaiController.shared.focusWindow(forWorkingDirectory: cwd) {
                return true
            }
        }

        // 2. AppleScript strategies for specific terminals
        let lower = terminalApp.lowercased()

        if lower.contains("vs code") || lower.contains("cursor") {
            if await jumpViaVSCode(cwd: cwd) { return true }
        }

        if lower.contains("iterm") {
            if await jumpViaiTerm2(cwd: cwd, pid: pid) { return true }
        }

        if lower.contains("terminal") && !lower.contains("wez") {
            if await jumpViaTerminalApp(cwd: cwd, pid: pid) { return true }
        }

        if lower.contains("cmux") {
            if await jumpViaCmux(cwd: cwd, sessionId: session.sessionId) { return true }
        }

        if lower.contains("ghostty") {
            if await jumpViaGhostty(cwd: cwd) { return true }
        }

        if lower.contains("kitty") {
            if await jumpViaKitty(cwd: cwd) { return true }
        }

        if lower.contains("wezterm") {
            if await jumpViaWezTerm(cwd: cwd) { return true }
        }

        if lower.contains("warp") {
            if await activateByBundleId("warp") { return true }
        }

        if lower.contains("alacritty") {
            if await activateByBundleId("alacritty") { return true }
        }

        if lower.contains("hyper") {
            if await activateByBundleId("hyper") { return true }
        }

        // 3. If a known terminal was matched above but its strategy failed,
        //    don't try other terminals — only fall through for truly unknown terminals
        let knownTerminals = ["iterm", "terminal", "cmux", "ghostty", "kitty", "wezterm", "warp",
                              "alacritty", "hyper", "vs code", "cursor"]
        let isKnownTerminal = knownTerminals.contains { lower.contains($0) }

        if !isKnownTerminal {
            // Unknown terminal — try actual terminals first, VS Code/Cursor last
            if await jumpViaCmux(cwd: cwd, sessionId: session.sessionId) { return true }
            if await jumpViaGhostty(cwd: cwd) { return true }
            if await jumpViaiTerm2(cwd: cwd, pid: pid) { return true }
            if await jumpViaTerminalApp(cwd: cwd, pid: pid) { return true }
            if await jumpViaVSCode(cwd: cwd) { return true }
        }

        // 4. Generic fallback: activate terminal app by bundle ID
        if !terminalApp.isEmpty {
            if await activateByBundleId(terminalApp) { return true }
        }

        return false
    }

    // MARK: - iTerm2 (AppleScript — rich API)

    private func jumpViaiTerm2(cwd: String, pid: Int?) async -> Bool {
        // Try matching by TTY first (most reliable), then fall back to directory name
        let ttyMatch = pid.flatMap { Self.ttyForPid($0) }
        let dirName = URL(fileURLWithPath: cwd).lastPathComponent

        let matchCondition: String
        if let tty = ttyMatch {
            matchCondition = "tty of s is \"\(tty)\""
        } else {
            matchCondition = "name of s contains \"\(dirName)\""
        }

        let script = """
        tell application "System Events"
            if not (exists process "iTerm2") then return false
        end tell
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        try
                            if \(matchCondition) then
                                select t
                                select s
                                activate
                                return true
                            end if
                        end try
                    end repeat
                end repeat
            end repeat
            return false
        end tell
        """
        return await runAppleScript(script)
    }

    /// Get the TTY device path for a given PID by walking up the process tree
    private static func ttyForPid(_ pid: Int) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "tty="]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let tty = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !tty.isEmpty, tty != "??" else { return nil }
            return "/dev/" + tty
        } catch {
            return nil
        }
    }

    // MARK: - Terminal.app (AppleScript)

    private func jumpViaTerminalApp(cwd: String, pid: Int?) async -> Bool {
        let dirName = URL(fileURLWithPath: cwd).lastPathComponent
        let script = """
        tell application "System Events"
            if not (exists process "Terminal") then return false
        end tell
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        if custom title of t contains "\(dirName)" or history of t contains "\(dirName)" then
                            set selected tab of w to t
                            set frontmost of w to true
                            activate
                            return true
                        end if
                    end try
                end repeat
            end repeat
            return false
        end tell
        """
        return await runAppleScript(script)
    }

    // MARK: - cmux (CLI)

    private func jumpViaCmux(cwd: String, sessionId: String? = nil) async -> Bool {
        let cmuxPath = "/Applications/cmux.app/Contents/Resources/bin/cmux"
        guard FileManager.default.isExecutableFile(atPath: cmuxPath) else { return false }

        // Use cmux find-window --content --select to search and jump in one command
        let dirName = URL(fileURLWithPath: cwd).lastPathComponent

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: cmuxPath)
        process.arguments = ["find-window", "--content", "--select", dirName]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            if process.terminationStatus == 0,
               let output = String(data: data, encoding: .utf8),
               output.contains("workspace:") {
                DebugLogger.log("Jump", "cmux matched: \(output.prefix(60))")
                await bringCmuxToFront()
                return true
            }
        } catch {}

        DebugLogger.log("Jump", "cmux no match for '\(dirName)'")
        return false
    }

    // MARK: - Ghostty (AppleScript)

    private func jumpViaGhostty(cwd: String) async -> Bool {
        let script = """
        tell application "System Events"
            if not (exists process "Ghostty") then return false
        end tell
        tell application "Ghostty"
            set matches to every terminal whose working directory contains "\(cwd)"
            if (count of matches) > 0 then
                focus (item 1 of matches)
                return true
            end if
            activate
            return true
        end tell
        """
        return await runAppleScript(script)
    }

    // MARK: - Kitty (CLI remote control)

    private func jumpViaKitty(cwd: String) async -> Bool {
        let kittyPaths = ["/opt/homebrew/bin/kitty", "/usr/local/bin/kitty",
                          "/Applications/kitty.app/Contents/MacOS/kitty"]
        guard let kittyPath = kittyPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return await activateByBundleId("kitty")
        }
        do {
            _ = try await ProcessExecutor.shared.run(kittyPath, arguments: [
                "@", "focus-window", "--match", "cwd:\(cwd)"
            ])
            await activateApp("kitty")
            return true
        } catch {
            return await activateByBundleId("kitty")
        }
    }

    // MARK: - WezTerm (CLI)

    private func jumpViaWezTerm(cwd: String) async -> Bool {
        let wezPaths = ["/opt/homebrew/bin/wezterm", "/usr/local/bin/wezterm",
                        "/Applications/WezTerm.app/Contents/MacOS/wezterm"]
        guard let wezPath = wezPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return await activateByBundleId("wezterm")
        }
        do {
            let output = try await ProcessExecutor.shared.run(wezPath, arguments: [
                "cli", "list", "--format", "json"
            ])
            if output.contains(cwd) {
                await activateApp("WezTerm")
                return true
            }
        } catch {}
        return await activateByBundleId("wezterm")
    }

    // MARK: - VS Code / Cursor (System Events)

    private func jumpViaVSCode(cwd: String) async -> Bool {
        let dirName = URL(fileURLWithPath: cwd).lastPathComponent

        // Try VS Code, then Cursor
        let editors: [(bundleId: String, processName: String, cli: String)] = [
            ("com.microsoft.VSCode", "Code", "/usr/local/bin/code"),
            ("com.todesktop.230313mzl4w4u92", "Cursor", "/usr/local/bin/cursor"),
        ]

        for editor in editors {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: editor.bundleId)
            guard !apps.isEmpty else { continue }

            // AppleScript: find the window whose title contains the project dir and raise it
            let script = """
            tell application "System Events"
                tell process "\(editor.processName)"
                    try
                        repeat with w in windows
                            if name of w contains "\(dirName)" then
                                perform action "AXRaise" of w
                                set frontmost to true
                                return true
                            end if
                        end repeat
                    end try
                end tell
            end tell
            return false
            """
            if await runAppleScript(script) { return true }

            // Fallback: use CLI to open the folder
            if FileManager.default.isExecutableFile(atPath: editor.cli) {
                do {
                    _ = try await ProcessExecutor.shared.run(editor.cli, arguments: [cwd])
                    return true
                } catch {}
            }

            // Last resort: just activate the app
            if let app = apps.first {
                app.activate()
                return true
            }
        }
        return false
    }

    // MARK: - Generic Bundle ID Activation

    @discardableResult
    private func activateByBundleId(_ terminalApp: String) async -> Bool {
        let lower = terminalApp.lowercased()

        let bundleMap: [(match: String, bundleId: String)] = [
            ("iterm", "com.googlecode.iterm2"),
            ("terminal", "com.apple.Terminal"),
            ("ghostty", "com.mitchellh.ghostty"),
            ("alacritty", "io.alacritty"),
            ("kitty", "net.kovidgoyal.kitty"),
            ("warp", "dev.warp.Warp-Stable"),
            ("wezterm", "com.github.wez.wezterm"),
            ("hyper", "co.zeit.hyper"),
            ("cmux", "com.cmuxterm.app"),
        ]

        for (match, bundleId) in bundleMap {
            if lower.contains(match) {
                return activateRunningApp(bundleId: bundleId)
            }
        }
        return false
    }

    // MARK: - Safari (for pikabot/web-based sessions)

    private func jumpToSafariLocalhost() async -> Bool {
        // Try Safari Web App (standalone PWA) first — look for "pika" or "localhost" in window title
        let webAppScript = """
        tell application "System Events"
            repeat with p in every process
                try
                    if name of p contains "pika" or name of p contains "Web App" then
                        set bundleId to bundle identifier of p
                        if bundleId contains "Safari.WebApp" then
                            set frontmost of p to true
                            return true
                        end if
                    end if
                end try
            end repeat
            return false
        end tell
        """
        if await runAppleScript(webAppScript) { return true }

        // Fallback: try regular Safari
        let safariScript = """
        tell application "System Events"
            if not (exists process "Safari") then return false
        end tell
        tell application "Safari"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        if URL of t contains "localhost" then
                            set current tab of w to t
                            set index of w to 1
                            activate
                            return true
                        end if
                    end try
                end repeat
            end repeat
            return false
        end tell
        """
        return await runAppleScript(safariScript)
    }

    @discardableResult
    private func activateRunningApp(bundleId: String) -> Bool {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            return app.activate()
        }
        return false
    }

    @discardableResult
    private func activateApp(_ name: String) async -> Bool {
        let script = "tell application \"\(name)\" to activate"
        return await runAppleScript(script)
    }

    // MARK: - cmux Activation

    private func bringCmuxToFront() async {
        // Use AppleScript to ensure cmux is frontmost
        _ = await runAppleScript("tell application \"cmux\" to activate")
    }

    // MARK: - AppleScript Runner

    private func runAppleScript(_ source: String) async -> Bool {
        do {
            let result = try await ProcessExecutor.shared.run("/usr/bin/osascript", arguments: ["-e", source])
            return result.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        } catch {
            return false
        }
    }
}
