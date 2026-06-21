import Foundation

/// A Wallet pass style (maps to the top-level structure key in `pass.json`).
public enum PassStyle: String, Sendable, Equatable {
    case generic, storeCard, coupon, eventTicket, boardingPass
}

/// A single key/label/value field shown on a pass.
public struct PassField: Equatable, Sendable {
    public let key: String
    public let label: String
    public let value: String
    public init(key: String, label: String, value: String) {
        self.key = key; self.label = label; self.value = value
    }
    var dictionary: [String: Any] { ["key": key, "label": label, "value": value] }
}

/// A pass barcode (PassKit `barcodes` entry).
public struct PassBarcode: Equatable, Sendable {
    public let message: String
    public let format: String          // e.g. "PKBarcodeFormatQR"
    public let messageEncoding: String // e.g. "iso-8859-1"
    public init(message: String, format: String = "PKBarcodeFormatQR", messageEncoding: String = "iso-8859-1") {
        self.message = message; self.format = format; self.messageEncoding = messageEncoding
    }
    var dictionary: [String: Any] { ["message": message, "format": format, "messageEncoding": messageEncoding] }
}

/// The data model for a `pass.json` payload (the contents of a Wallet pass, before signing).
public struct WalletPassPayload: Equatable, Sendable {
    /// PassKit format version (always `1`).
    public let formatVersion = 1
    public var passTypeIdentifier: String
    public var serialNumber: String
    public var teamIdentifier: String
    public var organizationName: String
    public var description: String
    public var style: PassStyle
    public var headerFields: [PassField]
    public var primaryFields: [PassField]
    public var secondaryFields: [PassField]
    public var auxiliaryFields: [PassField]
    public var barcode: PassBarcode?
    public var backgroundColor: String?
    public var foregroundColor: String?

    public init(passTypeIdentifier: String,
                serialNumber: String,
                teamIdentifier: String,
                organizationName: String,
                description: String,
                style: PassStyle,
                headerFields: [PassField] = [],
                primaryFields: [PassField] = [],
                secondaryFields: [PassField] = [],
                auxiliaryFields: [PassField] = [],
                barcode: PassBarcode? = nil,
                backgroundColor: String? = nil,
                foregroundColor: String? = nil) {
        self.passTypeIdentifier = passTypeIdentifier
        self.serialNumber = serialNumber
        self.teamIdentifier = teamIdentifier
        self.organizationName = organizationName
        self.description = description
        self.style = style
        self.headerFields = headerFields
        self.primaryFields = primaryFields
        self.secondaryFields = secondaryFields
        self.auxiliaryFields = auxiliaryFields
        self.barcode = barcode
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
    }
}

/// Assembles `pass.json` payloads for Wallet passes (receipts, loyalty cards, etc.).
///
/// ## Signing a real `.pkpass` (certificate requirement)
/// `WalletPassBuilder` produces only the **`pass.json`** content. A loadable `.pkpass` is a signed
/// ZIP and additionally requires (all needing a **paid Apple Developer account**):
/// 1. A **Pass Type ID** and its **Pass Type ID certificate**, plus the **Apple WWDR** certificate.
/// 2. The `com.apple.developer.pass-type-identifiers` entitlement (to add passes via
///    `PKAddPassesViewController`).
/// 3. A `manifest.json` of SHA-1 hashes of every file, signed (PKCS#7 detached) with the Pass Type
///    ID certificate to produce `signature`, then zipped with `pass.json` and images.
///
/// Signing is typically done **server-side**. Once you have signed `.pkpass` bytes, load them with
/// `PKPass(data:)` and present `PKAddPassesViewController`. Use ``encode(_:)`` here for the payload
/// and ``MockWalletPassProvider`` for a ready sample during development.
public struct WalletPassBuilder: Sendable {
    public init() {}

    /// Serialize a payload to `pass.json` data (sorted keys for stable, testable output).
    ///
    /// - Parameter payload: The pass payload.
    /// - Returns: UTF-8 JSON data matching the PassKit `pass.json` schema.
    /// - Throws: ``PaymentError/passEncodingFailed`` if serialization fails.
    public func encode(_ payload: WalletPassPayload) throws -> Data {
        var json: [String: Any] = [
            "formatVersion": payload.formatVersion,
            "passTypeIdentifier": payload.passTypeIdentifier,
            "serialNumber": payload.serialNumber,
            "teamIdentifier": payload.teamIdentifier,
            "organizationName": payload.organizationName,
            "description": payload.description,
        ]
        if let backgroundColor = payload.backgroundColor { json["backgroundColor"] = backgroundColor }
        if let foregroundColor = payload.foregroundColor { json["foregroundColor"] = foregroundColor }

        var structure: [String: Any] = [:]
        if !payload.headerFields.isEmpty { structure["headerFields"] = payload.headerFields.map(\.dictionary) }
        if !payload.primaryFields.isEmpty { structure["primaryFields"] = payload.primaryFields.map(\.dictionary) }
        if !payload.secondaryFields.isEmpty { structure["secondaryFields"] = payload.secondaryFields.map(\.dictionary) }
        if !payload.auxiliaryFields.isEmpty { structure["auxiliaryFields"] = payload.auxiliaryFields.map(\.dictionary) }
        json[payload.style.rawValue] = structure

        if let barcode = payload.barcode {
            json["barcodes"] = [barcode.dictionary]
        }

        do {
            return try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .prettyPrinted])
        } catch {
            throw PaymentError.passEncodingFailed
        }
    }

    /// Build a **receipt** pass (a `storeCard`) summarizing a cart total.
    ///
    /// - Parameters:
    ///   - cart: The purchased cart (its total and merchant name are used).
    ///   - passTypeIdentifier: Your Pass Type ID (`pass.com.example.receipt`).
    ///   - teamIdentifier: Your Apple Developer Team ID.
    ///   - serialNumber: Unique serial for this pass. Default the cart reference.
    /// - Returns: A ready-to-encode payload.
    public func makeReceiptPass(for cart: PaymentCart,
                                passTypeIdentifier: String,
                                teamIdentifier: String,
                                serialNumber: String? = nil) -> WalletPassPayload {
        let totalString = "\(cart.total.amount) \(cart.currencyCode)"
        return WalletPassPayload(
            passTypeIdentifier: passTypeIdentifier,
            serialNumber: serialNumber ?? (cart.reference.isEmpty ? "receipt" : cart.reference),
            teamIdentifier: teamIdentifier,
            organizationName: cart.merchantName,
            description: "Receipt from \(cart.merchantName)",
            style: .storeCard,
            headerFields: [PassField(key: "merchant", label: "Merchant", value: cart.merchantName)],
            primaryFields: [PassField(key: "total", label: "Total", value: totalString)],
            secondaryFields: [PassField(key: "reference", label: "Reference", value: cart.reference)],
            barcode: cart.reference.isEmpty ? nil : PassBarcode(message: cart.reference)
        )
    }

    /// Build a **loyalty** pass (a `storeCard`) for a member and point balance.
    public func makeLoyaltyPass(organizationName: String,
                                memberName: String,
                                points: Int,
                                passTypeIdentifier: String,
                                teamIdentifier: String,
                                serialNumber: String) -> WalletPassPayload {
        WalletPassPayload(
            passTypeIdentifier: passTypeIdentifier,
            serialNumber: serialNumber,
            teamIdentifier: teamIdentifier,
            organizationName: organizationName,
            description: "\(organizationName) loyalty card",
            style: .storeCard,
            primaryFields: [PassField(key: "points", label: "Points", value: String(points))],
            secondaryFields: [PassField(key: "member", label: "Member", value: memberName)],
            barcode: PassBarcode(message: serialNumber)
        )
    }
}

/// A seam for producing pass payloads, so apps can depend on a protocol and swap a real signing
/// backend in later.
public protocol WalletPassProviding: Sendable {
    /// Produce `pass.json` data for a cart.
    func makePassJSON(for cart: PaymentCart) throws -> Data
}

/// A mock provider returning a sample receipt `pass.json` using placeholder identifiers — useful
/// for development and previews before you have a Pass Type ID / certificates.
public struct MockWalletPassProvider: WalletPassProviding {
    private let builder = WalletPassBuilder()
    /// Placeholder Pass Type ID used in the sample.
    public let passTypeIdentifier: String
    /// Placeholder Team ID used in the sample.
    public let teamIdentifier: String

    /// Create a mock provider.
    public init(passTypeIdentifier: String = "pass.com.example.receipt",
                teamIdentifier: String = "ABCDE12345") {
        self.passTypeIdentifier = passTypeIdentifier
        self.teamIdentifier = teamIdentifier
    }

    public func makePassJSON(for cart: PaymentCart) throws -> Data {
        let payload = builder.makeReceiptPass(for: cart,
                                              passTypeIdentifier: passTypeIdentifier,
                                              teamIdentifier: teamIdentifier)
        return try builder.encode(payload)
    }

    /// A ready sample cart + pass payload, handy for previews/tests.
    public func samplePayload() -> WalletPassPayload {
        let cart = PaymentCart(lineItems: [LineItem(label: "Flat White", amount: Money(minorUnits: 450, currencyCode: "AUD"))],
                               currencyCode: "AUD", merchantName: "Demo Café", reference: "ORDER-1001")
        return builder.makeReceiptPass(for: cart,
                                       passTypeIdentifier: passTypeIdentifier,
                                       teamIdentifier: teamIdentifier)
    }
}
