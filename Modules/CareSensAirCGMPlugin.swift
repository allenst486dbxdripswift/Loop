import Foundation
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
        let sample = GlucoseSample(
            uuid: UUID(),
            quantity: Double(glucose),
            startDate: Date(),
            endDate: Date(),
            isDisplayOnly: false,
            syncIdentifier: "\(Int(Date().timeIntervalSince1970))",
            device: "CareSens Air"
        )
        delegate?.cgmManager(self, didUpdate: [sample])
    }

    var deviceIdentifier: String? { return "CSAIR-001" }
    var managerIdentifier: String { return "CareSensAirCGMPlugin" }
    var shouldSyncToRemoteService: Bool { return true }
}
