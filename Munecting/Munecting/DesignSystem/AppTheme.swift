import SwiftUI
import UIKit

enum AppTheme {
    static let background = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let accent = Color(red: 0.56, green: 0.36, blue: 0.96)

    enum Typography {
        static let rowTitle: Font = .subheadline.weight(.semibold)
        static let metadata: Font = .caption
        static let message: Font = .caption
        static let sectionTitle: Font = .subheadline.weight(.semibold)
        static let button: Font = .subheadline.weight(.semibold)
    }

    enum Spacing {
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 20
        static let section: CGFloat = 28
    }

    enum Radius {
        static let small: CGFloat = 12
        static let medium: CGFloat = 18
        static let large: CGFloat = 28
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.Typography.button)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.accent)
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct ArtworkView: View {
    let artwork: ArtworkStyle
    var cornerRadius: CGFloat = AppTheme.Radius.small

    var body: some View {
        ZStack {
            fallback
            if let imageURL = artwork.imageURL {
                AsyncImage(url: imageURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(LinearGradient(colors: artwork.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay { Image(systemName: artwork.symbol).font(.title2).foregroundStyle(.white.opacity(0.65)) }
    }
}
