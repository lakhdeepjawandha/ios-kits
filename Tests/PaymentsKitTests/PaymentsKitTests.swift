import XCTest
import PassKit
@testable import PaymentsKit

// MARK: - Money & cart

final class MoneyCartTests: XCTestCase {
    private func cart() -> PaymentCart {
        PaymentCart(lineItems: [
            LineItem(label: "Flat White", amount: Money(minorUnits: 450, currencyCode: "AUD")),
            LineItem(label: "Muffin", amount: Money(minorUnits: 650, currencyCode: "AUD")),
        ], currencyCode: "AUD", merchantName: "Demo Café", reference: "ORDER-1")
    }

    func testMoneyDecimalConversion() {
        XCTAssertEqual(Money(minorUnits: 1299, currencyCode: "USD").amount, Decimal(string: "12.99"))
        XCTAssertEqual(Money(minorUnits: 0, currencyCode: "USD").amount, Decimal(0))
    }

    func testCartTotalSumsLineItems() {
        XCTAssertEqual(cart().total.minorUnits, 1100)
        XCTAssertEqual(cart().total.amount, Decimal(string: "11.00"))
    }

    func testEmptyCartTotalIsZero() {
        let empty = PaymentCart(lineItems: [], currencyCode: "AUD", merchantName: "X")
        XCTAssertEqual(empty.total.minorUnits, 0)
    }
}

// MARK: - Apple Pay request building

final class ApplePayRequestTests: XCTestCase {
    private let config = ApplePayConfiguration(merchantIdentifier: "merchant.com.example",
                                               countryCode: "AU")
    private func cart() -> PaymentCart {
        PaymentCart(lineItems: [
            LineItem(label: "Flat White", amount: Money(minorUnits: 450, currencyCode: "AUD")),
            LineItem(label: "Muffin", amount: Money(minorUnits: 650, currencyCode: "AUD")),
        ], currencyCode: "AUD", merchantName: "Demo Café")
    }

    func testRequestCarriesConfiguration() {
        let request = ApplePayRequestBuilder.makeRequest(configuration: config, cart: cart())
        XCTAssertEqual(request.merchantIdentifier, "merchant.com.example")
        XCTAssertEqual(request.countryCode, "AU")
        XCTAssertEqual(request.currencyCode, "AUD")
        XCTAssertEqual(request.supportedNetworks, config.supportedNetworks)
        XCTAssertEqual(request.merchantCapabilities, config.merchantCapabilities)
    }

    func testSummaryItemsIncludeLinesAndFinalTotal() {
        let items = ApplePayRequestBuilder.summaryItems(for: cart())
        XCTAssertEqual(items.count, 3) // 2 lines + total
        XCTAssertEqual(items[0].label, "Flat White")
        XCTAssertEqual(items[0].amount, NSDecimalNumber(string: "4.5"))
        let total = items.last!
        XCTAssertEqual(total.label, "Demo Café")
        XCTAssertEqual(total.amount, NSDecimalNumber(string: "11"))
        XCTAssertEqual(total.type, .final)
    }

    func testDefaultNetworksAndCapabilities() {
        XCTAssertEqual(config.supportedNetworks, [.visa, .masterCard, .amex])
        XCTAssertEqual(config.merchantCapabilities, .threeDSecure)
    }
}

// MARK: - Apple Pay result mapping

final class ApplePayResultMappingTests: XCTestCase {
    func testProcessorResultMapsToAuthorizationStatus() {
        let success = ApplePayResultMapper.authorizationResult(for: PaymentResult(success: true, reference: "r"))
        XCTAssertEqual(success.status, .success)
        let failure = ApplePayResultMapper.authorizationResult(for: PaymentResult(success: false, reference: "r"))
        XCTAssertEqual(failure.status, .failure)
    }

    func testStatusMapsToOutcome() {
        XCTAssertEqual(ApplePayResultMapper.outcome(for: .success), .approved)
        XCTAssertEqual(ApplePayResultMapper.outcome(for: .failure), .declined)
    }
}

// MARK: - Mock services

final class MockServiceTests: XCTestCase {
    private func cart(_ items: [LineItem] = [LineItem(label: "X", amount: Money(minorUnits: 100, currencyCode: "AUD"))]) -> PaymentCart {
        PaymentCart(lineItems: items, currencyCode: "AUD", merchantName: "M", reference: "REF")
    }

    func testMockApplePayApproves() async throws {
        let service = MockApplePayService()
        XCTAssertTrue(service.canMakePayments())
        let result = try await service.pay(for: cart())
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.reference, "REF")
    }

    func testMockApplePayEmptyCartThrows() async {
        let service = MockApplePayService()
        do {
            _ = try await service.pay(for: cart([]))
            XCTFail("Expected invalidCart")
        } catch {
            XCTAssertEqual(error as? PaymentError, .invalidCart)
        }
    }

    func testMockApplePayUnavailableThrows() async {
        let service = MockApplePayService(available: false)
        XCTAssertFalse(service.canMakePayments())
        do {
            _ = try await service.pay(for: cart())
            XCTFail("Expected applePayUnavailable")
        } catch {
            XCTAssertEqual(error as? PaymentError, .applePayUnavailable)
        }
    }

    func testMockTapToPayApproves() async throws {
        let service = MockTapToPayService()
        XCTAssertTrue(service.isSupported)
        try await service.linkAccount()
        let result = try await service.collectPayment(for: cart())
        XCTAssertTrue(result.success)
    }

    func testMockTapToPayUnsupportedThrows() async {
        let service = MockTapToPayService(supported: false)
        XCTAssertFalse(service.isSupported)
        do {
            _ = try await service.collectPayment(for: cart())
            XCTFail("Expected tapToPayUnsupported")
        } catch {
            XCTAssertEqual(error as? PaymentError, .tapToPayUnsupported)
        }
    }

    func testMockProcessorDeclineThrows() async {
        let processor = MockPaymentProcessor(approves: false)
        do {
            _ = try await processor.process(ProcessorChargeRequest(amountMinorUnits: 100, currencyCode: "AUD", reference: "r"))
            XCTFail("Expected processorFailed")
        } catch {
            XCTAssertEqual(error as? PaymentError, .processorFailed("Mock declined the charge."))
        }
    }
}

// MARK: - Wallet pass building

final class WalletPassTests: XCTestCase {
    private let builder = WalletPassBuilder()

    private func decode(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    func testReceiptPassEncodesExpectedJSON() throws {
        let cart = PaymentCart(lineItems: [LineItem(label: "Coffee", amount: Money(minorUnits: 500, currencyCode: "AUD"))],
                               currencyCode: "AUD", merchantName: "Café", reference: "ORDER-9")
        let payload = builder.makeReceiptPass(for: cart,
                                              passTypeIdentifier: "pass.com.example.receipt",
                                              teamIdentifier: "TEAM12345")
        let json = decode(try builder.encode(payload))

        XCTAssertEqual(json["formatVersion"] as? Int, 1)
        XCTAssertEqual(json["passTypeIdentifier"] as? String, "pass.com.example.receipt")
        XCTAssertEqual(json["teamIdentifier"] as? String, "TEAM12345")
        XCTAssertEqual(json["organizationName"] as? String, "Café")
        XCTAssertEqual(json["serialNumber"] as? String, "ORDER-9")

        // The style key holds the field structure.
        let store = json["storeCard"] as? [String: Any]
        XCTAssertNotNil(store)
        let primary = store?["primaryFields"] as? [[String: Any]]
        XCTAssertEqual(primary?.first?["key"] as? String, "total")
        XCTAssertEqual(primary?.first?["value"] as? String, "5 AUD")

        // Barcode derived from the reference.
        let barcodes = json["barcodes"] as? [[String: Any]]
        XCTAssertEqual(barcodes?.first?["message"] as? String, "ORDER-9")
    }

    func testLoyaltyPass() throws {
        let payload = builder.makeLoyaltyPass(organizationName: "Brew Club",
                                              memberName: "Ada",
                                              points: 1200,
                                              passTypeIdentifier: "pass.com.example.loyalty",
                                              teamIdentifier: "TEAM12345",
                                              serialNumber: "MEMBER-7")
        XCTAssertEqual(payload.style, .storeCard)
        let json = decode(try builder.encode(payload))
        let store = json["storeCard"] as? [String: Any]
        let primary = store?["primaryFields"] as? [[String: Any]]
        XCTAssertEqual(primary?.first?["value"] as? String, "1200")
    }

    func testMockProviderReturnsSamplePayload() throws {
        let provider = MockWalletPassProvider()
        let cart = PaymentCart(lineItems: [LineItem(label: "Tea", amount: Money(minorUnits: 300, currencyCode: "AUD"))],
                               currencyCode: "AUD", merchantName: "Tea Co", reference: "R-1")
        let data = try provider.makePassJSON(for: cart)
        XCTAssertFalse(data.isEmpty)
        let json = decode(data)
        XCTAssertEqual(json["passTypeIdentifier"] as? String, "pass.com.example.receipt")

        let sample = provider.samplePayload()
        XCTAssertEqual(sample.organizationName, "Demo Café")
    }
}
