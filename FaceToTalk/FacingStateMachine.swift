import Foundation

struct FacingStateMachine: Sendable {
    private enum Segment: Equatable, Sendable {
        case facing
        case away
    }

    private var segment: Segment?
    private var segmentStart: TimeInterval?
    private var segmentHandled = false

    private(set) var progress: FacingProgress = .idle

    mutating func update(
        visualState: VisualState,
        now: TimeInterval,
        openDelay: TimeInterval,
        closeDelay: TimeInterval
    ) -> AutomationAction? {
        let nextSegment: Segment?
        switch visualState {
        case .facing:
            nextSegment = .facing
        case .away, .noFace, .uncertain:
            nextSegment = .away
        case .starting, .interrupted, .unavailable:
            nextSegment = nil
        }

        guard let nextSegment else {
            resetSegment()
            return nil
        }

        if segment != nextSegment || segmentStart == nil {
            segment = nextSegment
            segmentStart = now
            segmentHandled = false
        }

        let start = segmentStart ?? now
        let elapsed = max(0, now - start)
        let target = max(0.05, nextSegment == .facing ? openDelay : closeDelay)
        progress = FacingProgress(
            kind: nextSegment == .facing ? .opening : .closing,
            fraction: min(1, elapsed / target),
            elapsed: elapsed,
            target: target
        )

        guard elapsed >= target, !segmentHandled else { return nil }
        return nextSegment == .facing ? .open : .close
    }

    mutating func acknowledgeCurrentSegment() {
        segmentHandled = true
    }

    mutating func reset() {
        resetSegment()
    }

    private mutating func resetSegment() {
        segment = nil
        segmentStart = nil
        segmentHandled = false
        progress = .idle
    }
}
