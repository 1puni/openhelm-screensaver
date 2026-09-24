import Testing
@testable import OpenHelmChartSaverCore

@Suite("Flash timeline")
struct FlashTimelineTests {
    private let timeline = FlashTimeline(
        period: 6,
        pulses: [Pulse(start: 0, end: 0.48), Pulse(start: 0.96, end: 1.44)],
        rampSeconds: 0.072
    )

    @Test func exactWaveform() {
        let samples: [(time: Double, expected: Double)] = [
            (0.0, 0.0), (0.036, 0.5), (0.072, 1.0), (0.24, 1.0),
            (0.444, 0.5), (0.48, 0.0), (0.72, 0.0), (0.96, 0.0),
            (0.996, 0.5), (1.032, 1.0), (1.20, 1.0), (1.404, 0.5),
            (1.44, 0.0), (2.0, 0.0),
        ]
        for sample in samples {
            #expect(abs(Double(timeline.opacity(at: sample.time)) - sample.expected) < 0.000_01)
        }
    }

    @Test func repeatsWithoutDrift() {
        let expected = Double(timeline.opacity(at: 0.24))
        #expect(abs(Double(timeline.opacity(at: 6.24)) - expected) < 0.000_01)
        #expect(abs(Double(timeline.opacity(at: 600_000.24)) - expected) < 0.000_01)
        #expect(abs(Double(timeline.opacity(at: -5.76)) - expected) < 0.000_01)
    }

    @Test func pulseEdgesAreDarkWithoutLeakage() {
        let epsilon = 0.000_001
        for pulse in timeline.pulses {
            #expect(timeline.opacity(at: pulse.start - epsilon) == 0)
            #expect(timeline.opacity(at: pulse.start) == 0)
            #expect(timeline.opacity(at: pulse.start + epsilon) > 0)
            #expect(timeline.opacity(at: pulse.end - epsilon) > 0)
            #expect(timeline.opacity(at: pulse.end) == 0)
            #expect(timeline.opacity(at: pulse.end + epsilon) == 0)
        }
    }

    @Test func rampsAreMonotonic() {
        let rising = [0.0, 0.018, 0.036, 0.054, 0.072].map { timeline.opacity(at: $0) }
        let falling = [0.408, 0.426, 0.444, 0.462, 0.48].map { timeline.opacity(at: $0) }
        #expect(zip(rising, rising.dropFirst()).allSatisfy { $0.0 <= $0.1 })
        #expect(zip(falling, falling.dropFirst()).allSatisfy { $0.0 >= $0.1 })
    }

    @Test func nonFiniteAndInvalidPeriodsAreDark() {
        #expect(timeline.opacity(at: .nan) == 0)
        #expect(FlashTimeline(period: 0, pulses: [], rampSeconds: 0.072).opacity(at: 1) == 0)
    }
}
