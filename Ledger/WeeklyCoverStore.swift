import Foundation
import UIKit

enum WeeklyCoverStore {
    private static let fileName = "weekly-spending-cover.jpg"
    private static let maximumDimension: CGFloat = 1_600

    static func load() -> Data? {
        guard let url = try? coverURL() else { return nil }
        return try? Data(contentsOf: url)
    }

    static func savePhotoData(_ sourceData: Data) throws -> Data {
        guard let sourceImage = UIImage(data: sourceData) else {
            throw WeeklyCoverError.unsupportedImage
        }

        let scale = min(
            1,
            maximumDimension / max(sourceImage.size.width, sourceImage.size.height)
        )
        let outputSize = CGSize(
            width: max(1, sourceImage.size.width * scale),
            height: max(1, sourceImage.size.height * scale)
        )
        let renderer = UIGraphicsImageRenderer(size: outputSize)
        let resizedImage = renderer.image { _ in
            sourceImage.draw(in: CGRect(origin: .zero, size: outputSize))
        }

        guard let data = resizedImage.jpegData(compressionQuality: 0.86) else {
            throw WeeklyCoverError.couldNotEncode
        }

        let url = try coverURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        return data
    }

    static func remove() throws {
        let url = try coverURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static func coverURL() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return directory.appending(path: fileName)
    }
}

enum WeeklyCoverError: LocalizedError {
    case unsupportedImage
    case couldNotEncode

    var errorDescription: String? {
        switch self {
        case .unsupportedImage:
            "Ledger couldn’t read that photo. Choose a different image."
        case .couldNotEncode:
            "Ledger couldn’t prepare that photo for the weekly spending cover."
        }
    }
}
