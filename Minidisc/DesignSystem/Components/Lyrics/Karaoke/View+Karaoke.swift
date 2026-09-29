import SwiftUI

public extension View {
    /// Karaoke sweep driven by an external clock.
    ///
    /// Use this when the effect must stay in sync with a song position or any
    /// timeline you already own (typically inside a `TimelineView`).
    ///
    /// - Parameters:
    ///   - time:  Current time, on the same axis as `start`/`end`.
    ///   - start: Moment the sweep leaves the leading edge of the text.
    ///   - end:   Moment the sweep reaches the trailing edge (afterglow and
    ///            fall-back follow from here).
    ///   - configuration: Colors and animation parameters.
    func karaoke(
        time: TimeInterval,
        start: TimeInterval,
        end: TimeInterval,
        configuration: KaraokeConfiguration = .standard
    ) -> some View {
        textRenderer(KaraokeRenderer(time: time, start: start, end: end, config: configuration))
    }

    /// Self-looping karaoke sweep: starts playing on appearance and restarts
    /// every `loop` seconds. Within each loop the sweep runs from `start` to `end`.
    ///
    /// - Parameters:
    ///   - start: Moment (within the loop) the sweep leaves the leading edge.
    ///   - end:   Moment the sweep reaches the trailing edge.
    ///   - loop:  Total loop duration in seconds.
    ///   - configuration: Colors and animation parameters.
    func karaokeLoop(
        start: TimeInterval,
        end: TimeInterval,
        loop: TimeInterval,
        configuration: KaraokeConfiguration = .standard
    ) -> some View {
        modifier(KaraokeLoopModifier(start: start, end: end,
                                     loopDuration: loop, configuration: configuration))
    }
}

public struct KaraokeLoopModifier: ViewModifier {
    let start: TimeInterval
    let end: TimeInterval
    let loopDuration: TimeInterval
    let configuration: KaraokeConfiguration
    @State private var epoch = Date()

    public init(
        start: TimeInterval,
        end: TimeInterval,
        loopDuration: TimeInterval,
        configuration: KaraokeConfiguration = .standard
    ) {
        self.start = start
        self.end = end
        self.loopDuration = loopDuration
        self.configuration = configuration
    }

    public func body(content: Content) -> some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(epoch)
                .truncatingRemainder(dividingBy: max(loopDuration, 0.1))
            content.karaoke(time: t, start: start, end: end, configuration: configuration)
        }
    }
}
