import CoreBluetooth
import FoloVibeCore
import Foundation

final class BLEClient: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
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
    }

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var control: CBCharacteristic?
    private var lastSeq: UInt16?
    private let queue = DispatchQueue(label: "folovibe.ble")
    private let audio: AudioOutput
    private let mic: MicTest
    private let lock = NSLock()
    private var snap = Snapshot()
    private var desiredPowerMode: BridgePowerMode = .standard
    private var handoffUntil = Date.distantPast
    var prefix = "FoloVibe"
    var autoReconnect = true

    var onEvent: ((VibeEvent) -> Void)?
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

    func writeTypeless(_ state: UInt8) {
        queue.async { [self] in
            guard let p = peripheral, let c = control else { return }
            p.writeValue(Data([state]), for: c, type: .withoutResponse)
        }
    }

    func setPowerMode(_ mode: BridgePowerMode) {
        queue.async { [self] in
            self.desiredPowerMode = mode
            self.writePowerMode()
        }
    }

    private func writePowerMode() {
        guard let p = peripheral, let c = control else { return }
        let command: UInt8 = desiredPowerMode == .eco
            ? VibeProtocol.powerModeEco : VibeProtocol.powerModeStandard
        p.writeValue(Data([command]), for: c, type: .withoutResponse)
        Log.ble("同步功耗模式：\(desiredPowerMode.title)")
    }

    func reconnect() {
        queue.async { [self] in
            handoffUntil = .distantPast
            if let p = peripheral { central.cancelPeripheralConnection(p) }
            peripheral = nil
            control = nil
            lastSeq = nil
            update {
                $0.connected = false
                $0.subscribed = false
                $0.streaming = false
                $0.handoffPaused = false
            }
            scan()
        }
    }

    /// Release the device so another Mac running Bridge can take over.
    /// The short pause prevents this Mac from immediately winning the scan
    /// race again while the user changes computers.
    func releaseForHandoff(seconds: TimeInterval = 45) {
        queue.async { [self] in
            let pause = max(10, seconds)
            handoffUntil = Date().addingTimeInterval(pause)
            let releaseUntil = handoffUntil
            central.stopScan()
            if let p = peripheral { central.cancelPeripheralConnection(p) }
            peripheral = nil
            control = nil
            lastSeq = nil
            update {
                $0.connected = false
                $0.subscribed = false
                $0.streaming = false
                $0.handoffPaused = true
                $0.phase = "已释放，等待另一台 Mac"
            }
            Log.ble("已释放设备，\(Int(pause)) 秒内等待另一台 Mac 接管")
            queue.asyncAfter(deadline: .now() + pause) { [weak self] in
                guard let self, self.handoffUntil == releaseUntil else { return }
                self.handoffUntil = .distantPast
                self.update { $0.handoffPaused = false; $0.phase = "准备自动连接" }
                if self.autoReconnect { self.scan() }
                Log.ble("切换等待结束，恢复自动连接")
            }
        }
    }

    func resumeAfterHandoff() {
        queue.async { [self] in
            handoffUntil = .distantPast
            update { $0.handoffPaused = false; $0.phase = "准备连接" }
            scan()
        }
    }

    private var isHandoffPaused: Bool { Date() < handoffUntil }

    private func update(_ change: (inout Snapshot) -> Void) {
        lock.lock()
        change(&snap)
        lock.unlock()
    }

    private func scan() {
        guard !isHandoffPaused else {
            update { $0.handoffPaused = true; $0.phase = "已释放，等待另一台 Mac" }
            return
        }
        guard central.state == .poweredOn else { return }
        let uuid = CBUUID(string: VibeProtocol.serviceUUID)
        if let p = central.retrieveConnectedPeripherals(withServices: [uuid]).first {
            peripheral = p
            p.delegate = self
            update { $0.phase = "连接中"; $0.deviceName = p.name ?? $0.deviceName }
            central.connect(p)
            return
        }
        update { $0.phase = "扫描中" }
        Log.ble("扫描 \(prefix)*")
        central.scanForPeripherals(withServices: [uuid])
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let on = central.state == .poweredOn
        update { $0.bluetoothOn = on; $0.phase = on ? "扫描中" : "蓝牙关闭" }
        if on { scan() }
        else { Log.ble("系统蓝牙未开 (\(central.state.rawValue))") }
    }

    func centralManager(
        _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any], rssi RSSI: NSNumber
    ) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard let name, name.hasPrefix(prefix) else { return }
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        update {
            $0.phase = "连接中"
            $0.deviceName = name
            $0.rssi = RSSI.intValue
        }
        Log.ble("发现 \(name) RSSI \(RSSI)")
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if isHandoffPaused {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        update { $0.connected = true; $0.phase = "发现服务"; $0.deviceName = peripheral.name ?? $0.deviceName }
        Log.ble("已连接 \(peripheral.name ?? "?")")
        peripheral.discoverServices([CBUUID(string: VibeProtocol.serviceUUID)])
    }

    func centralManager(
        _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
    ) {
        update { $0.connected = false; $0.phase = "连接失败" }
        Log.ble("连接失败 \(error?.localizedDescription ?? "")")
        if autoReconnect && !isHandoffPaused { scan() }
    }

    func centralManager(
        _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
    ) {
        update {
            $0.connected = false
            $0.subscribed = false
            $0.streaming = false
            $0.phase = "已断开"
        }
        control = nil
        lastSeq = nil
        Log.ble("断开 \(error?.localizedDescription ?? "正常")")
        if autoReconnect && !isHandoffPaused { scan() }
    }

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
            ], for: svc)
    }

    func peripheral(
        _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
    ) {
        for ch in service.characteristics ?? [] {
            if ch.uuid == CBUUID(string: VibeProtocol.audioUUID)
                || ch.uuid == CBUUID(string: VibeProtocol.eventUUID)
            {
                peripheral.setNotifyValue(true, for: ch)
            } else if ch.uuid == CBUUID(string: VibeProtocol.controlUUID) {
                control = ch
            }
        }
        let mtu = peripheral.maximumWriteValueLength(for: .withoutResponse) + 3
        update { $0.subscribed = true; $0.phase = "已订阅"; $0.mtu = mtu }
        Log.ble("已订阅音频/事件，约 MTU \(mtu)")
        writePowerMode()
        peripheral.readRSSI()
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        update { $0.rssi = RSSI.intValue }
    }

    func peripheral(
        _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?
    ) {
        guard let data = characteristic.value, error == nil else { return }
        if characteristic.uuid == CBUUID(string: VibeProtocol.eventUUID),
            let byte = data.first, let ev = VibeEvent(rawValue: byte)
        {
            if ev == .start || ev == .typelessTranslate || ev == .typelessAsk || ev == .doubaoStart {
                update { $0.streaming = true }
            }
            if ev == .stop || ev == .cancel || ev == .doubaoStop || ev == .doubaoStopAndSend {
                update { $0.streaming = false }
                mic.finish()
            }
            update { $0.lastEvent = ev.title }
            Log.ble("事件 \(ev.title)")
            DispatchQueue.main.async { self.onEvent?(ev) }
            return
        }
        if characteristic.uuid == CBUUID(string: VibeProtocol.audioUUID) {
            handleAudio(data)
        }
    }

    private func handleAudio(_ data: Data) {
        guard let pkt = AudioPacket.parse(data) else {
            update { $0.lost += 1 }
            return
        }
        let hex = data.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
        if pkt.eos {
            update { $0.streaming = false; $0.lastPacketHex = hex + " EOS" }
            lastSeq = nil
            mic.finish()
            return
        }
        if let last = lastSeq {
            let gap = UInt16(truncatingIfNeeded: pkt.seq &- last &- 1)
            if gap > 0 && gap < 80 {
                update { $0.lost += Int(gap) }
                for _ in 0..<gap { audio.push([Int16](repeating: 0, count: 320)) }
            }
        }
        lastSeq = pkt.seq
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
