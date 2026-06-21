import Metal
import MetalKit
import CoreGraphics
import CoreImage

/// CPU-side image <-> bytes helpers. These use only Core Graphics, so they run **headless** (no GPU)
/// and are the unit-testable half of RenderKit's image bridging.
public enum ImageBridge {
    /// Render a `CGImage` into a tightly-packed 8-bit RGBA byte buffer (premultiplied alpha).
    ///
    /// - Parameter cgImage: The image to read.
    /// - Returns: `width * height * 4` bytes in R,G,B,A order, or `nil` if a context can't be made.
    public static func rgba8Bytes(from cgImage: CGImage) -> [UInt8]? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let made = data.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: colorSpace,
                                          bitmapInfo: bitmapInfo) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return made ? data : nil
    }

    /// Build a `CGImage` from a tightly-packed 8-bit RGBA byte buffer (premultiplied alpha).
    ///
    /// - Parameters:
    ///   - bytes: `width * height * 4` bytes in R,G,B,A order.
    ///   - width: Pixel width.
    ///   - height: Pixel height.
    /// - Returns: The image, or `nil` if the byte count is wrong or allocation fails.
    public static func makeCGImage(rgba8 bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, bytes.count == width * height * 4 else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width,
                       height: height,
                       bitsPerComponent: 8,
                       bitsPerPixel: 32,
                       bytesPerRow: width * 4,
                       space: colorSpace,
                       bitmapInfo: bitmapInfo,
                       provider: provider,
                       decode: nil,
                       shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}

public extension MetalContext {

    /// Allocate an empty colour texture suitable for rendering into and sampling from.
    ///
    /// - Parameters:
    ///   - width: Pixel width.
    ///   - height: Pixel height.
    ///   - pixelFormat: Pixel format. Default `.rgba8Unorm`.
    ///   - usage: Texture usage. Default `[.shaderRead, .renderTarget]`.
    /// - Returns: The new texture (CPU-readable `.shared` storage).
    /// - Throws: ``RenderError/textureCreationFailed``.
    func makeColorTexture(width: Int,
                          height: Int,
                          pixelFormat: MTLPixelFormat = .rgba8Unorm,
                          usage: MTLTextureUsage = [.shaderRead, .renderTarget]) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat,
                                                                  width: max(1, width),
                                                                  height: max(1, height),
                                                                  mipmapped: false)
        descriptor.usage = usage
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RenderError.textureCreationFailed
        }
        return texture
    }

    /// Create a texture from raw 8-bit RGBA bytes. Handy for test inputs and frame buffers.
    ///
    /// - Parameters:
    ///   - bytes: `width * height * 4` bytes in R,G,B,A order.
    ///   - width: Pixel width.
    ///   - height: Pixel height.
    func makeTexture(rgba8 bytes: [UInt8], width: Int, height: Int) throws -> MTLTexture {
        guard bytes.count == width * height * 4 else { throw RenderError.textureCreationFailed }
        let texture = try makeColorTexture(width: width, height: height)
        bytes.withUnsafeBytes { raw in
            texture.replace(region: MTLRegionMake2D(0, 0, width, height),
                            mipmapLevel: 0,
                            withBytes: raw.baseAddress!,
                            bytesPerRow: width * 4)
        }
        return texture
    }

    /// Load a `CGImage` into a Metal texture (sRGB decoding disabled, so values stay linear `0...1`).
    ///
    /// - Parameter cgImage: The image to upload.
    /// - Returns: An `.rgba8Unorm` texture usable as a filter input.
    func makeTexture(from cgImage: CGImage) throws -> MTLTexture {
        let loader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .textureUsage: NSNumber(value: MTLTextureUsage([.shaderRead, .renderTarget]).rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.shared.rawValue)
        ]
        do {
            return try loader.newTexture(cgImage: cgImage, options: options)
        } catch {
            throw RenderError.textureCreationFailed
        }
    }

    /// Read a texture back into a `CGImage`. The texture must be `.rgba8Unorm` with CPU-readable
    /// storage (textures from this type's helpers qualify).
    ///
    /// - Parameter texture: The texture to read.
    /// - Returns: The image.
    /// - Throws: ``RenderError/textureReadFailed``.
    func makeCGImage(from texture: MTLTexture) throws -> CGImage {
        let width = texture.width
        let height = texture.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            texture.getBytes(raw.baseAddress!,
                             bytesPerRow: width * 4,
                             from: MTLRegionMake2D(0, 0, width, height),
                             mipmapLevel: 0)
        }
        guard let image = ImageBridge.makeCGImage(rgba8: bytes, width: width, height: height) else {
            throw RenderError.textureReadFailed
        }
        return image
    }

    /// Wrap a Metal texture as a `CIImage` (no copy). Useful for handing GPU output to Core Image.
    func makeCIImage(from texture: MTLTexture) -> CIImage? {
        CIImage(mtlTexture: texture, options: [.colorSpace: CGColorSpaceCreateDeviceRGB()])
    }

    /// Render a `CIImage` into a new Metal texture using the provided Core Image context.
    ///
    /// - Parameters:
    ///   - ciImage: The image to render. Must have a finite extent.
    ///   - ciContext: A `CIContext` (ideally created with this device).
    /// - Returns: An `.rgba8Unorm` texture containing the rendered image.
    /// - Throws: ``RenderError/textureCreationFailed``.
    func makeTexture(from ciImage: CIImage, ciContext: CIContext) throws -> MTLTexture {
        let extent = ciImage.extent
        guard !extent.isInfinite, extent.width >= 1, extent.height >= 1 else {
            throw RenderError.textureCreationFailed
        }
        let texture = try makeColorTexture(width: Int(extent.width), height: Int(extent.height))
        ciContext.render(ciImage,
                         to: texture,
                         commandBuffer: nil,
                         bounds: extent,
                         colorSpace: CGColorSpaceCreateDeviceRGB())
        return texture
    }
}
