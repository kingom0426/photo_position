import SwiftUI
import UIKit

enum LumenTheme {
    static let canvas = Color(red: 0.957, green: 0.949, blue: 0.925)
    static let surface = Color(red: 0.984, green: 0.980, blue: 0.965)
    static let ink = Color(red: 0.086, green: 0.094, blue: 0.090)
    static let muted = Color(red: 0.45, green: 0.46, blue: 0.44)
    static let accent = Color(red: 0.85, green: 0.36, blue: 0.22)
}

struct AvatarView: View {
    let text: String
    var size: CGFloat = 38

    var body: some View {
        Text(text)
            .font(.system(size: size * 0.34, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LumenTheme.ink, in: Circle())
    }
}

struct PostPhotoView: View {
    let post: PhotoPost

    var body: some View {
        Group {
            if let data = post.imageData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let imageURL = post.imageURL {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else if phase.error != nil {
                        SeedArtworkView(artwork: post.seedArtwork ?? .bund)
                    } else {
                        ZStack {
                            LumenTheme.surface
                            ProgressView()
                        }
                    }
                }
            } else {
                SeedArtworkView(artwork: post.seedArtwork ?? .bund)
            }
        }
        .clipped()
    }
}

struct SeedArtworkView: View {
    let artwork: SeedArtwork

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                background
                artworkLayer(size: proxy.size)
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            }
        }
    }

    @ViewBuilder private var background: some View {
        switch artwork {
        case .bund:
            LinearGradient(colors: [Color(red: 0.20, green: 0.27, blue: 0.37), Color(red: 0.62, green: 0.45, blue: 0.42), Color(red: 0.09, green: 0.11, blue: 0.13)], startPoint: .top, endPoint: .bottom)
        case .lake:
            LinearGradient(colors: [Color(red: 0.72, green: 0.77, blue: 0.74), Color(red: 0.84, green: 0.81, blue: 0.73), Color(red: 0.42, green: 0.49, blue: 0.44)], startPoint: .top, endPoint: .bottom)
        case .street:
            LinearGradient(colors: [Color(red: 0.19, green: 0.21, blue: 0.23), Color(red: 0.06, green: 0.08, blue: 0.09)], startPoint: .top, endPoint: .bottom)
        }
    }

    @ViewBuilder private func artworkLayer(size: CGSize) -> some View {
        switch artwork {
        case .bund:
            ZStack(alignment: .bottom) {
                Circle().fill(Color(red: 0.95, green: 0.88, blue: 0.74)).frame(width: size.width * 0.15).offset(x: size.width * 0.25, y: -size.height * 0.60)
                HStack(alignment: .bottom, spacing: size.width * 0.015) {
                    ForEach([0.28, 0.42, 0.34, 0.60, 0.38, 0.70, 0.48, 0.32], id: \.self) { height in
                        Rectangle().fill(Color.black.opacity(0.70)).frame(height: size.height * height)
                    }
                }.padding(.horizontal, -8)
            }
        case .lake:
            ZStack(alignment: .bottom) {
                Circle().fill(Color.white.opacity(0.38)).frame(width: size.width * 0.25).offset(x: -size.width * 0.22, y: -size.height * 0.58)
                Ellipse().fill(Color(red: 0.34, green: 0.42, blue: 0.36).opacity(0.75)).frame(width: size.width * 1.3, height: size.height * 0.44).offset(y: size.height * 0.12)
                Rectangle().fill(Color.white.opacity(0.18)).frame(height: 2).offset(y: -size.height * 0.16)
            }
        case .street:
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.26, y: size.height))
                    path.addLine(to: CGPoint(x: size.width * 0.46, y: size.height * 0.42))
                    path.addLine(to: CGPoint(x: size.width * 0.62, y: size.height * 0.42))
                    path.addLine(to: CGPoint(x: size.width * 0.86, y: size.height))
                }.fill(Color(red: 0.23, green: 0.27, blue: 0.29))
                ForEach([0.32, 0.50, 0.68], id: \.self) { x in
                    Capsule().fill(Color(red: 0.87, green: 0.61, blue: 0.40).opacity(0.7)).frame(width: 5, height: size.height * 0.42).rotationEffect(.degrees(x < 0.5 ? 8 : -8)).position(x: size.width * x, y: size.height * 0.76)
                }
            }
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

struct LumenWordmark: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("光迹").font(.headline).tracking(2)
            Text("LUMEN FIELD NOTES").font(.system(size: 8, weight: .medium)).tracking(1.3).foregroundStyle(.secondary)
        }
    }
}
