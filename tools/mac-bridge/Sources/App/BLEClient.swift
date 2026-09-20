import CoreBluetooth
import FoloVibeCore
import Foundation

final class BLEClient: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    /// One connected Passport, as the UI sees it.
    struct Device: Equatable {
        var id: UUID
        var name: String
        var rssi: Int?
        var firmwareVersion: String
        var ready: Bool
        var connected: Bool
        /// The device says another Mac is using it. Only a click takes it over.
        var busyElsewhere: Bool
    }

    /// The aggregate fields keep their old meaning with more than one device:
    /// "connected" is true when any device is, the name lists them all. The
    /// per-device detail lives in `devices`.
    struct Snapshot {
        var phase = "未启动"
        var bluetoothOn = false
        var connected = false
        var subscribed = false
        var streaming = false
        var deviceName = "—"
        var rssi: Int?
        var mtu = 23
        var packets = 0
        var lost = 0
        var lastPacketHex = ""
        var lastEvent: String = "—"
        var handoffPaused = false
        var firmwareVersion = ""
        var devices: [Device] = []
    }

    /// Everything that used to be a single property on this class, per device.
    private final class Link {
        let peripheral: CBPeripheral
        var name: String
        var connected = false
        var connectDeadline: Date
        var control: CBCharacteristic?
        var audio: CBCharacteristic?
        var event: CBCharacteristic?
        var ota: CBCharacteristic?
        var audioReady = false
        var eventReady = false
        var ready = false
        var rssi: Int?
        var firmware = ""
        var lastSeq: UInt16?

        init(_ peripheral: CBPeripheral, name: String) {
            self.peripheral = peripheral
            self.name = name
            // `central.connect` never times out on its own. A stale connection
            // record leaves it waiting forever, so every attempt gets a deadline.
            connectDeadline = Date().addingTimeInterval(8)
        }
    }

    private var central: CBCentralManager!
    private var links: [UUID: Link] = [:]
    /// Devices handed to another Mac, ignored until the date passes.
    private var releasedUntil: [UUID: Date] = [:]
    /// Everything advertising nearby, connected or not, so the user can pick.
    private var seen: [UUID: (name: String, rssi: Int, busy: Bool, at: Date)] = [:]
    /// Devices seen during this run, so a busy one can be connected on request.
    private var peripherals: [UUID: CBPeripheral] = [:]
    /// Two devices streaming at once would interleave into one garbled input,
    /// so the first one to start talking owns the audio path until it stops.
    private var audioOwner: UUID?
    private let queue = DispatchQueue(label: "folovibe.ble")
    private let audio: AudioOutput
    private let mic: MicTest
    private let lock = NSLock()
    private var snap = Snapshot()
    private var desiredPowerMode: BridgePowerMode = .standard
    private var handoffUntil = Date.distantPast
    private var desiredActions = [UInt8]()
    /// Rendered custom labels by wire slot; nil means "use the built-in name".
    private var desiredLabels = [UInt8: Data?]()
    private var maintenance: DispatchSourceTimer?
    var prefix = "FoloVibe"
    var autoReconnect = true

    var onEvent: ((VibeEvent) -> Void)?
    var onGesture: ((GestureEvent, UUID) -> Void)?
    var onFirmwareVersion: ((String) -> Void)?
    var onOTAProgress: ((Double) -> Void)?
    var onOTAFinished: ((String?) -> Void)?
    var onPCM: (([Int16]) -> Void)?

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return snap
    }

    init(audio: AudioOutput, mic: MicTest) {
        self.audio = audio
        self.mic = mic
        super.init()
        central = CBCentralManager(delegate: self, queue: queue)
    }

    // MARK: - Writes, broadcast to every ready device

    private var readyLinks: [Link] { links.values.filter(\.ready) }

    func writeTypeless(_ state: UInt8) {
        queue.async { [self] in
            for l in readyLinks {
                guard let c = l.control else { continue }
                l.peripheral.writeValue(Data([state]), for: c, type: .withoutResponse)
            }
        }
    }

    func setPowerMode(_ mode: BridgePowerMode) {
        queue.async { [self] in
            desiredPowerMode = mode
            readyLinks.forEach(writePowerMode)
        }
    }

    /// Pushes the gesture-to-action bindings so each device knows which
    /// gestures arm the microphone and what to print under each key hint.
    func writeActions(_ codes: [UInt8]) {
        queue.async { [self] in
            desiredActions = codes
            readyLinks.forEach(writeActions)
        }
    }

    /// Sends only the slots whose bitmap changed: typing a label edits one
    /// slot at a time, and resending all nine on every keystroke is waste.
    func writeLabels(_ labels: [UInt8: Data?]) {
        queue.async { [self] in
            let changed = Set(labels.keys.filter { desiredLabels[$0] != labels[$0] })
            desiredLabels = labels
            guard !changed.isEmpty else { return }
            for l in readyLinks { writeLabels(l, only: changed) }
        }
    }

    private func writeLabels(_ l: Link, only: Set<UInt8>? = nil) {
        guard let c = l.control, !desiredLabels.isEmpty else { return }
        let p = l.peripheral
        let room = max(20, p.maximumWriteValueLength(for: .withoutResponse) - 4)
        var custom = 0
        for (slot, bitmap) in desiredLabels.sorted(by: { $0.key < $1.key })
        where only?.contains(slot) ?? true {
            guard let bitmap else {
                p.writeValue(Data([VibeProtocol.ctrlLabelClear, slot]), for: c, type: .withoutResponse)
                continue
            }
            custom += 1
            var off = 0
            while off < bitmap.count {
                let end = min(off + room, bitmap.count)
                var packet = Data([VibeProtocol.ctrlLabel, slot, UInt8(off & 0xFF), UInt8(off >> 8)])
                packet.append(bitmap.subdata(in: off..<end))
                p.writeValue(packet, for: c, type: .withoutResponse)
                off = end
                // No flow control without response; stay inside the buffer.
                Thread.sleep(forTimeInterval: 0.005)
            }
        }
        Log.ble("同步按键显示名 → \(l.name)（自定义 \(custom) 个）")
    }

    private func writeActions(_ l: Link) {
        guard let c = l.control, !desiredActions.isEmpty else { return }
        l.peripheral.writeValue(
            Data([VibeProtocol.ctrlActions] + desiredActions), for: c, type: .withoutResponse)
        Log.ble("同步按键绑定 → \(l.name)")
    }

    private func writePowerMode(_ l: Link) {
        guard let c = l.control else { return }
        let command: UInt8
        switch desiredPowerMode {
        case .standard: command = VibeProtocol.powerModeStandard
        case .eco: command = VibeProtocol.powerModeEco
        case .ultra: command = VibeProtocol.powerModeUltra
        }
        l.peripheral.writeValue(Data([command]), for: c, type: .withoutResponse)
        Log.ble("同步功耗模式 → \(l.name)：\(desiredPowerMode.title)")
    }

    /// Streams a firmware image to every connected device in turn. Chunks are
    /// paced to the negotiated MTU and written without response; each device
    /// reboots itself once its image verifies, so success looks like a
    /// disconnect.
    func sendFirmware(_ image: Data) {
        queue.async { [self] in
            let targets = readyLinks.filter { $0.ota != nil }
            guard !targets.isEmpty else {
                DispatchQueue.main.async { self.onOTAFinished?("设备未连接或不支持 OTA") }
                return
            }
            let total = Double(image.count * targets.count)
            var done = 0
            for l in targets {
                guard let c = l.ota else { continue }
                Log.ble("推送固件 → \(l.name)")
                let p = l.peripheral
                let chunk = max(20, p.maximumWriteValueLength(for: .withoutResponse))
                p.writeValue(VibeProtocol.otaHeader(length: image.count), for: c, type: .withoutResponse)
                var sent = 0
                while sent < image.count {
                    let end = min(sent + chunk, image.count)
                    p.writeValue(image.subdata(in: sent..<end), for: c, type: .withoutResponse)
                    done += end - sent
                    sent = end
                    let progress = Double(done) / total
                    DispatchQueue.main.async { self.onOTAProgress?(progress) }
                    // Without response there is no flow control, so pace the
                    // writes to stay inside the controller's buffer.
                    Thread.sleep(forTimeInterval: 0.006)
                }
            }
            DispatchQueue.main.async { self.onOTAFinished?(nil) }
        }
    }

    // MARK: - Connection management

    func reconnect() {
        queue.async { [self] in
            handoffUntil = .distantPast
            releasedUntil.removeAll()
            for l in links.values { central.cancelPeripheralConnection(l.peripheral) }
            links.removeAll()
            endAudio()
            publish()
            scan()
        }
    }

    /// Release every device so another Mac running Bridge can take over.
    /// The pause keeps this Mac from immediately winning the scan race again
    /// while the user changes computers.
    func releaseForHandoff(seconds: TimeInterval = 45) {
        queue.async { [self] in
            let pause = max(10, seconds)
            handoffUntil = Date().addingTimeInterval(pause)
            let until = handoffUntil
            central.stopScan()
            for l in links.values { central.cancelPeripheralConnection(l.peripheral) }
            links.removeAll()
            endAudio()
            publish()
            Log.ble("已释放全部设备，\(Int(pause)) 秒内等待另一台 Mac 接管")
            queue.asyncAfter(deadline: .now() + pause) { [weak self] in
                guard let self, self.handoffUntil == until else { return }
                self.handoffUntil = .distantPast
                self.publish()
                if self.autoReconnect { self.scan() }
                Log.ble("切换等待结束，恢复自动连接")
            }
        }
    }

    /// Hands one device to another Mac: the one whose button asked for it.
    /// Every other device stays connected here.
    func release(_ id: UUID, seconds: TimeInterval = 45) {
        queue.async { [self] in
            guard let l = links[id] else { return }
            releasedUntil[id] = Date().addingTimeInterval(seconds)
            central.cancelPeripheralConnection(l.peripheral)
            drop(id)
            Log.ble("已把 \(l.name) 交给另一台 Mac，\(Int(seconds)) 秒内不再连接它")
            queue.asyncAfter(deadline: .now() + seconds) { [weak self] in
                guard let self else { return }
                self.releasedUntil[id] = nil
                // Discovery reports a peripheral once per scan, so restart it
                // or the device would never be seen again.
                if self.autoReconnect { self.scan() }
            }
        }
    }

    /// Use this device now. If another Mac has it, the device drops that Mac
    /// and follows this one — whoever connects last gets it.
    func use(_ id: UUID) {
        queue.async { [self] in
            guard links[id] == nil, let p = peripherals[id] else { return }
            releasedUntil[id] = nil
            Log.ble("选择使用 \(seen[id]?.name ?? p.name ?? "?")")
            adopt(p, name: seen[id]?.name ?? p.name ?? "FoloVibe", force: true)
        }
    }

    func resumeAfterHandoff() {
        queue.async { [self] in
            handoffUntil = .distantPast
            releasedUntil.removeAll()
            publish()
            scan()
        }
    }

    private var isHandoffPaused: Bool { Date() < handoffUntil }

    private func isReleased(_ id: UUID) -> Bool {
        if let until = releasedUntil[id], Date() < until { return true }
        return false
    }

    private func matches(_ name: String?) -> Bool {
        // A connection the system restored on its own may come back nameless.
        guard let name else { return true }
        return name.hasPrefix(prefix)
    }

    private func adopt(_ p: CBPeripheral, name: String, force: Bool = false) {
        guard links[p.identifier] == nil else { return }
        guard force || (!isReleased(p.identifier) && !isHandoffPaused) else { return }
        let l = Link(p, name: name)
        links[p.identifier] = l
        p.delegate = self
        central.connect(p)
        publish()
    }

    private func drop(_ id: UUID) {
        links[id] = nil
        if audioOwner == id { endAudio() }
        publish()
    }

    private func scan() {
        guard !isHandoffPaused else {
            publish()
            return
        }
        guard central.state == .poweredOn else { return }
        let uuid = CBUUID(string: VibeProtocol.serviceUUID)
        // macOS can restore a BLE connection on its own without telling the
        // app. The device then stops advertising, so scanning alone would never
        // find it again. Take those over first.
        for p in central.retrieveConnectedPeripherals(withServices: [uuid]) where matches(p.name) {
            if links[p.identifier] == nil { Log.ble("接管系统已保持的连接 \(p.name ?? "?")") }
            adopt(p, name: p.name ?? "FoloVibe")
        }
        // Keep scanning even with devices connected: another one may turn up.
        central.stopScan()
        central.scanForPeripherals(
            withServices: [uuid], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        Log.ble("扫描 \(prefix)*（已连接 \(readyLinks.count) 台）")
        startMaintenance()
        publish()
    }

    /// One timer does the periodic chores for every link: expire connection
    /// attempts that will never answer, and pick up connections the system
    /// restored behind our back.
    private func startMaintenance() {
        guard maintenance == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 3, repeating: 3)
        timer.setEventHandler { [weak self] in
            guard let self, self.central.state == .poweredOn else { return }
            let now = Date()
            for l in self.links.values where !l.connected && now > l.connectDeadline {
                Log.ble("连接 \(l.name) 超时，重新扫描")
                self.central.cancelPeripheralConnection(l.peripheral)
                self.drop(l.peripheral.identifier)
                self.scan()
            }
            self.publish()
            guard !self.isHandoffPaused else { return }
            let uuid = CBUUID(string: VibeProtocol.serviceUUID)
            for p in self.central.retrieveConnectedPeripherals(withServices: [uuid])
            where self.links[p.identifier] == nil && self.matches(p.name) {
                Log.ble("接管系统已保持的连接 \(p.name ?? "?")")
                self.adopt(p, name: p.name ?? "FoloVibe")
            }
        }
        timer.resume()
        maintenance = timer
    }

    private func endAudio() {
        guard audioOwner != nil else { return }
        audioOwner = nil
        mic.finish()
        update { $0.streaming = false }
    }

    private func update(_ change: (inout Snapshot) -> Void) {
        lock.lock()
        change(&snap)
        lock.unlock()
    }

    /// Rebuilds the aggregate fields from the links.
    private func publish() {
        let all = links.values.sorted { $0.name < $1.name }
        let ready = all.filter(\.ready)
        var devices = all.map {
            Device(id: $0.peripheral.identifier, name: $0.name, rssi: $0.rssi,
                   firmwareVersion: $0.firmware, ready: $0.ready, connected: $0.connected,
                   busyElsewhere: false)
        }
        // Advertising stops once a device is connected anywhere, so a device
        // missing for a while has either gone or been taken by another Mac.
        let fresh = Date().addingTimeInterval(-30)
        for (id, s) in seen where links[id] == nil && s.at > fresh {
            devices.append(Device(id: id, name: s.name, rssi: s.rssi, firmwareVersion: "",
                                  ready: false, connected: false, busyElsewhere: s.busy))
        }
        devices.sort { $0.name == $1.name ? $0.id.uuidString < $1.id.uuidString : $0.name < $1.name }
        let paused = isHandoffPaused
        update {
            $0.devices = devices
            $0.connected = all.contains(where: \.connected)
            $0.subscribed = !ready.isEmpty
            $0.deviceName = ready.isEmpty ? (all.first?.name ?? "—") : ready.map(\.name).joined(separator: "、")
            $0.rssi = ready.first?.rssi
            $0.firmwareVersion = ready.map(\.firmware).filter { !$0.isEmpty }.joined(separator: "、")
            $0.handoffPaused = paused
            if paused {
                $0.phase = "已释放，等待另一台 Mac"
            } else if ready.count > 1 {
                $0.phase = "已就绪（\(ready.count) 台）"
            } else if ready.count == 1 {
                $0.phase = "已就绪"
            } else if !all.isEmpty {
                $0.phase = "连接中"
            } else {
                $0.phase = $0.bluetoothOn ? "扫描中" : "蓝牙关闭"
            }
        }
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let on = central.state == .poweredOn
        update { $0.bluetoothOn = on }
        if on { scan() } else {
            links.removeAll()
            endAudio()
            publish()
            Log.ble("系统蓝牙未开 (\(central.state.rawValue))")
        }
    }

    func centralManager(
        _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any], rssi RSSI: NSNumber
    ) {
        // The advertised name first: macOS caches peripheral.name per device and
        // keeps serving the old one after a firmware update renames it.
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        guard let name, name.hasPrefix(prefix) else { return }
        let id = peripheral.identifier
        if let l = links[id], l.name != name {
            l.name = name
            publish()
        }
        // Firmware that predates handover never advertises while connected, so
        // a missing flag means free.
        let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let busy = mfg.map { $0.count >= 3 && $0[0] == 0xFF && $0[1] == 0xFF && $0[2] == 1 } ?? false
        let changed = seen[id]?.busy != busy
        seen[id] = (name, RSSI.intValue, busy, Date())
        peripherals[id] = peripheral
        if changed {
            publish()
            if busy && links[id] == nil { Log.ble("\(name) 正被另一台主机使用，本机不自动连接（可在设置里点「使用」）") }
        }
        // Only a free device is picked up automatically. Taking one from
        // another Mac is the user's call, or two Macs would pass it back and
        // forth for ever.
        guard links[id] == nil, !busy, !isReleased(id) else { return }
        Log.ble("发现 \(name) RSSI \(RSSI)")
        adopt(peripheral, name: name)
        links[id]?.rssi = RSSI.intValue
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let l = links[peripheral.identifier], !isHandoffPaused, !isReleased(peripheral.identifier)
        else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        l.connected = true
        publish()
        Log.ble("已连接 \(l.name)")
        peripheral.discoverServices([CBUUID(string: VibeProtocol.serviceUUID)])
    }

    func centralManager(
        _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
    ) {
        Log.ble("连接失败 \(peripheral.name ?? "?") \(error?.localizedDescription ?? "")")
        drop(peripheral.identifier)
        if autoReconnect && !isHandoffPaused { scan() }
    }

    func centralManager(
        _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
    ) {
        let name = links[peripheral.identifier]?.name ?? peripheral.name ?? "?"
        drop(peripheral.identifier)
        Log.ble("断开 \(name) \(error?.localizedDescription ?? "正常")")
        if autoReconnect && !isHandoffPaused { scan() }
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            Log.ble("发现服务失败 \(error.localizedDescription)")
            return
        }
        guard let svc = peripheral.services?.first(where: {
            $0.uuid == CBUUID(string: VibeProtocol.serviceUUID)
        }) else {
            Log.ble("没有 Vibe 服务")
            return
        }
        peripheral.discoverCharacteristics(
            [
                CBUUID(string: VibeProtocol.audioUUID),
                CBUUID(string: VibeProtocol.eventUUID),
                CBUUID(string: VibeProtocol.controlUUID),
                CBUUID(string: VibeProtocol.versionUUID),
                CBUUID(string: VibeProtocol.otaUUID),
            ], for: svc)
    }

    func peripheral(
        _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
    ) {
        guard let l = links[peripheral.identifier] else { return }
        l.audioReady = false
        l.eventReady = false
        for ch in service.characteristics ?? [] {
            if ch.uuid == CBUUID(string: VibeProtocol.audioUUID) {
                l.audio = ch
            } else if ch.uuid == CBUUID(string: VibeProtocol.eventUUID) {
                l.event = ch
            } else if ch.uuid == CBUUID(string: VibeProtocol.controlUUID) {
                l.control = ch
            } else if ch.uuid == CBUUID(string: VibeProtocol.versionUUID) {
                peripheral.readValue(for: ch)
            } else if ch.uuid == CBUUID(string: VibeProtocol.otaUUID) {
                l.ota = ch
            }
        }
        // Claim the device before anything else. If another Mac has it, the
        // device only switches once asked, and it must switch before the
        // notifications below are enabled or they would land on the old link.
        if let c = l.control {
            peripheral.writeValue(Data([VibeProtocol.ctrlClaim]), for: c, type: .withResponse)
        }
        let mtu = peripheral.maximumWriteValueLength(for: .withoutResponse) + 3
        update { $0.mtu = mtu }
        Log.ble("\(l.name)：发现音频/事件特征，按顺序开启通知，约 MTU \(mtu)")
        enableNextNotify(l)
    }

    /// CoreBluetooth serializes CCCD writes less reliably when two notify
    /// requests are issued back-to-back. Wait for the first state callback
    /// before enabling the second one; otherwise the firmware may receive
    /// audio notifications but never receive button-event notifications.
    private func enableNextNotify(_ l: Link) {
        let p = l.peripheral
        if !l.audioReady, let ch = l.audio {
            p.setNotifyValue(true, for: ch)
        } else if !l.eventReady, let ch = l.event {
            p.setNotifyValue(true, for: ch)
        } else if l.audioReady && l.eventReady {
            l.ready = true
            publish()
            Log.ble("\(l.name) 已就绪（共 \(readyLinks.count) 台）")
            writePowerMode(l)
            writeActions(l)
            writeLabels(l)
            p.readRSSI()
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let l = links[peripheral.identifier] else { return }
        if let error {
            Log.ble("\(l.name) 通知开启失败 \(characteristic.uuid): \(error.localizedDescription)")
            return
        }
        guard characteristic.isNotifying else {
            Log.ble("\(l.name) 通知未开启 \(characteristic.uuid)")
            return
        }
        if characteristic.uuid == CBUUID(string: VibeProtocol.audioUUID) {
            l.audioReady = true
        } else if characteristic.uuid == CBUUID(string: VibeProtocol.eventUUID) {
            l.eventReady = true
        }
        enableNextNotify(l)
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        links[peripheral.identifier]?.rssi = RSSI.intValue
        publish()
    }

    func peripheral(
        _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?
    ) {
        guard let data = characteristic.value, error == nil,
              let l = links[peripheral.identifier] else { return }
        if characteristic.uuid == CBUUID(string: VibeProtocol.versionUUID) {
            l.firmware = String(decoding: data, as: UTF8.self)
            publish()
            Log.ble("\(l.name) 设备固件 \(l.firmware)")
            let summary = snapshot.firmwareVersion
            DispatchQueue.main.async { self.onFirmwareVersion?(summary) }
            return
        }
        if characteristic.uuid == CBUUID(string: VibeProtocol.eventUUID),
            let byte = data.first, let gesture = GestureEvent.parse(byte)
        {
            update { $0.lastEvent = gesture.title }
            Log.ble("\(l.name) 手势 \(gesture.title)")
            let id = peripheral.identifier
            DispatchQueue.main.async { self.onGesture?(gesture, id) }
            return
        }
        // Older firmware still speaks the semantic events.
        if characteristic.uuid == CBUUID(string: VibeProtocol.eventUUID),
            let byte = data.first, let ev = VibeEvent(rawValue: byte)
        {
            if ev == .stop || ev == .doubaoStop || ev == .doubaoStopAndSend { endAudio() }
            update { $0.lastEvent = ev.title }
            Log.ble("事件 \(ev.title)")
            DispatchQueue.main.async { self.onEvent?(ev) }
            return
        }
        if characteristic.uuid == CBUUID(string: VibeProtocol.audioUUID) {
            handleAudio(data, from: l)
        }
    }

    private func handleAudio(_ data: Data, from l: Link) {
        let id = l.peripheral.identifier
        if let owner = audioOwner, owner != id { return }
        guard let pkt = AudioPacket.parse(data) else {
            update { $0.lost += 1 }
            return
        }
        let hex = data.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
        if pkt.eos {
            update { $0.lastPacketHex = hex + " EOS" }
            l.lastSeq = nil
            if audioOwner == id { endAudio() }
            return
        }
        if audioOwner == nil {
            audioOwner = id
            if links.count > 1 { Log.ble("\(l.name) 开始说话，其它设备的声音暂不采用") }
        }
        if let last = l.lastSeq {
            let gap = UInt16(truncatingIfNeeded: pkt.seq &- last &- 1)
            if gap > 0 && gap < 80 {
                update { $0.lost += Int(gap) }
                for _ in 0..<gap { audio.push([Int16](repeating: 0, count: 320)) }
            }
        }
        l.lastSeq = pkt.seq
        let pcm = IMAADPCM.decode(pkt.adpcm, predictor: pkt.predictor, stepIndex: pkt.stepIndex)
        audio.push(pcm)
        mic.append(pcm)
        onPCM?(pcm)
        update {
            $0.streaming = true
            $0.packets += 1
            $0.lastPacketHex = hex
        }
    }
}
