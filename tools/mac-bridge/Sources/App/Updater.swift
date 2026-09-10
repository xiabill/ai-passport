import AppKit
import FoloVibeCore
import Foundation

/// Checks GitHub for a newer release and installs the macOS app.
///
/// The published app is ad-hoc signed by CI, and an ad-hoc signature ties the
/// macOS permission grants to the binary's hash — installing one as-is would
/// drop Accessibility on every upgrade, the very problem the local signing
/// identity solves. So the downloaded bundle is re-signed with that identity
/// before it replaces the running app.
final class Updater: ObservableObject {
    static let releaseAPI = URL(
        string: "https://api.github.com/repos/xiabill/ai-passport/releases/latest")!

    @Published var status = "尚未检查"
    @Published var latest: ReleaseInfo?
    @Published var busy = false

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var updateAvailable: Bool {
        guard let latest else { return false }
        return versionIsNewer(latest.version, than: currentVersion)
    }

    func check(quiet: Bool = false) {
        if !quiet { status = "正在检查更新…" }
        var request = URLRequest(url: Self.releaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            DispatchQueue.main.async {
                guard let data, let info = ReleaseInfo.parse(data) else {
                    self.status = "检查更新失败：\(error?.localizedDescription ?? "无法解析响应")"
                    return
                }
                self.latest = info
                self.status = self.updateAvailable
                    ? "有新版本 \(info.version)，当前 \(self.currentVersion)"
                    : "已是最新版本 \(self.currentVersion)"
                Log.sys(self.status)
            }
        }.resume()
    }

    func installUpdate() {
        guard let url = latest?.appURL, !busy else { return }
        busy = true
        status = "正在下载 \(latest?.version ?? "")…"
        URLSession.shared.downloadTask(with: url) { [weak self] temp, _, error in
            guard let self else { return }
            guard let temp else {
                DispatchQueue.main.async {
                    self.busy = false
                    self.status = "下载失败：\(error?.localizedDescription ?? "未知错误")"
                }
                return
            }
            // The temporary file disappears when this handler returns.
            let zip = FileManager.default.temporaryDirectory
                .appendingPathComponent("FoloVibeBridge-update.zip")
            try? FileManager.default.removeItem(at: zip)
            do {
                try FileManager.default.moveItem(at: temp, to: zip)
                try self.swapIn(zip)
            } catch {
                DispatchQueue.main.async {
                    self.busy = false
                    self.status = "安装失败：\(error.localizedDescription)"
                }
            }
        }.resume()
    }

    private func swapIn(_ zip: URL) throws {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("folovibe-update", isDirectory: true)
        try? FileManager.default.removeItem(at: work)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
        let unpacked = work.appendingPathComponent("FoloVibeBridge.app")
        guard FileManager.default.fileExists(
            atPath: unpacked.appendingPathComponent("Contents/MacOS/FoloVibeBridge").path)
        else {
            throw NSError(domain: "FoloVibe", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "下载的内容不是完整的 FoloVibeBridge.app",
            ])
        }

        let identity = ProcessInfo.processInfo.environment["FOLO_VIBE_SIGN_IDENTITY"]
            ?? "FoloVibe Bridge Local"
        let installed = Bundle.main.bundleURL.path
        let log = NSHomeDirectory() + "/Library/Logs/folovibe-update.log"

        // Everything happens in the helper: the app cannot replace itself while
        // running, and signing from here used to fail silently, leaving an
        // ad-hoc signature that costs the user their permission grants.
        //
        // The helper must outlive us. Launched as a plain child it shared our
        // process group and died partway through the last upgrade — after ditto,
        // before the relaunch — which is why the app seemed to vanish. nohup in a
        // detached subshell keeps it alive.
        let script = work.appendingPathComponent("install.sh")
        let body = """
            #!/bin/sh
            exec >> "\(log)" 2>&1
            echo "=== $(date '+%F %T') installing \(latest?.version ?? "?") ==="
            while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do
                sleep 0.2
            done
            if security find-identity -p codesigning | grep -q "\(identity)"; then
                codesign --force --sign "\(identity)" \
                    --identifier dev.folovibe.bridge "\(unpacked.path)" \
                    || echo "WARN: re-signing failed; permissions will be asked for again"
            else
                echo "WARN: no local signing identity; permissions will be asked for again"
            fi
            rm -rf "\(installed)" || { echo "FATAL: could not remove the old app"; exit 1; }
            /usr/bin/ditto "\(unpacked.path)" "\(installed)" \
                || { echo "FATAL: install failed; the app is gone from \(installed)"; exit 1; }
            codesign -dv "\(installed)" 2>&1 | grep -E "Identifier|Authority" || true
            open "\(installed)" || echo "WARN: could not reopen the app"
            echo "=== $(date '+%F %T') done ==="
            """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: script.path)

        DispatchQueue.main.async {
            self.status = "正在安装并重启…"
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-c", "nohup /bin/sh '\(script.path)' >/dev/null 2>&1 &"]
            try? task.run()
            task.waitUntilExit()
            NSApp.terminate(nil)
        }
    }

    /// Downloads the firmware asset from the same release the app came from,
    /// so the two halves always match.
    func downloadFirmware(_ done: @escaping (Data?, String?) -> Void) {
        guard let url = latest?.firmwareURL else {
            done(nil, "这个版本没有提供固件文件")
            return
        }
        status = "正在下载固件…"
        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                if let data, !data.isEmpty {
                    done(data, nil)
                } else {
                    done(nil, error?.localizedDescription ?? "下载失败")
                }
            }
        }.resume()
    }

    private func hasSigningIdentity(_ name: String) -> Bool {
        guard let out = try? capture("/usr/bin/security", ["find-identity", "-p", "codesigning"])
        else { return false }
        return out.contains(name)
    }

    @discardableResult
    private func run(_ path: String, _ args: [String]) throws -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        try task.run()
        task.waitUntilExit()
        return task.terminationStatus
    }

    private func capture(_ path: String, _ args: [String]) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
