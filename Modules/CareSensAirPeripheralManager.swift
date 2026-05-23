import Foundation
import CoreBluetooth

/// CoreBluetooth manager for CareSens Air CGM.
final class CareSensAirPeripheralManager: NSObject {
    private let serviceUUID = CBUUID(string: "0000FFE0-0000-1000-8000-00805F9B34FB")
    private let writeCharUUID = CBUUID(string: "0000FFE1-0000-1000-8000-00805F9B34FB")
    private let notifyCharUUID = CBUUID(string: "0000FFE2-0000-1000-8000-00805F9B34FB")

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }

    private func authenticate() {
        let pin = "123456"
        let deviceID = "CSAIR-001"
        let payload = "\(pin):\(deviceID)".data(using: .utf8)!
        guard let writeChar = writeChar else { return }
        peripheral?.writeValue(payload, for: writeChar, type: .withResponse)
    }

    private func handleIncoming(_ data: Data) {
        guard let plain = CareSensAirCrypto.decrypt(data) else { return }
        if let glucose = PacketParser.parse(plain) {
            NotificationCenter.default.post(name: .csAirGlucoseUpdate,
                                            object: nil,
                                            userInfo: ["glucose": glucose])
        }
    }
}

extension CareSensAirPeripheralManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { startScanning() }
    }
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        self.peripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        central.connect(peripheral, options: nil)
    }
    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([serviceUUID])
    }
}

extension CareSensAirPeripheralManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svc = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else { return }
        peripheral.discoverCharacteristics([writeCharUUID, notifyCharUUID], for: svc)
    }
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        for char in service.characteristics ?? [] {
            if char.uuid == writeCharUUID { writeChar = char }
            if char.uuid == notifyCharUUID {
                notifyChar = char
                peripheral.setNotifyValue(true, for: char)
            }
        }
        authenticate()
    }
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid == notifyCharUUID,
              let data = characteristic.value else { return }
        handleIncoming(data)
    }
}

extension Notification.Name {
    static let csAirGlucoseUpdate = Notification.Name("csAirGlucoseUpdate")
}
