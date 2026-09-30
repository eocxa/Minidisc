import SwiftUI

/// All tunable parameters of the karaoke effect — colors, sweep, glow and
/// per-character bounce. The defaults reproduce the feel of Apple Music's
/// karaoke lyrics.
///
/// Create one, change what you need, and pass it to `karaoke(...)` or
/// `karaokeLoop(...)`:
///
/// ```swift
/// Text("no fair")
///     .karaokeLoop(start: 0.5, end: 1.4, loop: 3.2,
///                  configuration: KaraokeConfiguration(litColor: .mint))
/// ```
public struct KaraokeConfiguration: Sendable {

    // MARK: Colors

    /// Color of the not-yet-sung text (typically semi-transparent).
    public var dimColor: Color
    /// Color the text is revealed with as it is sung.
    public var litColor: Color
    /// Color of the glow around freshly sung characters.
    public var glowColor: Color

    // MARK: Sweep

    /// Width in points of the soft lit/dim transition band.
    /// `nil` adapts to the text: `min(totalWidth * 0.6, 34)`.
    public var feather: CGFloat?

    // MARK: Glow

    /// Seconds the glow takes to light up after the sweep passes a character.
    public var glowAttack: TimeInterval
    /// Exponential decay time constant (seconds) of the afterglow.
    public var glowRelease: TimeInterval
    /// Overall glow intensity multiplier. `0` disables the glow.
    public var glowStrength: Double
    /// Radius in points of the inner sharp glow; the outer soft glow is ~2.6×.
    public var glowRadius: CGFloat
    /// Left-to-right stagger (seconds per character) of the afterglow fade-out
    /// once the line ends.
    public var releaseStagger: TimeInterval

    // MARK: Per-character bounce

    /// How high (points) a character lifts as it is swept. `0` disables the bounce.
    public var bounceHeight: CGFloat
    /// Extra scale applied while lifted, anchored at the character's baseline center.
    public var bounceScale: CGFloat
    /// Seconds a character takes to rise.
    public var bounceRise: TimeInterval
    /// How long (seconds) a character stays lifted after being swept before it
    /// falls back — making the fall a left-to-right wave, just like the rise.
    /// `nil` makes all characters wait and fall together when the line ends at `end`.
    public var bounceHold: TimeInterval?
    /// Damping of the settle oscillation (higher = stops sooner).
    public var settleDamping: Double
    /// Frequency (rad/s) of the settle oscillation.
    public var settleFrequency: Double

    public init(
        dimColor: Color = .white.opacity(0.45),
        litColor: Color = .white,
        glowColor: Color = .white,
        feather: CGFloat? = nil,
        glowAttack: TimeInterval = 0.35,
        glowRelease: TimeInterval = 0.35,
        glowStrength: Double = 1.0,
        glowRadius: CGFloat = 4,
        releaseStagger: TimeInterval = 0.09,
        bounceHeight: CGFloat = 0.4,
        bounceScale: CGFloat = 0.003,
        bounceRise: TimeInterval = 0.30,
        bounceHold: TimeInterval? = 0.5,
        settleDamping: Double = 4.5,
        settleFrequency: Double = 6.5
    ) {
        self.dimColor = dimColor
        self.litColor = litColor
        self.glowColor = glowColor
        self.feather = feather
        self.glowAttack = glowAttack
        self.glowRelease = glowRelease
        self.glowStrength = glowStrength
        self.glowRadius = glowRadius
        self.releaseStagger = releaseStagger
        self.bounceHeight = bounceHeight
        self.bounceScale = bounceScale
        self.bounceRise = bounceRise
        self.bounceHold = bounceHold
        self.settleDamping = settleDamping
        self.settleFrequency = settleFrequency
    }

    /// The stock Apple Music feel.
    public static let standard = KaraokeConfiguration()
}
