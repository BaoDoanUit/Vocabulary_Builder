//
//  ImageCache.swift
//  vocabulary_builder
//
//  In-memory image cache keyed by URL string. Avoids refetching the same
//  media file on every navigation. Replaces the web app's sessionStorage
//  TTL cache. See IOS_PORTING_GUIDE.md §6 + §9.
//

import Foundation
import UIKit

@MainActor
final class ImageCache: ObservableObject {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 64 * 1024 * 1024 // 64 MB
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    func store(_ image: UIImage, for url: URL) {
        let bytes = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: url.absoluteString as NSString, cost: bytes)
    }

    /// Load (and cache) an image from a URL. Network is off-main; the
    /// returned image is delivered back on the main actor.
    func load(_ url: URL) async -> UIImage? {
        if let cached = image(for: url) { return cached }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let img = UIImage(data: data) else { return nil }
            store(img, for: url)
            return img
        } catch {
            return nil
        }
    }
}
