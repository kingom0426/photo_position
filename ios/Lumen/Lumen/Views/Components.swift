import SwiftUI
import UIKit

enum AppAppearance: String, CaseIterable, Identifiable {
    static let storageKey = "appAppearance"

    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随手机系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum LumenTheme {
    static let canvas = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.094, green: 0.102, blue: 0.110, alpha: 1)
            : UIColor(red: 0.950, green: 0.950, blue: 0.940, alpha: 1)
    })
    static let surface = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.137, green: 0.145, blue: 0.157, alpha: 1)
            : .white
    })
    static let ink = Color(.label)
    static let muted = Color(.secondaryLabel)
    static let divider = Color(.separator)
    static let accent = Color(red: 0.85, green: 0.36, blue: 0.22)
}

struct AvatarView: View {
    let text: String
    var size: CGFloat = 38

    var body: some View {
        Group {
            if let url = URL(string: text), url.scheme?.hasPrefix("http") == true {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallback: some View {
        Text(text.count > 2 ? "摄" : text)
            .font(.system(size: size * 0.34, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LumenTheme.ink)
    }
}

struct CurrentUserAvatarView: View {
    let avatar: String
    var size: CGFloat = 34

    var body: some View {
        Group {
            if let url = URL(string: avatar), url.scheme?.hasPrefix("http") == true {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        defaultAvatar
                    }
                }
            } else {
                defaultAvatar
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5))
        .accessibilityLabel("用户头像")
    }

    private var defaultAvatar: some View {
        ZStack {
            Color(.systemGray5)
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.48, weight: .medium))
                .foregroundStyle(Color(.systemGray2))
                .offset(y: size * 0.08)
        }
    }
}

struct CurrentUserToolbarAvatar: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Button {
            if store.isAuthenticated {
                store.selectedTab = 4
            } else {
                store.showingAuthentication = true
            }
        } label: {
            CurrentUserAvatarView(avatar: store.currentUser.avatar)
                .id(toolbarAvatarIdentity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.isAuthenticated ? "打开我的页面" : "打开登录页面")
    }

    private var toolbarAvatarIdentity: String {
        guard store.isAuthenticated else { return "guest-avatar" }
        return "\(store.currentUser.id)|\(store.currentUser.avatar)"
    }
}

struct PostPhotoView: View {
    let post: PhotoPost

    var body: some View {
        ZStack {
            LumenTheme.ink
            if let data = post.imageData, let image = UIImage(data: data) {
                blurredPhoto(Image(uiImage: image))
            } else if let imageURL = post.imageURL {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        blurredPhoto(image)
                    } else if phase.error != nil {
                        PhotoPlaceholderView()
                    } else {
                        ZStack {
                            LumenTheme.ink
                            ProgressView().tint(.white)
                        }
                    }
                }
            } else {
                PhotoPlaceholderView()
            }
        }
        .clipped()
    }

    private func blurredPhoto(_ image: Image) -> some View {
        ZStack {
            image
                .resizable()
                .scaledToFill()
                .scaleEffect(1.12)
                .blur(radius: 24)
            Color.black.opacity(0.16)
            image
                .resizable()
                .scaledToFit()
        }
        .clipped()
    }
}

struct PhotoPlaceholderView: View {
    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.system(size: 28, weight: .light))
                Text("图片不可用")
                    .font(.caption)
            }
            .foregroundStyle(.white.opacity(0.62))
        }
    }
}

struct MetadataGrid: View {
    let metadata: CaptureMetadata

    private var items: [(String, String)] {
        [("相机", metadata.camera), ("镜头", metadata.lens), ("焦段", metadata.focalLength), ("光圈", metadata.aperture), ("快门", metadata.shutterSpeed), ("感光度", metadata.iso)]
            .filter { !$0.1.isEmpty }
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 18) {
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.0).font(.caption2).foregroundStyle(.secondary)
                    Text(item.1).font(.caption.weight(.semibold)).lineLimit(2)
                }
            }
        }
    }
}

struct SectionLabel: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            if let trailing { Text(trailing).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
