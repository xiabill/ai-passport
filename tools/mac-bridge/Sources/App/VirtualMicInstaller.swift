import AppKit
import CryptoKit
import Foundation

/// Installs BlackHole 2ch, the virtual microphone the device's audio travels
/// through, on a Mac that does not have one. Before this the user was sent to
/// a download page and left to work out an installer and a restart on their
/// own.
final class VirtualMicInstaller: ObservableObject {
    static let deviceName = "BlackHole 2ch"
    @Published private(set) var busy = false
    @Published private(set) var status = ""

    /// Homebrew's public catalogue names the current release and its checksum,
    /// which is what makes a download from the publisher verifiable.
    private let catalogue = URL(string: "https://formulae.brew.sh/api/cask/blackhole-2ch.json")!

    func install(done: @escaping (Bool) -> Void) {
        guard !busy else { return }
        busy = true
        report("正在查询最新版本…")
        URLSession.shared.dataTask(with: catalogue) { [self] data, _, error in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let link = json["url"] as? String, let url = URL(string: link),
                  // Only ever the publisher's own server, over HTTPS.
                  url.scheme == "https", url.host == "existential.audio",
                  let sha = json["sha256"] as? String,
                  let version = json["version"] as? String
            else {
                return finish(false, "查不到安装包信息：\(error?.localizedDescription ?? "返回内容无法识别")", done)
            }
            report("正在下载 BlackHole \(version)…")
            URLSession.shared.downloadTask(with: url) { [self] file, _, error in
                guard let file, let bytes = try? Data(contentsOf: file) else {
                    return finish(false, "下载失败：\(error?.localizedDescription ?? "未知错误")", done)
                }
                // A package that does not match the published checksum is not
                // the one that was published; it never reaches the installer.
                let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                guard digest == sha.lowercased() else {
                    return finish(false, "安装包校验不通过，已放弃安装", done)
                }
                let pkg = FileManager.default.temporaryDirectory
                    .appendingPathComponent("BlackHole2ch-\(version).pkg")
                try? FileManager.default.removeItem(at: pkg)
                do { try bytes.write(to: pkg) } catch {
                    return finish(false, "无法保存安装包：\(error.localizedDescription)", done)
                }
                report("请在弹出的窗口里输入电脑密码…")
                runInstaller(pkg, done: done)
            }.resume()
        }.resume()
    }

    /// Installing a driver needs an administrator, so macOS asks for the
    /// password. CoreAudio only notices a new driver after it restarts, which
    /// the same privileged step takes care of.
    private func runInstaller(_ pkg: URL, done: @escaping (Bool) -> Void) {
        let path = pkg.path.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
            do shell script "/usr/sbin/installer -pkg " & quoted form of "\(path)" & \
            " -target / && /bin/launchctl kickstart -k system/com.apple.audio.coreaudiod" \
            with administrator privileges
            """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        let err = Pipe()
        task.standardError = err
        do { try task.run() } catch {
            return finish(false, "无法启动安装：\(error.localizedDescription)", done)
        }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            let why = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let cancelled = why.contains("-128")
            return finish(false, cancelled ? "已取消安装" : "安装没有完成：\(why.trimmingCharacters(in: .whitespacesAndNewlines))", done)
        }
        report("安装完成，等待系统识别…")
        waitForDevice(tries: 20, done: done)
    }

    private func waitForDevice(tries: Int, done: @escaping (Bool) -> Void) {
        if AudioOutput.deviceExists(Self.deviceName) {
            return finish(true, "已安装 \(Self.deviceName)，并设为声音输出。别忘了在语音软件里把麦克风也选成它。", done)
        }
        guard tries > 0 else {
            return finish(false, "已安装，但系统还没识别到它。重启电脑后再回来看看。", done)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [self] in
            waitForDevice(tries: tries - 1, done: done)
        }
    }

    private func report(_ text: String) {
        DispatchQueue.main.async { self.status = text }
        Log.audio(text)
    }

    private func finish(_ ok: Bool, _ text: String, _ done: @escaping (Bool) -> Void) {
        Log.audio(text)
        DispatchQueue.main.async {
            self.busy = false
            self.status = text
            done(ok)
        }
    }
}
