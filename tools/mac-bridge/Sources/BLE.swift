import CoreBluetooth
import Foundation

final class BLEClient: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let serviceUUID = CBUUID(string: "F0100001-0000-4A6B-9E10-464F4C4F5631")
    static let audioUUID = CBUUID(string: "F0100002-0000-4A6B-9E10-464F4C4F5631")
    static let eventUUID = CBUUID(string: "F0100003-0000-4A6B-9E10-464F4C4F5631")
    static let controlUUID = CBUUID(string: "F0100004-0000-4A6B-9E10-464F4C4F5631")

    enum Event: UInt8 { case start = 1, stop = 2, enter = 3, cancel = 4 }

    private let audio: AudioOutput
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var control: CBCharacteristic?
    private var lastSeq: UInt16?
    private let queue = DispatchQueue(label: "folovibe.ble")
    var onEvent: ((Event) -> Void)?
    var onStatus: ((String) -> Void)?
    private(set) var streaming = false
    private(set) var connected = false

    init(audio: AudioOutput) {
        self.audio = audio
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
            connected = false
            streaming = false
            scan()
        }
    }

    private func scan() {
        guard central.state == .poweredOn else { return }
        if let p = central.retrieveConnectedPeripherals(withServices: [Self.serviceUUID]).first {
            peripheral = p
            p.delegate = self
            onStatus?("connecting")
            central.connect(p)
            return
        }
        onStatus?("scanning")
        central.scanForPeripherals(withServices: [Self.serviceUUID])
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { scan() }
        else { onStatus?("bluetooth \(central.state.rawValue)") }
    }

    func centralManager(
        _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any], rssi RSSI: NSNumber
    ) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard let name, name.hasPrefix("FoloVibe") else { return }
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        onStatus?("connecting \(name)")
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connected = true
        onStatus?("connected")
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
    ) {
        connected = false
        onStatus?("connect failed")
        scan()
    }

    func centralManager(
        _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
    ) {
        connected = false
        streaming = false
        control = nil
        onStatus?("disconnected")
        scan()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svc = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            return
        }
        peripheral.discoverCharacteristics(
            [Self.audioUUID, Self.eventUUID, Self.controlUUID], for: svc)
    }

    func peripheral(
        _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
    ) {
        for ch in service.characteristics ?? [] {
            if ch.uuid == Self.audioUUID || ch.uuid == Self.eventUUID {
                peripheral.setNotifyValue(true, for: ch)
            } else if ch.uuid == Self.controlUUID {
                control = ch
            }
        }
        onStatus?("subscribed")
    }

    func peripheral(
        _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let data = characteristic.value, error == nil else { return }
        if characteristic.uuid == Self.eventUUID, let byte = data.first,
            let ev = Event(rawValue: byte)
        {
            if ev == .start { streaming = true }
            if ev == .stop || ev == .cancel { streaming = false }
            DispatchQueue.main.async { self.onEvent?(ev) }
            return
        }
        if characteristic.uuid == Self.audioUUID {
            handleAudio(data)
        }
    }

    private func handleAudio(_ data: Data) {
        guard data.count >= 6 else { return }
        let seq = UInt16(data[0]) | (UInt16(data[1]) << 8)
        let flags = data[5]
        if data.count == 6 || (flags & 0x01) != 0 {
            streaming = false
            lastSeq = nil
            return
        }
        guard data.count == 166 else { return }
        if let last = lastSeq {
            let gap = UInt16(truncatingIfNeeded: seq &- last &- 1)
            if gap > 0 && gap < 50 {
                for _ in 0..<gap { audio.push([Int16](repeating: 0, count: 320)) }
            }
        }
        lastSeq = seq
        streaming = true
        let predictor = Int16(bitPattern: UInt16(data[2]) | (UInt16(data[3]) << 8))
        let index = data[4]
        let pcm = IMAADPCM.decode(data.subdata(in: 6..<data.count), predictor: predictor, stepIndex: index)
        audio.push(pcm)
    }
}
