import Photos
import SwiftUI

enum Links {
    static let privacy = URL(string: "https://jimtarfas.github.io/phone-cleaner-site/privacy.html")!
    static let support = URL(string: "https://jimtarfas.github.io/phone-cleaner-site/support.html")!
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let settings = URL(string: UIApplication.openSettingsURLString)!
    static let appStoreID = "6826949859"
    static let review = URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")!
}

enum Theme {
    static let gradient = LinearGradient(colors: [Color(red: 0.15, green: 0.39, blue: 0.92), Color(red: 0.02, green: 0.71, blue: 0.83)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
    static let keep = Color.green
    static let delete = Color.red
}

extension Font {
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

/// A card surface used across the app.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

/// Loads images from Photos at the size they're shown.
enum ImageLoader {
    static let manager = PHCachingImageManager()

    static func image(for asset: PHAsset, side: CGFloat, mode: PHImageContentMode = .aspectFill) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            manager.requestImage(for: asset, targetSize: CGSize(width: side, height: side), contentMode: mode, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

/// A photo or video thumbnail that fills its frame.
struct AssetImage: View {
    let asset: PHAsset
    var side: CGFloat = 160
    var fit = false

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Color(.tertiarySystemFill)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: fit ? .fit : .fill)
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: asset.localIdentifier) {
                let loaded = await ImageLoader.image(for: asset, side: side * displayScale, mode: fit ? .aspectFit : .aspectFill)
                withAnimation(.easeOut(duration: 0.15)) { image = loaded }
            }
    }
}

/// A square grid cell with a selection mark, used by every cleaning screen.
struct SelectableThumbnail: View {
    let item: MediaItem
    let selected: Bool
    var badge: String? = nil
    var showsSize = true

    var body: some View {
        AssetImage(asset: item.asset)
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.green, in: Capsule())
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 4) {
                    if item.isVideo {
                        Image(systemName: "video.fill")
                        Text(Duration.seconds(item.asset.duration).formatted(.time(pattern: .minuteSecond)))
                    }
                    if showsSize { Text(item.bytes.formattedBytes) }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .shadow(radius: 2)
                .padding(6)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, selected ? Color.accentColor : .black.opacity(0.25))
                    .shadow(radius: 2)
                    .padding(6)
            }
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.isVideo ? "Video, \(item.bytes.formattedBytes)" : "Photo, \(item.bytes.formattedBytes)")
            .accessibilityValue(selected ? "Selected for deletion" : "Not selected")
            .accessibilityAddTraits(.isButton)
    }
}

/// A large preview shown when you long-press a thumbnail.
struct AssetPreview: View {
    let asset: PHAsset

    var body: some View {
        AssetImage(asset: asset, side: 600, fit: true)
            .frame(width: 340, height: 340 * CGFloat(max(asset.pixelHeight, 1)) / CGFloat(max(asset.pixelWidth, 1)))
            .frame(maxHeight: 560)
    }
}
