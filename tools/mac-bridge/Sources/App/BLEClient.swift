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

    func reconnect() {
        queue.async { [self] in
            if let p = peripheral { central.cancelPeripheralConnection(p) }
            peripheral = nil
            control = nil
            lastSeq = nil
            update { $0.connected = false; $0.subscribed = false; $0.streaming = false }
            scan()
        }
    }

    private func update(_ change: (inout Snapshot) -> Void) {
        lock.lock()
        change(&snap)
        lock.unlock()
    }

    private func scan() {
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
        update { $0.connected = true; $0.phase = "发现服务"; $0.deviceName = peripheral.name ?? $0.deviceName }
        Log.ble("已连接 \(peripheral.name ?? "?")")
        peripheral.discoverServices([CBUUID(string: VibeProtocol.serviceUUID)])
    }

    func centralManager(
        _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
    ) {
        update { $0.connected = false; $0.phase = "连接失败" }
        Log.ble("连接失败 \(error?.localizedDescription ?? "")")
        if autoReconnect { scan() }
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
        if autoReconnect { scan() }
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
            if ev == .start { update { $0.streaming = true } }
            if ev == .stop || ev == .cancel {
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
