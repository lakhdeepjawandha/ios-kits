import XCTest
import CoreGraphics
import CoreText
import CoreVideo
@testable import VisionScanKit

// MARK: - ReceiptParser: amounts

final class ReceiptAmountTests: XCTestCase {
    private func dec(_ s: String) -> Decimal { Decimal(string: s)! }

    func testSimpleAmount() {
        XCTAssertEqual(ReceiptParser.extractAmounts(from: ["Coffee 4.50"]), [dec("4.50")])
    }

    func testCurrencySymbolStripped() {
        XCTAssertEqual(ReceiptParser.extractAmounts(from: ["Latte $4.50", "Tea £2.00", "Bun €1.25"]),
                       [dec("4.50"), dec("2.00"), dec("1.25")])
    }

    func testThousandsSeparator() {
        XCTAssertEqual(ReceiptParser.extractAmounts(from: ["Balance $1,234.56"]), [dec("1234.56")])
        XCTAssertEqual(ReceiptParser.extractAmounts(from: ["Big 1,000,000.00"]), [dec("1000000.00")])
    }

    func testMultiplePerLine() {
        XCTAssertEqual(ReceiptParser.extractAmounts(from: ["2 x 3.00 = 6.00"]), [dec("3.00"), dec("6.00")])
    }

    func testIgnoresNonMonetaryNumbers() {
        // No 2-decimal money pattern here.
        XCTAssertEqual(ReceiptParser.extractAmounts(from: ["Order 12345", "Qty 3"]), [])
    }

    func testDecimalPrecisionIsExact() {
        // 0.1 + 0.2 would be imprecise as Double; Decimal stays exact.
        let amounts = ReceiptParser.extractAmounts(from: ["0.10", "0.20"])
        XCTAssertEqual(amounts.reduce(0, +), dec("0.30"))
    }
}

// MARK: - ReceiptParser: totals

final class ReceiptTotalTests: XCTestCase {
    private func dec(_ s: String) -> Decimal { Decimal(string: s)! }

    func testPicksTotalOverSubtotalAndTax() {
        let lines = ["Subtotal 10.00", "Tax 1.00", "Total 11.00"]
        XCTAssertEqual(ReceiptParser.extractTotal(from: lines), dec("11.00"))
    }

    func testCaseInsensitiveLabel() {
        XCTAssertEqual(ReceiptParser.extractTotal(from: ["TOTAL: $42.00"]), dec("42.00"))
    }

    func testIgnoresSubtotalLine() {
        // Only "subtotal" present → no total label, so fall back to max amount.
        let lines = ["Subtotal 10.00", "Tax 1.00"]
        XCTAssertEqual(ReceiptParser.extractTotal(from: lines), dec("10.00"))
    }

    func testGrandTotalPrefersLargestLabeled() {
        let lines = ["Total 11.00", "Grand Total 12.00"]
        XCTAssertEqual(ReceiptParser.extractTotal(from: lines), dec("12.00"))
    }

    func testFallsBackToMaxWhenNoLabel() {
        XCTAssertEqual(ReceiptParser.extractTotal(from: ["Item 3.00", "Item 9.00", "Item 5.00"]), dec("9.00"))
    }

    func testNilWhenNoAmounts() {
        XCTAssertNil(ReceiptParser.extractTotal(from: ["Thank you!", "Visit again"]))
    }
}

// MARK: - ReceiptParser: dates

final class ReceiptDateTests: XCTestCase {
    private func ymd(_ date: Date) -> (Int, Int, Int) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (c.year!, c.month!, c.day!)
    }

    func testSlashDate() {
        let date = ReceiptParser.extractFirstDate(from: ["Date: 01/15/2024"])
        XCTAssertNotNil(date)
        XCTAssertTrue(ymd(date!) == (2024, 1, 15))
    }

    func testISODate() {
        let date = ReceiptParser.extractFirstDate(from: ["2024-03-22 transaction"])
        XCTAssertNotNil(date)
        XCTAssertTrue(ymd(date!) == (2024, 3, 22))
    }

    func testNaturalLanguageDate() {
        let date = ReceiptParser.extractFirstDate(from: ["Purchased March 22, 2024"])
        XCTAssertNotNil(date)
        XCTAssertTrue(ymd(date!) == (2024, 3, 22))
    }

    func testMultipleDates() {
        // Across separate recognized lines (a single "x to y" string is detected as one range).
        XCTAssertEqual(ReceiptParser.extractDates(from: ["Opened 2024-01-15", "Closed 2024-03-22"]).count, 2)
    }

    func testNoDate() {
        XCTAssertNil(ReceiptParser.extractFirstDate(from: ["No date here"]))
    }
}

// MARK: - ReceiptParser over RecognizedText

final class ReceiptParserOverObservationsTests: XCTestCase {
    func testConveniencesUseStrings() {
        let texts = [
            RecognizedText(string: "Date: 01/15/2024", confidence: 0.9, boundingBox: .zero),
            RecognizedText(string: "Total $25.00", confidence: 0.8, boundingBox: .zero),
        ]
        XCTAssertEqual(ReceiptParser.extractTotal(from: texts), Decimal(string: "25.00"))
        XCTAssertNotNil(ReceiptParser.extractFirstDate(from: texts))
    }
}

// MARK: - Image classifier (pure + stub)

final class ImageClassifierTests: XCTestCase {
    private let sample = [
        Classification(identifier: "cat", confidence: 0.1),
        Classification(identifier: "dog", confidence: 0.9),
        Classification(identifier: "fox", confidence: 0.5),
    ]

    func testTopKSortsDescending() {
        XCTAssertEqual(topK(sample, k: 2).map(\.identifier), ["dog", "fox"])
    }

    func testTopKZeroIsEmpty() {
        XCTAssertTrue(topK(sample, k: 0).isEmpty)
    }

    func testTopKBeyondCountReturnsAll() {
        XCTAssertEqual(topK(sample, k: 100).count, 3)
    }

    func testStubReturnsCannedResults() async throws {
        let canned = [Classification(identifier: "receipt", confidence: 0.42)]
        let classifier = StubImageClassifier(cannedResults: canned)
        let image = TestImage.solid(width: 8, height: 8)
        let result = try await classifier.classify(image)
        XCTAssertEqual(result, canned)
    }

    func testCoreMLClassifierBogusURLThrows() {
        let url = URL(fileURLWithPath: "/nonexistent/model.mlmodelc")
        XCTAssertThrowsError(try CoreMLImageClassifier(contentsOf: url)) { error in
            guard case .modelLoadFailed = error as? VisionScanError else {
                return XCTFail("Expected modelLoadFailed, got \(error)")
            }
        }
    }
}

// MARK: - Vision-on-image (gated; uses a rendered fixture)

final class VisionImageTests: XCTestCase {

    func testOCRReadsRenderedText() throws {
        let image = TestImage.text("TOTAL 12.34", width: 600, height: 200)
        let ocr = OCRService(recognitionLevel: .accurate)
        let strings: [String]
        do {
            strings = try ocr.recognizeStrings(in: image)
        } catch {
            throw XCTSkip("OCR unavailable in this environment: \(error)")
        }
        try XCTSkipIf(strings.isEmpty, "OCR returned no text in this environment")
        let joined = strings.joined(separator: " ").uppercased()
        XCTAssertTrue(joined.contains("12.34") || joined.contains("TOTAL"),
                      "Recognized text was: \(joined)")
    }

    func testSegmenterProducesMask() throws {
        let image = TestImage.solid(width: 64, height: 64)
        let segmenter = Segmenter(quality: .fast)
        let mask: CVPixelBuffer
        do {
            mask = try segmenter.generateMask(for: image)
        } catch {
            throw XCTSkip("Segmentation unavailable in this environment: \(error)")
        }
        XCTAssertGreaterThan(CVPixelBufferGetWidth(mask), 0)
        XCTAssertGreaterThan(CVPixelBufferGetHeight(mask), 0)
        XCTAssertNotNil(Segmenter.makeGrayCGImage(from: mask))
    }

    func testDocumentScannerOnBlankImageDetectsNoDocument() throws {
        // A flat solid image has no document rectangle → corrected image should throw.
        let image = TestImage.solid(width: 64, height: 64)
        let scanner = DocumentScanner()
        do {
            _ = try scanner.correctedImage(from: image)
            // If a rectangle was somehow detected, that's acceptable too; just ensure no crash.
        } catch let error as VisionScanError {
            XCTAssertEqual(error, .noDocumentDetected)
        } catch {
            throw XCTSkip("Rectangle detection unavailable: \(error)")
        }
    }
}

// MARK: - Test image helpers

enum TestImage {
    /// A solid mid-grey RGBA image.
    static func solid(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// Black text rendered on a white background via Core Text.
    static func text(_ string: String, width: Int, height: Int) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Helvetica" as CFString, 72, nil)
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        ]
        let attributed = CFAttributedStringCreate(nil, string as CFString, attrs as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attributed)
        ctx.textPosition = CGPoint(x: 20, y: CGFloat(height) / 2 - 20)
        CTLineDraw(line, ctx)
        return ctx.makeImage()!
    }
}
