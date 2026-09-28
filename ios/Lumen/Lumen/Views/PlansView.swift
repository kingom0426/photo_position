import SwiftUI

struct PlansView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection = 0

    private var plannedPosts: [PhotoPost] {
        store.originals.filter { store.plannedPostIDs.contains($0.id) }
    }

    private var submittedAssignments: [PhotoPost] {
        store.currentUserPosts.filter { $0.kind == .assignment }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !store.isAuthenticated {
                    GuestGateView(
                        title: "登录后使用拍摄计划",
                        description: "登录后可以收藏机位、加入计划并提交复刻作业。"
                    )
                } else {
                    VStack(spacing: 0) {
                        HStack(spacing: 32) {
                            planTab(title: "待拍摄 \(plannedPosts.count)", index: 0)
                            planTab(title: "已交作业 \(submittedAssignments.count)", index: 1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(LumenTheme.surface)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(.black.opacity(0.06))
                                .frame(height: 0.5)
                        }

                        if selection == 0 && plannedPosts.isEmpty {
                            ContentUnavailableView(
                                "还没有拍摄计划",
                                systemImage: "bookmark",
                                description: Text("从作品详情加入一个想复刻的作品")
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if selection == 1 && submittedAssignments.isEmpty {
                            ContentUnavailableView(
                                "还没有提交作业",
                                systemImage: "camera",
                                description: Text("完成拍摄后，作业会显示在这里")
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 10) {
                                    ForEach(selection == 0 ? plannedPosts : submittedAssignments) { post in
                                        planCard(post)
                                    }
                                }
                                .padding(12)
                                .padding(.bottom, 16)
                            }
                            .background(LumenTheme.canvas)
                        }
                    }
                    .simultaneousGesture(planSwipeGesture)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func planTab(title: String, index: Int) -> some View {
        Button {
            selectPlanTab(index)
        } label: {
            Text(title)
                .font(.system(size: 17, weight: selection == index ? .semibold : .regular))
                .foregroundStyle(selection == index ? LumenTheme.ink : Color.secondary)
                .frame(height: 48)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(LumenTheme.ink)
                        .frame(width: 24, height: 3)
                        .opacity(selection == index ? 1 : 0)
                        .padding(.bottom, 2)
                }
        }
        .buttonStyle(.plain)
    }

    private func planCard(_ post: PhotoPost) -> some View {
        VStack(spacing: 0) {
            NavigationLink {
                if selection == 0 {
                    PostDetailView(postID: post.id)
                } else {
                    AssignmentCompareView(assignmentID: post.id)
                }
            } label: {
                HStack(spacing: 13) {
                    PostPhotoView(post: post)
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 7) {
                        Text(post.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(LumenTheme.ink)
                            .lineLimit(2)
                        Label(planLocation(for: post), systemImage: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if !post.location.advice.isEmpty {
                            Text(post.location.advice)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.leading, 113)

            HStack {
                Spacer()
                if selection == 0 {
                    NavigationLink(destination: PublishView(original: post)) {
                        Label("交作业", systemImage: "camera")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(LumenTheme.ink)
                } else {
                    NavigationLink(destination: AssignmentCompareView(assignmentID: post.id)) {
                        Label("查看作业", systemImage: "rectangle.split.2x1")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(LumenTheme.ink)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .background(LumenTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.black.opacity(0.05), lineWidth: 0.5)
        }
    }

    private var planSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height),
                      abs(value.translation.width) > 50 else {
                    return
                }
                selectPlanTab(value.translation.width < 0 ? 1 : 0)
            }
    }

    private func selectPlanTab(_ index: Int) {
        guard index != selection else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selection = index
        }
    }

    private func planLocation(for post: PhotoPost) -> String {
        let candidates = [post.location.displayAddress, post.location.city]
        if let location = candidates.first(where: {
            let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !value.isEmpty && !value.contains("未公开")
        }) {
            return location.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "默认拍摄点"
    }
}
