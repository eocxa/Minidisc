import Foundation
import Observation

nonisolated enum EqualizerPreset: String, CaseIterable, Identifiable, Sendable, Codable {
    case bassBoost
    case electronic
    case hipHop
    case rock
    case pop
    case acoustic
    case flat
    case manual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bassBoost:
            return "Bass Boost"
        case .electronic:
            return "Electronic"
        case .hipHop:
            return "Hip-Hop"
        case .rock:
            return "Rock"
        case .pop:
            return "Pop"
        case .acoustic:
            return "Acoustic"
        case .flat:
            return "Flat"
        case .manual:
            return "Manual"
        }
    }

    /// Default gains in dB for the 6 bands: [60Hz, 150Hz, 400Hz, 1kHz, 2.4kHz, 15kHz]
    var defaultGains: [Float] {
        switch self {
        case .bassBoost:
            return [5.0, 3.5, 0.5, 0.0, 0.0, 0.0]
        case .electronic:
            return [4.5, 3.0, 0.0, 1.0, 2.0, 4.0]
        case .hipHop:
            return [5.5, 3.5, 1.0, 0.0, 1.5, 2.5]
        case .rock:
            return [4.0, 2.5, -1.0, 1.0, 3.0, 3.5]
        case .pop:
            return [2.0, 3.0, 1.0, 2.0, 3.0, 2.0]
        case .acoustic:
            return [2.5, 2.0, 1.0, 2.0, 2.5, 3.5]
        case .flat, .manual:
            return [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
        }
    }
}

nonisolated struct EqualizerBandInfo: Identifiable, Sendable {
    let id: Int
    let frequency: Double
    let label: String

    static let bands: [EqualizerBandInfo] = [
        EqualizerBandInfo(id: 0, frequency: 60, label: "60 Hz"),
        EqualizerBandInfo(id: 1, frequency: 150, label: "150 Hz"),
        EqualizerBandInfo(id: 2, frequency: 400, label: "400 Hz"),
        EqualizerBandInfo(id: 3, frequency: 1000, label: "1 kHz"),
        EqualizerBandInfo(id: 4, frequency: 2400, label: "2.4 kHz"),
        EqualizerBandInfo(id: 5, frequency: 15000, label: "15 kHz")
    ]
}

nonisolated struct EqualizerConfig: Sendable, Equatable {
    let enabled: Bool
    let preset: EqualizerPreset
    let gains: [Float]

    var isActive: Bool {
        guard enabled else { return false }
        return gains.contains { abs($0) > 0.05 }
    }

    static let flat = EqualizerConfig(
        enabled: false,
        preset: .flat,
        gains: [0, 0, 0, 0, 0, 0]
    )
}

@Observable
@MainActor
final class EqualizerSettings {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var _enabled: Bool
    @ObservationIgnored private var _preset: EqualizerPreset
    @ObservationIgnored private var _gains: [Float]

    private static let enabledKey = "minidisc.equalizer.enabled"
    private static let presetKey = "minidisc.equalizer.preset"
    private static let gainsKey = "minidisc.equalizer.gains"

    var enabled: Bool {
        get {
            access(keyPath: \.enabled)
            return _enabled
        }
        set {
            withMutation(keyPath: \.enabled) {
                _enabled = newValue
            }
            defaults.set(newValue, forKey: Self.enabledKey)
        }
    }

    var preset: EqualizerPreset {
        get {
            access(keyPath: \.preset)
            return _preset
        }
        set {
            withMutation(keyPath: \.preset) {
                _preset = newValue
            }
            defaults.set(newValue.rawValue, forKey: Self.presetKey)
        }
    }

    var gains: [Float] {
        get {
            access(keyPath: \.gains)
            return _gains
        }
        set {
            withMutation(keyPath: \.gains) {
                _gains = newValue
            }
            defaults.set(newValue.map { Double($0) }, forKey: Self.gainsKey)
        }
    }

    var config: EqualizerConfig {
        EqualizerConfig(
            enabled: enabled,
            preset: preset,
            gains: gains
        )
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self._enabled = defaults.bool(forKey: Self.enabledKey)
        let presetRaw = defaults.string(forKey: Self.presetKey) ?? EqualizerPreset.flat.rawValue
        let resolvedPreset = EqualizerPreset(rawValue: presetRaw) ?? .flat
        self._preset = resolvedPreset

        if let savedGains = defaults.array(forKey: Self.gainsKey) as? [Double], savedGains.count == 6 {
            self._gains = savedGains.map { Float($0) }
        } else {
            self._gains = resolvedPreset.defaultGains
        }
    }

    func selectPreset(_ newPreset: EqualizerPreset) {
        preset = newPreset
        if newPreset != .manual {
            gains = newPreset.defaultGains
        }
    }

    func setBandGain(at index: Int, to value: Float) {
        guard index >= 0, index < _gains.count else { return }
        var updated = _gains
        updated[index] = value
        gains = updated
        if preset != .manual {
            preset = .manual
        }
    }

    func resetToFlat() {
        selectPreset(.flat)
    }
}
