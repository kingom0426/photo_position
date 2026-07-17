import SwiftUI
import MapKit

struct MapScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedPostID: UUID?
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737), span: MKCoordinateSpan(latitudeDelta: 0.14, longitudeDelta: 0.14))
    )

    private var mappedPosts: [PhotoPost] {
        store.originals.filter { $0.location.privacy != .hidden && $0.location.coordinate != nil }
    }

    private var selectedPost: PhotoPost? {
        selectedPostID.flatMap { store.post(id: $0) } ?? mappedPosts.first
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $camera) {
                    ForEach(mappedPosts) { post in
                        if let coordinate = post.location.coordinate {
                            Annotation(post.location.name, coordinate: coordinate) {
                                Button {
                                    selectedPostID = post.id
                                    withAnimation { camera = .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))) }
                                } label: {
                                    VStack(spacing: 2) {
                                        Image(systemName: "camera.fill").font(.caption)
                                        Text("\(store.assignments(for: post.id).count + 1)").font(.caption2.weight(.bold))
                                    }
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 48)
                                    .background(LumenTheme.ink, in: Circle())
                                    .overlay(Circle().stroke(.white, lineWidth: 3))
                                    .shadow(radius: 7, y: 4)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))

                if let selectedPost {
                    NavigationLink(destination: PostDetailView(postID: selectedPost.id)) {
                        HStack(spacing: 12) {
                            PostPhotoView(post: selectedPost).frame(width: 74, height: 74).clipShape(RoundedRectangle(cornerRadius: 13))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedPost.location.name).font(.subheadline.weight(.semibold))
                                Text("\(selectedPost.location.city) · \(selectedPost.location.privacy.title)").font(.caption).foregroundStyle(.secondary)
                                Text(selectedPost.location.advice).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
                    }
                    .buttonStyle(.plain)
                    .padding(16)
                }
            }
            .navigationTitle("地图找机位")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { LumenWordmark() } }
        }
    }
}
