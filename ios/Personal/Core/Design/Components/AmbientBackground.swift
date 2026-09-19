import SwiftUI
import UIKit

/// The tinted background of a detail page (§3 "Ambient detail background"):
/// the hero image blurred behind the content, fading into `canvas` by 45 % of
/// the screen height. Without an image it is plain `canvas`.
struct AmbientBackground: View {

    var image: UIImage?

    @Environment(\.colorScheme) private var colorScheme

    init(image: UIImage?) {
        self.image = image
    }

    var body: some View {
        GeometryReader { proxy in
            ambient(in: proxy.size)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Dark mode keeps the blur quieter (25 %) so the near-black canvas stays
    /// black; light mode uses 35 %.
    private var imageOpacity: Double {
        colorScheme == .dark ? 0.25 : 0.35
    }

    @ViewBuilder
    private func ambient(in size: CGSize) -> some View {
        ZStack(alignment: .top) {
            Theme.Colors.canvas
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height * 0.45)
                    .clipped()
                    .blur(radius: 40)
                    .saturation(0.7)
                    .opacity(imageOpacity)
                    .mask(alignment: .top) {
                        LinearGradient(
                            colors: [Color.black, Color.black.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom)
                            .frame(width: size.width, height: size.height * 0.45)
                    }
            }
        }
    }
}

// MARK: - Previews

private struct AmbientBackgroundGallery: View {
    var body: some View {
        ZStack {
            AmbientBackground(image: Self.sample())
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Push A")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Today · 00:12:04")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Theme.Spacing.screenInset)
        }
    }

    /// A stand-in hero image; the app passes the exercise illustration.
    private static func sample() -> UIImage {
        let size = CGSize(width: 120, height: 120)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 120))
        }
    }
}

#Preview("Light") {
    AmbientBackgroundGallery()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    AmbientBackgroundGallery()
        .preferredColorScheme(.dark)
}
