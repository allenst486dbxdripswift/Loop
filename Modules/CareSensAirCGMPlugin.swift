import Foundation
import HealthKit
import LoopKit
import LoopKitUI
import UIKit

/// Loop용 CGM 플러그인. iOS Loop 코드베이스에 CareSens Air를 `CGMManagerUI` 로 등록합니다.
public final class CareSensAirCGMPlugin: NSObject, CGMManagerUI {
    public var delegate: CGMManagerDelegate?
    
    public var cgmManagerDelegate: CGMManagerDelegate? {
        get { return delegate }
        set { delegate = newValue }
    }
    
    public var delegateQueue: DispatchQueue! = .main

    private let peripheral = CareSensAirPeripheralManager()

    // MARK: - DeviceManager
    public static let pluginIdentifier: String = "CareSensAirCGMPlugin"
    public static let localizedTitle = "CareSens Air"
    
    public var pluginIdentifier: String { return Self.pluginIdentifier }
    public var managerIdentifier: String { return Self.pluginIdentifier }
    public var localizedTitle: String { return Self.localizedTitle }
    public let isOnboarded = true
    public var appURL: URL? { return nil }
    public var device: HKDevice? { return nil }

    // MARK: - CGMManager
    public var cgmManagerStatus: CGMManagerStatus {
        return CGMManagerStatus(hasValidSensorSession: true, device: device)
    }
    public var shouldSyncToRemoteService: Bool = true
    public var providesBLEHeartbeat: Bool = false
    public var managedDataInterval: TimeInterval? = nil

    // MARK: - Missing requirements for CGMManager and DeviceManager
    public var glucoseDisplay: GlucoseDisplayable? { return nil }
    public var debugDescription: String { return "CareSensAirCGMPlugin" }

    public var rawState: CGMManager.RawStateValue {
        return [:]
    }

    public required init?(rawState: CGMManager.RawStateValue) {
        super.init()
    }

    public override init() {
        super.init()
    }

    public func fetchNewDataIfNeeded(_ completion: @escaping (CGMReadingResult) -> Void) {
        completion(.noData)
    }

    public func start() {
        peripheral.startScanning()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleGlucoseUpdate(_:)),
                                               name: .csAirGlucoseUpdate,
                                               object: nil)
    }

    public func stop() {
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

    // MARK: - AlertResponder
    public func acknowledgeAlert(alertIdentifier: Alert.AlertIdentifier, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }

    // MARK: - AlertSoundVendor
    public func getSoundBaseURL() -> URL? { return nil }
    public func getSounds() -> [Alert.Sound] { return [] }

    // MARK: - CGMManagerUI
    public var cgmStatusHighlight: DeviceStatusHighlight? { return nil }
    public var cgmLifecycleProgress: DeviceLifecycleProgress? { return nil }
    public var cgmStatusBadge: DeviceStatusBadge? { return nil }
    
    public static var onboardingImage: UIImage? { return nil }
    public var smallImage: UIImage? { return nil }

    public static func setupViewController(bluetoothProvider: BluetoothProvider, displayGlucosePreference: DisplayGlucosePreference, colorPalette: LoopUIColorPalette, allowDebugFeatures: Bool, prefersToSkipUserInteraction: Bool) -> SetupUIResult<CGMManagerViewController, CGMManagerUI> {
        let manager = CareSensAirCGMPlugin()
        return .createdAndOnboarded(manager)
    }

    public func settingsViewController(bluetoothProvider: BluetoothProvider, displayGlucosePreference: DisplayGlucosePreference, colorPalette: LoopUIColorPalette, allowDebugFeatures: Bool) -> CGMManagerViewController {
        return CareSensDummySettingsVC()
    }
}

// MARK: - UIViewController for Settings
public class CareSensDummySettingsVC: UIViewController, CGMManagerOnboarding, CompletionNotifying {
    public weak var cgmManagerOnboardingDelegate: CGMManagerOnboardingDelegate?
    public weak var completionDelegate: CompletionDelegate?

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        
        let label = UILabel()
        label.text = "CareSens Air Settings\n(No configurable settings)"
        label.numberOfLines = 0
        label.textAlignment = .center
        label.frame = view.bounds
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(label)
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(done))
    }
    
    @objc func done() {
        completionDelegate?.completionNotifyingDidComplete(self)
    }
}

// MARK: - CGMManagerUIPlugin
public class CareSensAirCGMUIPlugin: NSObject, CGMManagerUIPlugin {
    public var cgmManagerType: CGMManagerUI.Type? {
        return CareSensAirCGMPlugin.self
    }
}
