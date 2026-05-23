import Foundation
import HealthKit
import LoopKit
import LoopKitUI

/// Loop용 CGM 플러그인. iOS Loop 코드베이스에 CareSens Air를 `CGMManager` 로 등록합니다.
final class CareSensAirCGMPlugin: NSObject, CGMManager {
    var delegate: CGMManagerDelegate?
    var pumpManager: PumpManagerUI?

    private let peripheral = CareSensAirPeripheralManager()

    func start() {
        peripheral.startScanning()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleGlucoseUpdate(_:)),
                                               name: .csAirGlucoseUpdate,
                                               object: nil)
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleGlucoseUpdate(_ note: Notification) {
        guard let glucose = note.userInfo?["glucose"] as? Double else { return }
        let sample = NewGlucoseSample(
            date: Date(),
            quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: glucose),
            condition: nil,
            trend: nil,
            trendRate: nil,
            isDisplayOnly: false,
            wasUserEntered: false,
            syncIdentifier: "\(Int(Date().timeIntervalSince1970))"
        )
        delegate?.cgmManager(self, hasNew: .newData([sample]))
    }

    var deviceIdentifier: String? { return "CSAIR-001" }
    var managerIdentifier: String { return "CareSensAirCGMPlugin" }
    var shouldSyncToRemoteService: Bool { return true }
    
    // MARK: - CGMManager Protocol Requirements
    var providesBLEHeartbeat: Bool { return false }
    var managedDataInterval: TimeInterval? { return nil }

    var rawState: CGMManager.RawStateValue {
        return [:]
    }

    required init?(rawState: CGMManager.RawStateValue) {
        super.init()
    }

    override init() {
        super.init()
    }
}

// MARK: - CGMManagerUIPlugin conformance (minimal UI to appear in selection list)
extension CareSensAirCGMPlugin: CGMManagerUIPlugin {
    static var pluginIdentifier: String { return "CareSensAirCGMPlugin" }
    static var localizedTitle: String { return "CareSens Air" }
    static var deviceType: DeviceType { return .cgm }
    static var onboardingMethods: [OnboardingMethod] { return [] }

    static func setupViewController(bluetoothProvider: BluetoothProvider?, displayGlucosePreference: DisplayGlucosePreference, colorPalette: LoopUIColorPalette, allowDebugFeatures: Bool, prefersToSkipUserInteraction: Bool) -> SetupUIResult {
        // No UI needed – just create the manager instance directly.
        let manager = CareSensAirCGMPlugin()
        return .createdAndOnboarded(manager)
    }
}
