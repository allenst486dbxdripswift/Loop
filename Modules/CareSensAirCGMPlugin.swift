//
//  CareSensAirCGMPlugin.swift
//  Loop
//
//  Registers the CareSens Air (i-SENS) CGM as a CGMManagerUI in the Loop app target.
//  Persists the per-device serial + PIN, drives the BLE manager, and feeds glucose
//  (with trend) into Loop. See caresens_protocol_spec.md.
//

import Foundation
import HealthKit
import LoopKit
import LoopKitUI
import UIKit

public final class CareSensAirCGMPlugin: NSObject, CGMManagerUI {

    // MARK: - Persisted configuration

    /// 12-char sensor serial (e.g. "C1QBT5A01157").
    public private(set) var serial: String
    /// Box PIN code (used for BLE bonding; iOS presents the pairing dialog).
    public private(set) var pin: String
    private var isFirstConnection: Bool

    private var peripheralManager: CareSensAirPeripheralManager?

    // Trend tracking
    private var lastGlucoseValue: Int?
    private var lastGlucoseDate: Date?
    private var latestTrendRate: Double?   // mg/dL/min

    // MARK: - Delegate

    public var cgmManagerDelegate: CGMManagerDelegate? {
        get { delegate.delegate }
        set { delegate.delegate = newValue }
    }
    public var delegateQueue: DispatchQueue! {
        get { delegate.queue }
        set { delegate.queue = newValue }
    }
    private let delegate = WeakSynchronizedDelegate<CGMManagerDelegate>()

    // MARK: - DeviceManager

    public static let pluginIdentifier = "CareSensAirCGMPlugin"
    public static let localizedTitle = "CareSens Air"

    public var pluginIdentifier: String { Self.pluginIdentifier }
    public var managerIdentifier: String { Self.pluginIdentifier }
    public var localizedTitle: String { Self.localizedTitle }
    public let isOnboarded = true
    public var appURL: URL? { nil }
    public var device: HKDevice? {
        HKDevice(name: "CareSens Air", manufacturer: "i-SENS", model: "CSAir",
                 hardwareVersion: nil, firmwareVersion: nil, softwareVersion: nil,
                 localIdentifier: serial, udiDeviceIdentifier: nil)
    }

    // MARK: - CGMManager

    public var cgmManagerStatus: CGMManagerStatus {
        CGMManagerStatus(hasValidSensorSession: true, device: device)
    }
    public var shouldSyncToRemoteService = true
    public var providesBLEHeartbeat = false
    public var managedDataInterval: TimeInterval? = nil
    public var glucoseDisplay: GlucoseDisplayable? { nil }
    public override var debugDescription: String {
        "CareSensAirCGMPlugin(serial: \(serial), running: \(peripheralManager?.state.rawValue ?? "nil"))"
    }

    // MARK: - RawState

    public var rawState: CGMManager.RawStateValue {
        ["serial": serial, "pin": pin, "isFirstConnection": isFirstConnection]
    }

    public required init?(rawState: CGMManager.RawStateValue) {
        guard let serial = rawState["serial"] as? String, !serial.isEmpty else { return nil }
        self.serial = serial
        self.pin = (rawState["pin"] as? String) ?? ""
        self.isFirstConnection = (rawState["isFirstConnection"] as? Bool) ?? true
        super.init()
        startIfNeeded()
    }

    public init(serial: String, pin: String) {
        self.serial = serial
        self.pin = pin
        self.isFirstConnection = true
        super.init()
        startIfNeeded()
    }

    // MARK: - Lifecycle

    public func fetchNewDataIfNeeded(_ completion: @escaping (CGMReadingResult) -> Void) {
        // BLE stream is push-based; nothing to poll.
        completion(.noData)
    }

    private func startIfNeeded() {
        guard peripheralManager == nil else { return }
        let manager = CareSensAirPeripheralManager(serial: serial, isFirstConnection: isFirstConnection)
        manager.delegate = self
        peripheralManager = manager
        manager.start()
    }

    // MARK: - AlertResponder / AlertSoundVendor

    public func acknowledgeAlert(alertIdentifier: Alert.AlertIdentifier, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }
    public func getSoundBaseURL() -> URL? { nil }
    public func getSounds() -> [Alert.Sound] { [] }

    // MARK: - CGMManagerUI

    public var cgmStatusHighlight: DeviceStatusHighlight? { nil }
    public var cgmLifecycleProgress: DeviceLifecycleProgress? { nil }
    public var cgmStatusBadge: DeviceStatusBadge? { nil }
    public static var onboardingImage: UIImage? { nil }
    public var smallImage: UIImage? { nil }

    public static func setupViewController(bluetoothProvider: BluetoothProvider,
                                           displayGlucosePreference: DisplayGlucosePreference,
                                           colorPalette: LoopUIColorPalette,
                                           allowDebugFeatures: Bool,
                                           prefersToSkipUserInteraction: Bool) -> SetupUIResult<CGMManagerViewController, CGMManagerUI> {
        let vc = CareSensAirSetupViewController()
        return .userInteractionRequired(vc)
    }

    public func settingsViewController(bluetoothProvider: BluetoothProvider,
                                       displayGlucosePreference: DisplayGlucosePreference,
                                       colorPalette: LoopUIColorPalette,
                                       allowDebugFeatures: Bool) -> CGMManagerViewController {
        CareSensAirSettingsViewController(manager: self)
    }
}

// MARK: - CGMManager start/stop (LoopKit)

extension CareSensAirCGMPlugin {
    public func start() { startIfNeeded() }
    public func stop() {
        peripheralManager?.stop()
        peripheralManager = nil
    }

    /// Tears down BLE and asks Loop to remove this CGM manager.
    public func requestDeletion() {
        stop()
        delegate.notify { $0?.cgmManagerWantsDeletion(self) }
    }
}

// MARK: - CareSensAirPeripheralManagerDelegate

extension CareSensAirCGMPlugin: CareSensAirPeripheralManagerDelegate {

    func peripheralManager(_ manager: CareSensAirPeripheralManager, didReceive record: CareSensAirProtocol.GlucoseRecord) {
        guard let mgdl = record.currentGlucose else { return }
        let date = record.measurementTime

        // Compute trend rate (mg/dL/min) from the previous reading.
        var trend: GlucoseTrend? = nil
        var trendRate: HKQuantity? = nil
        if let prev = lastGlucoseValue, let prevDate = lastGlucoseDate {
            let minutes = date.timeIntervalSince(prevDate) / 60.0
            if minutes > 0.5 {
                let rate = Double(mgdl - prev) / minutes
                latestTrendRate = rate
                trend = Self.trend(forRate: rate)
                trendRate = HKQuantity(unit: HKUnit.milligramsPerDeciliter.unitDivided(by: .minute()), doubleValue: rate)
            }
        }
        lastGlucoseValue = mgdl
        lastGlucoseDate = date

        let sample = NewGlucoseSample(
            date: date,
            quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: Double(mgdl)),
            condition: nil,
            trend: trend,
            trendRate: trendRate,
            isDisplayOnly: false,
            wasUserEntered: false,
            syncIdentifier: "\(serial)-\(record.sequence)-\(Int(date.timeIntervalSince1970))",
            device: device
        )
        delegate.notify { $0?.cgmManager(self, hasNew: .newData([sample])) }
    }

    func peripheralManager(_ manager: CareSensAirPeripheralManager, didChangeState state: CareSensAirPeripheralManager.State) {
        if state == .running { isFirstConnection = false }
        delegate.notify { $0?.cgmManagerDidUpdateState(self) }
    }

    func peripheralManager(_ manager: CareSensAirPeripheralManager, didError message: String) {
        // Surfaced via logs; Loop treats missing data as stale automatically.
    }

    private static func trend(forRate rate: Double) -> GlucoseTrend {
        switch rate {
        case let r where r > 3:   return .upUpUp
        case let r where r > 2:   return .upUp
        case let r where r > 1:   return .up
        case let r where r >= -1: return .flat
        case let r where r >= -2: return .down
        case let r where r >= -3: return .downDown
        default:                  return .downDownDown
        }
    }
}

// MARK: - Setup UI (enter serial + PIN)

public final class CareSensAirSetupViewController: UIViewController, CGMManagerOnboarding, CompletionNotifying {
    public weak var cgmManagerOnboardingDelegate: CGMManagerOnboardingDelegate?
    public weak var completionDelegate: CompletionDelegate?

    private let serialField = UITextField()
    private let pinField = UITextField()

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "CareSens Air"

        let serialLabel = makeLabel("Sensor serial (12 chars, e.g. C1QBT5A01157)")
        configure(serialField, placeholder: "C1QBT5A0____", autocaps: .allCharacters)
        let pinLabel = makeLabel("PIN code (from the sensor box)")
        configure(pinField, placeholder: "446732", keyboard: .numberPad)

        let stack = UIStackView(arrangedSubviews: [serialLabel, serialField, pinLabel, pinField])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(done))
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
    }

    private func makeLabel(_ text: String) -> UILabel {
        let l = UILabel(); l.text = text; l.numberOfLines = 0; l.font = .preferredFont(forTextStyle: .subheadline); return l
    }
    private func configure(_ field: UITextField, placeholder: String, keyboard: UIKeyboardType = .default, autocaps: UITextAutocapitalizationType = .none) {
        field.placeholder = placeholder
        field.borderStyle = .roundedRect
        field.keyboardType = keyboard
        field.autocapitalizationType = autocaps
        field.autocorrectionType = .no
    }

    @objc private func done() {
        let serial = (serialField.text ?? "").trimmingCharacters(in: .whitespaces).uppercased()
        let pin = (pinField.text ?? "").trimmingCharacters(in: .whitespaces)
        guard serial.count >= 8 else {
            let alert = UIAlertController(title: "Invalid serial", message: "Enter the full sensor serial number.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        let manager = CareSensAirCGMPlugin(serial: serial, pin: pin)
        cgmManagerOnboardingDelegate?.cgmManagerOnboarding(didCreateCGMManager: manager)
        cgmManagerOnboardingDelegate?.cgmManagerOnboarding(didOnboardCGMManager: manager)
        completionDelegate?.completionNotifyingDidComplete(self)
    }

    @objc private func cancel() {
        completionDelegate?.completionNotifyingDidComplete(self)
    }
}

// MARK: - Settings UI

public final class CareSensAirSettingsViewController: UIViewController, CGMManagerOnboarding, CompletionNotifying {
    public weak var cgmManagerOnboardingDelegate: CGMManagerOnboardingDelegate?
    public weak var completionDelegate: CompletionDelegate?

    private let manager: CareSensAirCGMPlugin
    init(manager: CareSensAirCGMPlugin) {
        self.manager = manager
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "CareSens Air"

        let info = UILabel()
        info.numberOfLines = 0
        info.textAlignment = .center
        info.text = "Serial: \(manager.serial)\nPIN: \(manager.pin)"
        info.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(info)

        let deleteButton = UIButton(type: .system)
        deleteButton.setTitle("Delete CGM", for: .normal)
        deleteButton.setTitleColor(.systemRed, for: .normal)
        deleteButton.addTarget(self, action: #selector(deleteManager), for: .touchUpInside)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            info.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            info.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            deleteButton.topAnchor.constraint(equalTo: info.bottomAnchor, constant: 32),
            deleteButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(done))
    }

    @objc private func deleteManager() {
        manager.requestDeletion()
        completionDelegate?.completionNotifyingDidComplete(self)
    }
    @objc private func done() {
        completionDelegate?.completionNotifyingDidComplete(self)
    }
}
