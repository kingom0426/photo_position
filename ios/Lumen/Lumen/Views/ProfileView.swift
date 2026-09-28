import SwiftUI
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedAvatar: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var avatarError: String?
    @State private var showingNicknameEditor = false
    @State private var showingBioEditor = false
    @State private var showingPasswordEditor = false
    @State private var showingLogoutConfirmation = false
    @State private var selectedContent = 0

    var body: some View {
        let avatar = store.currentUser.avatar
        NavigationStack {
            Group {
                if store.isAuthenticated {
                    ScrollView {
                        VStack(spacing: 12) {
                            profileCard(avatar: avatar)
                            contentTabs

                            if displayedPosts.isEmpty {
                                ContentUnavailableView(
                                    selectedContent == 0 ? "还没有发布作品" : "还没有提交作业",
                                    systemImage: selectedContent == 0 ? "camera" : "rectangle.split.2x1",
                                    description: Text(selectedContent == 0 ? "分享拍摄参数和你的创作经验" : "从喜欢的作品开始一次复刻练习")
                                )
                                .frame(minHeight: 280)
                                .background(LumenTheme.surface)
                            } else {
                                LazyVGrid(
                                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                                    spacing: 8
                                ) {
                                    ForEach(displayedPosts) { post in
                                        NavigationLink {
                                            if post.kind == .original {
                                                PostDetailView(postID: post.id)
                                            } else {
                                                AssignmentCompareView(assignmentID: post.id)
                                            }
                                        } label: {
                                            Color.clear
                                                .aspectRatio(1, contentMode: .fit)
                                                .overlay {
                                                    PostPhotoView(post: post)
                                                        .id(post.imageURL?.absoluteString ?? post.id.uuidString)
                                                }
                                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.bottom, 20)
                            }
                        }
                        .simultaneousGesture(contentSwipeGesture)
                    }
                    .background(LumenTheme.canvas)
                } else {
                    GuestGateView(
                        title: "登录后查看个人主页",
                        description: "游客可以浏览公开作品；发布、评论和拍摄计划需要登录。"
                    )
                }
            }
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                }
            }
            .sheet(isPresented: $showingNicknameEditor) {
                NicknameEditorView(currentNickname: store.currentUser.name)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showingBioEditor) {
                BioEditorView(currentBio: store.currentUser.bio)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showingPasswordEditor) {
                PasswordChangeView().environmentObject(store)
            }
            .onChange(of: selectedAvatar) { _, item in
                guard let item else { return }
                Task { await uploadAvatar(item) }
            }
            .alert("头像上传失败", isPresented: Binding(
                get: { avatarError != nil },
                set: { if !$0 { avatarError = nil } }
            )) {
                Button("好") { avatarError = nil }
            } message: {
                Text(avatarError ?? "未知错误")
            }
            .onAppear {
                guard store.isAuthenticated else { return }
                Task { await store.sync() }
            }
        }
    }

    private func profileCard(avatar: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                PhotosPicker(selection: $selectedAvatar, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        CurrentUserAvatarView(avatar: avatar, size: 76)
                            .id(avatar)
                            .overlay(Circle().stroke(.white, lineWidth: 3))
                            .shadow(color: .black.opacity(0.1), radius: 7, y: 3)
                        Group {
                            if isUploadingAvatar {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "camera.fill")
                            }
                        }
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(LumenTheme.ink, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
                .buttonStyle(.plain)
                .disabled(isUploadingAvatar)

                VStack(alignment: .leading, spacing: 7) {
                    Button {
                        showingNicknameEditor = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(store.currentUser.name)
                                .font(.title3.weight(.semibold))
                            Image(systemName: "pencil")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(LumenTheme.ink)
                    }
                    .buttonStyle(.plain)

                    Text(store.currentUser.city.isEmpty ? "城市未填写" : store.currentUser.city)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("点击头像更换照片")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 8)

                Button {
                    showingLogoutConfirmation = true
                } label: {
                    Label("退出", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Color(.systemGray6), in: Capsule())
                }
                .buttonStyle(.plain)
                .confirmationDialog("确定退出登录？", isPresented: $showingLogoutConfirmation, titleVisibility: .visible) {
                    Button("退出登录", role: .destructive) { store.logout() }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("退出后需要重新登录才能发布作品、提交作业和同步关注内容。")
                }
            }

            Button {
                showingPasswordEditor = true
            } label: {
                Label("修改密码", systemImage: "lock.rotation")
                    .font(.subheadline)
                    .foregroundStyle(LumenTheme.ink)
            }
            .buttonStyle(.plain)

            Divider()

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("自我介绍")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        showingBioEditor = true
                    } label: {
                        Label(store.currentUser.bio.isEmpty ? "添加" : "编辑", systemImage: "square.and.pencil")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Text(store.currentUser.bio.isEmpty ? "介绍一下自己，让大家更了解你。" : store.currentUser.bio)
                    .font(.subheadline)
                    .foregroundStyle(store.currentUser.bio.isEmpty ? Color.secondary : LumenTheme.ink)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .background(LumenTheme.surface)
    }

    private var contentTabs: some View {
        HStack(spacing: 0) {
            contentTab(title: "作品", count: originalPosts.count, index: 0)
            contentTab(title: "作业", count: assignmentPosts.count, index: 1)
        }
        .frame(height: 54)
        .background(LumenTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.black.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    private func contentTab(title: String, count: Int, index: Int) -> some View {
        Button {
            selectContent(index)
        } label: {
            Text("\(title) \(count)")
                .font(.system(size: 16, weight: selectedContent == index ? .semibold : .regular))
                .foregroundStyle(selectedContent == index ? LumenTheme.ink : Color.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(LumenTheme.ink)
                        .frame(width: 24, height: 3)
                        .opacity(selectedContent == index ? 1 : 0)
                        .padding(.bottom, 2)
                }
        }
        .buttonStyle(.plain)
    }

    private var contentSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height),
                      abs(value.translation.width) > 50 else {
                    return
                }
                selectContent(value.translation.width < 0 ? 1 : 0)
            }
    }

    private func selectContent(_ index: Int) {
        guard index != selectedContent else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedContent = index
        }
    }

    private func uploadAvatar(_ item: PhotosPickerItem) async {
        isUploadingAvatar = true
        defer {
            isUploadingAvatar = false
            selectedAvatar = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw APIError.server("无法读取所选照片")
            }
            try await store.updateAvatar(imageData: data)
        } catch {
            avatarError = error.localizedDescription
        }
    }

    private var originalPosts: [PhotoPost] {
        store.currentUserPosts.filter { $0.kind == .original }
    }

    private var assignmentPosts: [PhotoPost] {
        store.currentUserPosts.filter { $0.kind == .assignment }
    }

    private var displayedPosts: [PhotoPost] {
        selectedContent == 0 ? originalPosts : assignmentPosts
    }
}

private struct AppearanceSettingsView: View {
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue

    var body: some View {
        Form {
            Section {
                Picker("背景模式", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("外观")
            } footer: {
                Text("选择“跟随手机系统”后，Lumen 会随手机的深色或浅色外观自动切换。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(LumenTheme.canvas)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NicknameEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var nickname: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(currentNickname: String) {
        _nickname = State(initialValue: currentNickname)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("昵称", text: $nickname)
                        .textContentType(.nickname)
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("昵称不可与其他用户重复")
                }
            }
            .navigationTitle("修改昵称")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "保存中…" : "保存") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .alert("修改失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
        .presentationDetents([.height(260)])
    }

    private var canSave: Bool {
        let value = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && value.count <= 80 && value != store.currentUser.name
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.updateNickname(
                nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct BioEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var bio: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(currentBio: String) {
        _bio = State(initialValue: currentBio)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .trailing, spacing: 8) {
                TextEditor(text: $bio)
                    .font(.body)
                    .padding(10)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topLeading) {
                        if bio.isEmpty {
                            Text("介绍一下你的摄影偏好、常拍题材或所在城市…")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }
                Text("\(bio.count)/300")
                    .font(.caption)
                    .foregroundStyle(bio.count > 300 ? Color.red : Color.secondary)
            }
            .padding(16)
            .navigationTitle("编辑自我介绍")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "保存中…" : "保存") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
        .presentationDetents([.medium])
    }

    private var canSave: Bool {
        bio.count <= 300 && bio.trimmingCharacters(in: .whitespacesAndNewlines) != store.currentUser.bio
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.updateBio(
                bio.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct GuestGateView: View {
    @EnvironmentObject private var store: AppStore
    var title = "登录后使用此功能"
    var description = "游客可以浏览公开内容，互动操作需要登录。"

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text(description)
        } actions: {
            Button("登录或注册") { store.showingAuthentication = true }
                .buttonStyle(.borderedProminent)
                .tint(Color(.systemGray))
        }
    }
}

struct AuthView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    @State private var email = ""
    @State private var verificationCode = ""
    @State private var isSendingCode = false
    @State private var resendAfter = Date.distantPast
    @State private var notice: String?
    @State private var showingForgotPassword = false
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var nickname = ""
    @State private var consent: ConsentDocument?
    @State private var consentAccepted = false
    @State private var showingConsent = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("账号操作", selection: $mode) {
                        Text("登录").tag(0)
                        Text("注册").tag(1)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextField("邮箱地址", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)
                        .keyboardType(.default)
                        .onChange(of: email) { _, value in
                            email = String(value.lowercased().prefix(254))
                            verificationCode = ""
                            notice = nil
                        }
                    TextField("密码（至少 8 位）", text: $password)
                        .textContentType(nil)
                        .keyboardType(.default)
                        .textInputAutocapitalization(.never)
                    if mode == 1 {
                        TextField("确认密码", text: $confirmPassword)
                            .textContentType(nil)
                            .keyboardType(.default)
                            .textInputAutocapitalization(.never)
                        TextField("昵称（可选，默认随机生成）", text: $nickname)
                            .textContentType(.nickname)
                    }
                } header: {
                    Text(mode == 0 ? "登录账号" : "创建账号")
                } footer: {
                    if mode == 0 { Text("使用注册邮箱登录。忘记密码可通过邮件重置。") }
                }

                if mode == 1 {
                    Section {
                        EmailVerificationCodeInput(code: $verificationCode)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let remaining = max(0, Int(ceil(resendAfter.timeIntervalSince(context.date))))
                            Button(isSendingCode ? "正在发送…" : (remaining > 0 ? "\(remaining) 秒后可重发" : "发送邮箱验证码")) {
                                Task { await sendCode() }
                            }
                            .disabled(!validEmail || isSendingCode || remaining > 0 || isSubmitting)
                        }
                    } header: {
                        Text("邮箱验证码")
                    } footer: {
                        Text("请输入最新邮件中的 6 位数字，10 分钟内有效。支持粘贴或自动填充。")
                    }
                }

                if mode == 1 {
                    Section {
                        HStack(alignment: .top, spacing: 10) {
                            Button {
                                consentAccepted.toggle()
                            } label: {
                                Image(systemName: consentAccepted
                                      ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(consentAccepted ? LumenTheme.ink : .secondary)
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)

                            HStack(spacing: 0) {
                                Text("我已阅读并同意")
                                    .foregroundStyle(.secondary)
                                Button(consent?.title ?? "《用户知情同意书》") {
                                    showingConsent = true
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(LumenTheme.ink)
                            }
                            .font(.footnote)
                        }
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        Group {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            } else {
                                Text(mode == 0 ? "登录" : "注册并登录")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(canSubmit || isSubmitting ? Color.white : Color(.secondaryLabel))
                        .background(canSubmit || isSubmitting ? LumenTheme.ink : Color(.systemGray5), in: Capsule())
                    }
                    .disabled(!canSubmit || isSubmitting)
                    .buttonStyle(.plain)
                }
                if let notice {
                    Section { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                }
                if mode == 0 {
                    Section {
                        Button("忘记密码？") { showingForgotPassword = true }
                    }
                }
            }
            .disabled(isSubmitting)
            .onChange(of: mode) { _, _ in notice = nil }
            .navigationTitle(mode == 0 ? "登录" : "注册")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
            .alert("操作失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
            .sheet(isPresented: $showingConsent) {
                ConsentDocumentView(document: consent)
            }
            .sheet(isPresented: $showingForgotPassword) {
                ForgotPasswordView(initialEmail: email).environmentObject(store)
            }
            .task {
                await loadConsent()
            }
        }
    }

    private var canSubmit: Bool {
        guard validEmail && password.count >= 8 && password.count <= 128 else { return false }
        if mode == 0 { return true }
        return password == confirmPassword && consentAccepted && consent != nil && verificationCode.count == 6 && !isSendingCode
    }

    private var validEmail: Bool { isValidAuthEmail(email) }

    private func sendCode() async {
        isSendingCode = true
        defer { isSendingCode = false }
        let requestedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let message = try await store.sendRegistrationCode(email: requestedEmail)
            resendAfter = Date().addingTimeInterval(60)
            guard requestedEmail == email.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            verificationCode = ""
            notice = message
        } catch { errorMessage = error.localizedDescription }
    }

    private func loadConsent() async {
        do {
            consent = try await store.fetchUserConsent()
        } catch {
            errorMessage = "暂时无法加载用户知情同意书，请检查网络后重试。"
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            if mode == 0 {
                try await store.login(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            } else {
                guard let consent else { return }
                try await store.register(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password,
                    nickname: nickname,
                    consentAccepted: consentAccepted,
                    consentVersion: consent.version,
                    verificationCode: verificationCode
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct EmailVerificationCodeInput: View {
    @Binding var code: String
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            // One real field preserves paste, backspace and iOS one-time-code autofill.
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .accessibilityLabel("6 位邮箱验证码")
                .accessibilityIdentifier("registrationVerificationCode")
                .onChange(of: code) { _, value in
                    let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6))
                    if code != digits { code = digits }
                }
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    let digits = Array(code)
                    let active = isFocused && index == min(digits.count, 5)
                    Text(index < digits.count ? String(digits[index]) : "")
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(active ? Color.primary : Color(.separator), lineWidth: active ? 2 : 1))
                }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
        .frame(height: 50)
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }
}

private func isValidAuthEmail(_ email: String) -> Bool {
    let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.count <= 254 && value.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) != nil
}

private struct ForgotPasswordView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var email: String
    @State private var isSending = false
    @State private var resendAfter = Date.distantPast
    @State private var message: String?

    init(initialEmail: String) { _email = State(initialValue: initialEmail) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("注册邮箱", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("我们会向该账号的邮箱发送一次性重置链接。请在 30 分钟内打开邮件设置新密码，再返回 Lumen 登录。")
                }
                Section {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = max(0, Int(ceil(resendAfter.timeIntervalSince(context.date))))
                        Button(isSending ? "正在发送…" : (remaining > 0 ? "\(remaining) 秒后可重发" : "发送重置邮件")) {
                            Task { await send() }
                        }
                        .disabled(!isValidAuthEmail(email) || isSending || remaining > 0)
                    }
                }
                if let message { Section { Text(message).font(.footnote) } }
                Section {
                    Text("没收到邮件？请检查垃圾邮件、邮箱拼写，或稍后重试。未绑定邮箱的旧账号需要联系管理员核验处理。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .disabled(isSending)
            .navigationTitle("找回密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            message = try await store.forgotPassword(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
            resendAfter = Date().addingTimeInterval(60)
        } catch { message = error.localizedDescription }
    }
}

private struct PasswordChangeView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var isSubmitting = false
    @State private var message: String?
    @State private var succeeded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("原密码", text: $oldPassword).textContentType(.password)
                    SecureField("新密码（8–128 位）", text: $newPassword).textContentType(.newPassword)
                    SecureField("确认新密码", text: $confirmation).textContentType(.newPassword)
                } footer: {
                    Text("修改成功后，所有设备都会退出登录。请使用邮箱和新密码重新登录。")
                }
                Section {
                    Button(isSubmitting ? "正在修改…" : "确认修改") { Task { await submit() } }
                        .disabled(isSubmitting || oldPassword.isEmpty || newPassword.count < 8
                                  || newPassword.count > 128 || newPassword != confirmation)
                }
            }
            .disabled(isSubmitting)
            .navigationTitle("修改密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("取消") { dismiss() } } }
            .alert(succeeded ? "修改成功" : "修改失败", isPresented: Binding(
                get: { message != nil }, set: { if !$0 { message = nil } }
            )) {
                Button("好") { if succeeded { dismiss() } }
            } message: { Text(message ?? "") }
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await store.changePassword(oldPassword: oldPassword, newPassword: newPassword)
            oldPassword = ""
            newPassword = ""
            confirmation = ""
            succeeded = true
            message = "密码已修改，请使用邮箱和新密码重新登录。"
        } catch { message = error.localizedDescription }
    }
}

private struct ConsentDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    let document: ConsentDocument?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let document {
                    Text(attributedContent(document.content))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                } else {
                    ContentUnavailableView(
                        "协议加载失败",
                        systemImage: "doc.text",
                        description: Text("请返回后重试")
                    )
                }
            }
            .navigationTitle(document?.title ?? "用户知情同意书")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func attributedContent(_ markdown: String) -> AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .full)
        )) ?? AttributedString(markdown)
    }
}
