#if canImport(CoreSpotlight) && !os(watchOS)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import SYSKit

final class SYSSearchThumbnailTests: XCTestCase {
    private struct RGB {
        let red: Int
        let green: Int
        let blue: Int
        var lightest: Int { min(red, green, blue) }
    }

    private func png(width: Int, height: Int, draw: (CGContext) -> Void) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        draw(context)
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func redLeftBlueRight(width: Int, height: Int) throws -> Data {
        try png(width: width, height: height) { context in
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
            context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        }
    }

    private func pixel(_ jpeg: Data, x: Int, y: Int) throws -> RGB {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let offset = y * context.bytesPerRow + x * 4
        return RGB(red: Int(bytes[offset]), green: Int(bytes[offset + 1]), blue: Int(bytes[offset + 2]))
    }

    private func size(of jpeg: Data) throws -> (width: Int, height: Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height)
    }

    func testFillMakesASquareJPEGThatIsSmallEnoughForTheList() throws {
        let result = try XCTUnwrap(SYSSearchThumbnail.jpeg(from: try redLeftBlueRight(width: 1600, height: 800)))
        XCTAssertEqual(Array(result.prefix(2)), [0xFF, 0xD8])
        let dimensions = try size(of: result)
        XCTAssertEqual(dimensions.width, SYSSearchThumbnail.side)
        XCTAssertEqual(dimensions.height, SYSSearchThumbnail.side)
        XCTAssertLessThan(result.count, 60_000)
    }

    func testFillCropsToTheCentreInsteadOfSqueezing() throws {
        let result = try XCTUnwrap(SYSSearchThumbnail.jpeg(from: try redLeftBlueRight(width: 800, height: 400)))
        let left = try pixel(result, x: 20, y: 180)
        let right = try pixel(result, x: 340, y: 180)
        XCTAssertGreaterThan(left.red, 200)
        XCTAssertLessThan(left.blue, 60)
        XCTAssertGreaterThan(right.blue, 200)
        XCTAssertLessThan(right.red, 60)
    }

    func testFitKeepsTheWholePictureOnWhite() throws {
        let wide = try redLeftBlueRight(width: 800, height: 400)
        let result = try XCTUnwrap(SYSSearchThumbnail.jpeg(from: wide, mode: .fit))
        let corner = try pixel(result, x: 4, y: 4)
        let above = try pixel(result, x: 180, y: 30)
        let inside = try pixel(result, x: 90, y: 180)
        XCTAssertGreaterThan(corner.lightest, 240)
        XCTAssertGreaterThan(above.lightest, 240)
        XCTAssertGreaterThan(inside.red, 200)
        XCTAssertLessThan(inside.green, 60)
    }

    func testTransparencyIsSetOnWhite() throws {
        let clear = try png(width: 300, height: 300) { _ in }
        let result = try XCTUnwrap(SYSSearchThumbnail.jpeg(from: clear))
        XCTAssertGreaterThan(try pixel(result, x: 4, y: 4).lightest, 240)
    }

    func testSomethingThatIsNotAPictureGivesNothing() {
        XCTAssertNil(SYSSearchThumbnail.jpeg(from: Data("not an image".utf8)))
    }

    func testTheTitleComesFirstThenHostedWordsThenTheAppsOwn() {
        let entry = SYSSearchEntry(id: "1", title: "Animals", keywords: ["kids", "Alphabet", "toddler"])
        XCTAssertEqual(
            entry.searchKeywords(adding: ["alphabet", "abc"], limit: 30),
            ["Animals", "alphabet", "abc", "kids", "toddler"]
        )
    }

    func testKeywordsAreCappedWithTheHostedWordsKept() {
        let entry = SYSSearchEntry(id: "1", title: "T", keywords: (1...40).map { "own\($0)" })
        let words = entry.searchKeywords(adding: ["hosted"], limit: 30)
        XCTAssertEqual(words.count, 30)
        XCTAssertEqual(Array(words.prefix(2)), ["T", "hosted"])
    }

    func testAnEntryChangesItsSignatureWhenAnythingShownChanges() {
        func entry(
            title: String = "Animals",
            keywords: [String] = ["kids"],
            thumbnail: SYSSearchEntry.Picture? = nil
        ) -> String {
            SYSSearchEntry(id: "1", title: title, summary: "Learn", keywords: keywords, thumbnail: thumbnail).signature(adding: [])
        }
        XCTAssertNotEqual(
            SYSSearchEntry(id: "1", title: "Animals").signature(adding: ["abc"]),
            SYSSearchEntry(id: "1", title: "Animals").signature(adding: [])
        )
        XCTAssertEqual(entry(), entry())
        XCTAssertNotEqual(entry(), entry(title: "Animal"))
        XCTAssertNotEqual(entry(), entry(keywords: ["kids", "abc"]))
        XCTAssertNotEqual(entry(), entry(thumbnail: .file(URL(fileURLWithPath: "/a/b.png"))))
        XCTAssertEqual(entry(thumbnail: .render(key: "p-1") { nil }), entry(thumbnail: .render(key: "p-1") { Data() }))
        XCTAssertNotEqual(entry(thumbnail: .render(key: "p-1") { nil }), entry(thumbnail: .render(key: "p-2") { nil }))
    }
}
#endif
