import CoreGraphics

public struct ArtworkColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public func blended(with other: Self, amount: Double) -> Self {
        Self(red: red + (other.red - red) * amount,
             green: green + (other.green - green) * amount,
             blue: blue + (other.blue - blue) * amount)
    }

    fileprivate func distance(to other: Self) -> Double {
        let r = red - other.red, g = green - other.green, b = blue - other.blue
        return (r * r + g * g + b * b).squareRoot()
    }

    private var brightness: Double { max(red, green, blue) }
    fileprivate var readable: Self {
        let scale = max(1, 0.5 / max(0.01, brightness))
        let lifted = Self(red: min(1, red * scale), green: min(1, green * scale), blue: min(1, blue * scale))
        // Preserve the hue while giving deep blues enough contrast on the black island.
        let luminance = lifted.red * 0.2126 + lifted.green * 0.7152 + lifted.blue * 0.0722
        return lifted.blended(with: Self(red: 1, green: 1, blue: 1), amount: max(0, (0.16 - luminance) / (1 - luminance)))
    }
}

public enum ArtworkPalette {
    public static let fallback = [ArtworkColor(red: 0.85, green: 0.85, blue: 0.85)]

    /// A bounded 32×32 analysis, performed once on the artwork decoding queue.
    public static func extract(from image: CGImage) -> [ArtworkColor] {
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: bytes.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return fallback }
        struct Bucket {
            var weight = 0.0
            var red = 0.0
            var green = 0.0
            var blue = 0.0
            var color: ArtworkColor { ArtworkColor(red: red / weight, green: green / weight, blue: blue / weight) }
        }
        var buckets = [Bucket](repeating: Bucket(), count: 512)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > 0.5 else { continue }
            let r = min(1, Double(pixels[offset]) / (255 * alpha))
            let g = min(1, Double(pixels[offset + 1]) / (255 * alpha))
            let b = min(1, Double(pixels[offset + 2]) / (255 * alpha))
            let maximum = max(r, g, b)
            let saturation = (maximum - min(r, g, b)) / max(0.01, maximum)
            // Ignore neutral borders and typography, but retain muted artwork hues.
            guard maximum > 0.06, saturation > 0.04 else { continue }
            let index = min(7, Int(r * 8)) * 64 + min(7, Int(g * 8)) * 8 + min(7, Int(b * 8))
            let weight = alpha * (0.9 + 0.1 * saturation)
            buckets[index].weight += weight
            buckets[index].red += r * weight
            buckets[index].green += g * weight
            buckets[index].blue += b * weight
        }
        // Quantization can split a large region across adjacent bins. Compare
        // neighborhoods by coverage, keeping averages of the actual sampled colors.
        let occupied = buckets.filter { $0.weight > 0 }
        guard !occupied.isEmpty else { return fallback }
        func strongest(in candidates: [Bucket]) -> Bucket? {
            candidates.map { seed in
                var cluster = Bucket()
                for bucket in candidates where seed.color.distance(to: bucket.color) < 0.22 {
                    cluster.weight += bucket.weight
                    cluster.red += bucket.red
                    cluster.green += bucket.green
                    cluster.blue += bucket.blue
                }
                return cluster
            }.max { $0.weight < $1.weight }
        }
        guard let dominant = strongest(in: occupied) else { return fallback }
        let remaining = occupied.filter { $0.color.distance(to: dominant.color) > 0.28 }
        let secondary = strongest(in: remaining)
        let totalWeight = occupied.reduce(0) { $0 + $1.weight }
        // Small logos and isolated details should not supply half the gradient.
        if let secondary, secondary.weight >= dominant.weight * 0.25,
           secondary.weight >= totalWeight * 0.12 {
            return [dominant.color.readable, secondary.color.readable]
        }
        return [dominant.color.readable]
    }
}
