import XCTest
import CoreGraphics
@testable import HaloCore

final class ArtworkPaletteTests: XCTestCase {
    private func cover(_ draw: (CGContext) -> Void) -> CGImage {
        let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8,
                                bytesPerRow: 128, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(context)
        return context.makeImage()!
    }

    func testSolidCoverKeepsItsHueAndLiftsDarkColors() {
        let image = cover {
            $0.setFillColor(CGColor(red: 0.35, green: 0.03, blue: 0.02, alpha: 1))
            $0.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        let colors = ArtworkPalette.extract(from: image)
        XCTAssertEqual(colors.count, 1)
        XCTAssertGreaterThanOrEqual(colors[0].red, 0.8)
        XCTAssertGreaterThan(colors[0].red, colors[0].green * 2)
    }

    func testTwoDistinctCoverColorsAreRetained() {
        let image = cover {
            $0.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            $0.fill(CGRect(x: 0, y: 0, width: 20, height: 32))
            $0.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
            $0.fill(CGRect(x: 20, y: 0, width: 12, height: 32))
        }
        let colors = ArtworkPalette.extract(from: image)
        XCTAssertEqual(colors.count, 2)
        XCTAssertGreaterThan(colors[0].red, colors[0].blue)
        XCTAssertGreaterThan(colors[1].blue, colors[1].red)
    }

    func testWhiteBackgroundDoesNotWashOutArtworkAccent() {
        let image = cover {
            $0.setFillColor(CGColor(gray: 1, alpha: 1))
            $0.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            $0.setFillColor(CGColor(red: 0, green: 0.8, blue: 0.1, alpha: 1))
            $0.fill(CGRect(x: 8, y: 8, width: 16, height: 16))
        }
        let color = ArtworkPalette.extract(from: image)[0]
        XCTAssertGreaterThan(color.green, color.red * 2)
    }

    func testGrayscaleAndTransparentCoversUseNeutralFallback() {
        let gray = cover {
            $0.setFillColor(CGColor(gray: 0.2, alpha: 1))
            $0.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        XCTAssertEqual(ArtworkPalette.extract(from: gray), ArtworkPalette.fallback)
        XCTAssertEqual(ArtworkPalette.extract(from: cover { _ in }), ArtworkPalette.fallback)
    }
}
