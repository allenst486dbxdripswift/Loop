import Foundation
import CoreBluetooth
import os.log

/// CoreBluetooth manager for CareSens Air CGM.
final class CareSensAirPeripheralManager: NSObject {
    private let log = OSLog(subsystem: "com.loopkit.Loop", category: "CareSensAirPeripheralManager")

    // Service UUIDs from device_info.txt
    private let cgmServiceUUID       = CBUUID(string: "C4DE9A20-5A9D-11E9-8647-D663BD873D93")
    private let commandServiceUUID   = CBUUID(string: "C4DE9DC2-5A9D-11E9-8647-D663BD873D93")
    private let commandWriteUUID     = CBUUID(string: "C4DE9EE4-5A9D-11E9-8647-D663BD873D93")
    private let authAppIDCheckUUID   = CBUUID(string: "C4DEC61C-5A9D-11E9-8647-D663BD873D93")
    private let dataStreamNotifyUUID = CBUUID(string: "C4DE9B74-5A9D-11E9-8647-D663BD873D93")

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandWriteChar: CBCharacteristic?
    private var authAppIDCheckChar: CBCharacteristic?
    private var dataStreamNotifyChar: CBCharacteristic?

    // Serial number: fixed prefix "C1QBT5A0" + last 4 digits from BLE device name
    // e.g. BLE name "CSAir 1157" -> serialNumber = "C1QBT5A01157"
    private let serialNumberPrefix = "C1QBT5A0"
    private var serialNumber = "C1QBT5A01157" // fallback default

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        guard central.state == .poweredOn else { return }
        os_log("Scanning for CareSens Air...", log: self.log, type: .default)
        central.scanForPeripherals(withServices: [cgmServiceUUID, commandServiceUUID], options: nil)
    }

    /// Extracts the last 4-digit suffix from BLE device name.
    /// Expected formats: "CSAir 1157", "CareSens Air-1157", "CSAIR_1157", etc.
    private func extractSuffix4(from peripheralName: String) -> String? {
        // Find the last sequence of exactly 4 digits in the name
        let digits = peripheralName.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
        let digitString = String(digits)
        guard digitString.count >= 4 else { return nil }
        return String(digitString.suffix(4))
    }

    private func performHandshake() {
        guard let commandWriteChar = commandWriteChar, let authAppIDCheckChar = authAppIDCheckChar else {
            os_log("Characteristics missing for handshake.", log: self.log, type: .error)
            return
        }

        os_log("Starting AES Handshake with serialNumber: %{public}@", log: self.log, type: .default, serialNumber)

        // 1. AES Handshake (0xC0 0x01 + 16 bytes encrypted serial)
        var serialData = serialNumber.data(using: .utf8)!
        while serialData.count < 16 { serialData.append(0) } // Pad to 16 bytes

        if let encryptedSerial = CareSensAirCrypto.encrypt(serialData, serialNumber: serialNumber) {
            var payload1 = Data([0xC0, 0x01])
            payload1.append(encryptedSerial)
            peripheral?.writeValue(payload1, for: commandWriteChar, type: .withResponse)
            os_log("AES Handshake payload sent.", log: self.log, type: .default)
        } else {
            os_log("Failed to encrypt serial number.", log: self.log, type: .error)
        }

        // 2. App ID Check (0xC0 0x03 + "csair" padded to 32 bytes + 0x00)
        os_log("Sending App ID Check...", log: self.log, type: .default)
        var payload2 = Data([0xC0, 0x03])
        var appIdData = "csair".data(using: .utf8)!
        let padLength = 32 - appIdData.count
        for _ in 0..<padLength { appIdData.append(UInt8(padLength)) } // PKCS7 padding to 32 bytes
        appIdData.append(0x00)
        payload2.append(appIdData)
        peripheral?.writeValue(payload2, for: authAppIDCheckChar, type: .withResponse)

        // 3. Time Sync (0xC3 0x02 + 4 bytes Unix timestamp little-endian)
        os_log("Sending Time Sync...", log: self.log, type: .default)
        var payload3 = Data([0xC3, 0x02])
        var timestamp = UInt32(Date().timeIntervalSince1970)
        payload3.append(withUnsafeBytes(of: &timestamp) { Data($0) })
        peripheral?.writeValue(payload3, for: commandWriteChar, type: .withResponse)
    }

    private func handleIncoming(_ data: Data) {
        os_log("Incoming data: %{public}@", log: self.log, type: .default, data.map { String(format: "%02x", $0) }.joined())

        guard let plain = CareSensAirCrypto.decrypt(data, serialNumber: serialNumber) else {
            os_log("Failed to decrypt incoming data.", log: self.log, type: .error)
            return
        }

        if let glucose = PacketParser.parse(plain) {
            os_log("Parsed glucose: %{public}f", log: self.log, type: .default, glucose)
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
        let name = peripheral.name ?? ""
        os_log("Discovered CareSens Air: %{public}@", log: self.log, type: .default, name)

        // Derive serial number from BLE device name suffix (last 4 digits)
        // e.g. "CSAir 1157" -> suffix4 = "1157" -> serialNumber = "C1QBT5A01157"
        if let suffix4 = extractSuffix4(from: name) {
            serialNumber = serialNumberPrefix + suffix4
            os_log("Derived serialNumber: %{public}@ from BLE name: %{public}@",
                   log: self.log, type: .default, serialNumber, name)
        } else {
            os_log("Could not extract 4-digit suffix from BLE name '%{public}@', using fallback: %{public}@",
                   log: self.log, type: .fault, name, serialNumber)
        }

        self.peripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {
        os_log("Connected to CareSens Air.", log: self.log, type: .default)
        peripheral.discoverServices([cgmServiceUUID, commandServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        os_log("Failed to connect: %{public}@", log: self.log, type: .error, error?.localizedDescription ?? "Unknown")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        os_log("Disconnected: %{public}@", log: self.log, type: .error, error?.localizedDescription ?? "Unknown")
        startScanning()
    }
}

extension CareSensAirPeripheralManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            os_log("Discover services error: %{public}@", log: self.log, type: .error, error.localizedDescription)
            return
        }
        for service in peripheral.services ?? [] {
            if service.uuid == commandServiceUUID {
                peripheral.discoverCharacteristics([commandWriteUUID, authAppIDCheckUUID, dataStreamNotifyUUID], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error = error {
            os_log("Discover characteristics error: %{public}@", log: self.log, type: .error, error.localizedDescription)
            return
        }
        for char in service.characteristics ?? [] {
            if char.uuid == commandWriteUUID { commandWriteChar = char }
            if char.uuid == authAppIDCheckUUID { authAppIDCheckChar = char }
            if char.uuid == dataStreamNotifyUUID {
                dataStreamNotifyChar = char
                peripheral.setNotifyValue(true, for: char)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            os_log("Update notification state error: %{public}@", log: self.log, type: .error, error.localizedDescription)
            return
        }
        if characteristic.uuid == dataStreamNotifyUUID && characteristic.isNotifying {
            os_log("Data stream notify enabled. Starting handshake.", log: self.log, type: .default)
            performHandshake()
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            os_log("Update value error: %{public}@", log: self.log, type: .error, error.localizedDescription)
            return
        }
        guard characteristic.uuid == dataStreamNotifyUUID,
              let data = characteristic.value else { return }
        handleIncoming(data)
    }
}

extension Notification.Name {
    static let csAirGlucoseUpdate = Notification.Name("csAirGlucoseUpdate")
}
