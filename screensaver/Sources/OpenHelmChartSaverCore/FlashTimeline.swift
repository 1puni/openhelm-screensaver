import Foundation

public struct FlashTimeline: Equatable, Sendable {
    public let period: Double
    public let pulses: [Pulse]
    public let rampSeconds: Double

    public init(period: Double, pulses: [Pulse], rampSeconds: Double = 0.072) {
        self.period = period
        self.pulses = pulses
        self.rampSeconds = rampSeconds
    }

    public init(light: LightSpec, rampSeconds: Double = 0.072) {
        self.init(period: light.periodSeconds, pulses: light.pulses, rampSeconds: rampSeconds)
    }

    public func opacity(at uptime: TimeInterval) -> Float {
        guard uptime.isFinite, period.isFinite, period > 0 else { return 0 }
        var phase = uptime.truncatingRemainder(dividingBy: period)
        if phase < 0 { phase += period }

        for pulse in pulses where phase >= pulse.start && phase <= pulse.end {
            let duration = pulse.end - pulse.start
            let ramp = min(max(rampSeconds, 0), duration / 2)
            if ramp == 0 { return phase < pulse.end ? 1 : 0 }
            if phase < pulse.start + ramp { return Float((phase - pulse.start) / ramp) }
            if phase > pulse.end - ramp { return Float((pulse.end - phase) / ramp) }
            return 1
        }
        return 0
    }
}
