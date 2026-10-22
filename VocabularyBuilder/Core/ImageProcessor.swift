//
//  ImageProcessor.swift
//  vocabulary_builder
//
//  Compresses images before upload. The web app caps to 1280 px on the long
//  edge and 500 KB; sending a full-resolution photo as base64 inside JSON
//  is the difference between a 2-second request and a failed one. See
//  API.md §10 + IOS_PORTING_GUIDE.md §7.3.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

enum ImageProcessor {
    static let maxDimension: CGFloat = 1280
    static let maxBytes = 500 * 1024

    /// Downscale and re-encode to JPEG. Returns the JPEG data and the raw
    /// base64 string the API expects. Applies EXIF orientation
    /// (`kCGImageSourceCreateThumbnailWithTransform: true`) so portrait
    /// photos do not upload sideways.
    static func prepare(_ data: Data) throws -> (data: Data, base64: String) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw NSError(domain: "ImageProcessor", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not read image."])
        }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else {
            throw NSError(domain: "ImageProcessor", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not downscale image."])
        }
        let mutable = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(mutable, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw NSError(domain: "ImageProcessor", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Could not prepare JPEG output."])
        }
        CGImageDestinationAddImage(dest, thumb, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "ImageProcessor", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Could not finalise JPEG."])
        }
        let jpeg = mutable as Data
        return (jpeg, jpeg.base64EncodedString())
    }
}
