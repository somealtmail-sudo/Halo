import XCTest
import CoreGraphics
@testable import HaloCore

final class ArtworkPaletteTests: XCTestCase {
    private func rgb(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> CGColor {
        CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                components: [red, green, blue, alpha])!
    }

    private func cover(_ draw: (CGContext) -> Void) -> CGImage {
        let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8,
                                bytesPerRow: 128, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(context)
        return context.makeImage()!
    }

    func testSolidCoverKeepsItsHueAndLiftsDarkColors() {
        let image = cover {
            $0.setFillColor(rgb(red: 0.35, green: 0.03, blue: 0.02, alpha: 1))
            $0.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        let colors = ArtworkPalette.extract(from: image)
        XCTAssertEqual(colors.count, 1)
        XCTAssertGreaterThanOrEqual(colors[0].red, 0.5)
        XCTAssertLessThan(colors[0].red, 0.6)
        XCTAssertGreaterThan(colors[0].red, colors[0].green * 2)
    }

    func testTwoDistinctCoverColorsAreRetained() {
        let image = cover {
            $0.setFillColor(rgb(red: 1, green: 0, blue: 0, alpha: 1))
            $0.fill(CGRect(x: 0, y: 0, width: 20, height: 32))
            $0.setFillColor(rgb(red: 0, green: 0, blue: 1, alpha: 1))
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
            $0.setFillColor(rgb(red: 0, green: 0.8, blue: 0.1, alpha: 1))
            $0.fill(CGRect(x: 8, y: 8, width: 16, height: 16))
        }
        let color = ArtworkPalette.extract(from: image)[0]
        XCTAssertGreaterThan(color.green, color.red * 2)
    }

    func testMutedCoverPreservesItsActualColor() {
        let image = cover {
            $0.setFillColor(rgb(red: 0.58, green: 0.53, blue: 0.51, alpha: 1))
            $0.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        let color = ArtworkPalette.extract(from: image)[0]
        XCTAssertEqual(color.red, 0.58, accuracy: 0.01)
        XCTAssertEqual(color.green, 0.53, accuracy: 0.01)
        XCTAssertEqual(color.blue, 0.51, accuracy: 0.01)
    }

    func testSimilarShadesOutweighSaturatedAccent() {
        let image = cover {
            for x in 0..<24 {
                let shade = CGFloat(x) / 23
                $0.setFillColor(rgb(red: 0.42 + shade * 0.22,
                                       green: 0.5 + shade * 0.2,
                                       blue: 0.4 + shade * 0.22, alpha: 1))
                $0.fill(CGRect(x: x, y: 0, width: 1, height: 32))
            }
            $0.setFillColor(rgb(red: 1, green: 0, blue: 0, alpha: 1))
            $0.fill(CGRect(x: 24, y: 0, width: 8, height: 32))
        }
        let colors = ArtworkPalette.extract(from: image)
        XCTAssertEqual(colors.count, 2)
        XCTAssertGreaterThan(colors[0].green, colors[0].red)
        XCTAssertGreaterThan(colors[1].red, 0.95)
    }

    func testTinyAccentDoesNotDominateMutedCover() {
        let image = cover {
            $0.setFillColor(rgb(red: 0.56, green: 0.51, blue: 0.48, alpha: 1))
            $0.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            $0.setFillColor(rgb(red: 0, green: 0, blue: 1, alpha: 1))
            $0.fill(CGRect(x: 0, y: 0, width: 2, height: 32))
        }
        let colors = ArtworkPalette.extract(from: image)
        XCTAssertEqual(colors.count, 1)
        XCTAssertEqual(colors[0].red, 0.56, accuracy: 0.01)
        XCTAssertEqual(colors[0].blue, 0.48, accuracy: 0.01)
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
