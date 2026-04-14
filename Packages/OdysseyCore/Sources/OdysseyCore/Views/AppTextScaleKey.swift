// Sources/OdysseyCore/Views/AppTextScaleKey.swift
import SwiftUI

// NOTE: Named OdysseyCoreTextScaleKey (not AppTextScaleKey) to avoid collision with
// the private AppTextScaleKey in the macOS target's AppSettings.swift.
// The public EnvironmentValues extension uses the same key name `appTextScale`
// but is in the OdysseyCore module namespace and will not conflict since the
// macOS target's extension is internal only.
private struct OdysseyCoreTextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

public extension EnvironmentValues {
    var appTextScale: CGFloat {
        get { self[OdysseyCoreTextScaleKey.self] }
        set { self[OdysseyCoreTextScaleKey.self] = newValue }
    }
}
