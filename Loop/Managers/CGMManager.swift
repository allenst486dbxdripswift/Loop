//
//  CGMManager.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopKitUI
import MockKit

let staticCGMManagersByIdentifier: [String: CGMManager.Type] = [
    MockCGMManager.pluginIdentifier: MockCGMManager.self,
    CareSensAirCGMPlugin.pluginIdentifier: CareSensAirCGMPlugin.self,
]

var availableStaticCGMManagers: [CGMManagerDescriptor] {
        // CareSens Air is always selectable; the Mock CGM only in simulator builds.
        var managers = [
            CGMManagerDescriptor(identifier: CareSensAirCGMPlugin.pluginIdentifier, localizedTitle: CareSensAirCGMPlugin.localizedTitle)
        ]
        if FeatureFlags.allowSimulators {
            managers.insert(CGMManagerDescriptor(identifier: MockCGMManager.pluginIdentifier, localizedTitle: MockCGMManager.localizedTitle), at: 0)
        }
        return managers
}

func CGMManagerFromRawValue(_ rawValue: [String: Any]) -> CGMManager? {
    guard let managerIdentifier = rawValue["managerIdentifier"] as? String,
        let rawState = rawValue["state"] as? CGMManager.RawStateValue,
        let Manager = staticCGMManagersByIdentifier[managerIdentifier]
    else {
        return nil
    }
    
    return Manager.init(rawState: rawState)
}

extension CGMManager {

    typealias RawValue = [String: Any]
    
    var rawValue: [String: Any] {
        return [
            "managerIdentifier": pluginIdentifier,
            "state": self.rawState
        ]
    }
}
