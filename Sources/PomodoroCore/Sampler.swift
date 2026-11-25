import Foundation

public struct SessionSampler {
    public var minMinutes: Double
    public var maxMinutes: Double
    public var steepness: Double

    public init(minMinutes: Double = 10, maxMinutes: Double = 30, steepness: Double = 2.0) {
        self.minMinutes = minMinutes
        self.maxMinutes = maxMinutes
        self.steepness = steepness
    }

    /// Draws seconds using the inverse CDF of a rising truncated exponential.
    public func draw(u: Double) -> TimeInterval {
        guard maxMinutes > minMinutes else { return maxMinutes * 60 }
        let x: Double
        if steepness <= 1e-10 {
            x = u
        } else if u == 0 {
            x = 0
        } else if steepness > 50 {
            // Algebraically equivalent to the inverse CDF, without exp(lambda) overflow.
            x = 1 + log(u + (1 - u) * exp(-steepness)) / steepness
        } else {
            x = log1p(u * expm1(steepness)) / steepness
        }
        let fraction = Swift.min(1, Swift.max(0, x))
        return (minMinutes + fraction * (maxMinutes - minMinutes)) * 60
    }

    public func draw() -> TimeInterval {
        var generator = SystemRandomNumberGenerator()
        return draw(u: Double.random(in: 0..<1, using: &generator))
    }
}

public enum BreakPolicy {
    public static func breakDuration(worked: TimeInterval) -> TimeInterval {
        let minutes = Swift.min(10, Swift.max(3, worked * 0.2 / 60))
        return minutes.rounded() * 60
    }
}
