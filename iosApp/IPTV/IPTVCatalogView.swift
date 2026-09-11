import SwiftUI
import UniformTypeIdentifiers

public struct IPTVCatalogView: View {
    @StateObject private var store = IPTVPlaylistStore.shared

    @State private var searchText: String = ""
    @State private var selectedCategory: String = "ALL"
    @State private var selectedChannelForPlayback: IPTVChannel? = nil
    @State private var showPlaylistManager: Bool = false
    @State private var showAddPlaylistSheet: Bool = false
    @State private var showStorageCleaner: Bool = false

    // File Importer State
    @State private var showFileImporter: Bool = false

    // Edit Playlist State
    @State private var playlistToEdit: IPTVPlaylist? = nil
    @State private var editPlaylistName: String = ""
    @State private var showEditAlert: Bool = false

    // Delete confirmation
    @State private var playlistToDelete: IPTVPlaylist? = nil
    @State private var showDeleteConfirm: Bool = false

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 14)
    ]

    public init() {}

    public var body: some View {
        ZStack {
            Color(red: 0.051, green: 0.051, blue: 0.051)
                .ignoresSafeArea()

            if store.playlists.isEmpty {
                // Màn hình chào mừng khi chưa thêm playlist nào
                welcomeEmptyView
            } else {
                VStack(spacing: 0) {
                    // Header Bar
                    headerView
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 10)

                    // Search Bar
                    searchBarView
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)

                    // Category Chips
                    categoryScrollView
                        .padding(.bottom, 10)

                    // Channels Grid / List
                    if store.isLoading && store.currentChannels.isEmpty {
                        Spacer()
                        ProgressView("Đang tải kênh...")
                            .tint(.cyan)
                            .foregroundStyle(.white)
                        Spacer()
                    } else if filteredChannels.isEmpty {
                        noResultView
                    } else {
                        channelsGridView
                    }
                }
            }
        }
        .fullScreenCover(item: $selectedChannelForPlayback) { channel in
            IPTVPlayerView(channel: channel, playlistChannels: filteredChannels)
        }
        .sheet(isPresented: $showPlaylistManager) {
            playlistManagerSheet
        }
        .sheet(isPresented: $showAddPlaylistSheet) {
            AddPlaylistSheetView(isPresented: $showAddPlaylistSheet, showFileImporter: $showFileImporter)
        }
        .sheet(isPresented: $showStorageCleaner) {
            StorageCleanerView()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [
                UTType(filenameExtension: "m3u") ?? .plainText,
                UTType(filenameExtension: "m3u8") ?? .plainText,
                .plainText,
                .data
            ],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    _ = await store.addLocalFilePlaylist(name: url.deletingPathExtension().lastPathComponent, sourceURL: url)
                }
            case .failure(let error):
                print("[IPTV] File pick error: \(error.localizedDescription)")
            }
        }
        .alert("Đổi Tên Danh Sách", isPresented: $showEditAlert) {
            TextField("Tên mới", text: $editPlaylistName)
            Button("Lưu") {
                if let p = playlistToEdit {
                    store.updatePlaylist(id: p.id, newName: editPlaylistName)
                }
            }
            Button("Hủy", role: .cancel) {}
        }
        .confirmationDialog(
            "Xác nhận xóa danh sách phát này?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Xóa vĩnh viễn", role: .destructive) {
                if let p = playlistToDelete {
                    store.deletePlaylist(id: p.id)
                }
            }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text(playlistToDelete?.name ?? "Danh sách")
        }
    }

    // MARK: - Filtered Channels

    private var filteredChannels: [IPTVChannel] {
        var base: [IPTVChannel]

        switch selectedCategory {
        case "ALL":
            base = store.currentChannels
        case "FAVORITES":
            base = store.favoriteChannels
        case "RECENTS":
            base = store.recentChannels
        default:
            base = store.currentChannels.filter { $0.groupTitle == selectedCategory }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return base }
        return base.filter {
            $0.name.lowercased().contains(query) || $0.groupTitle.lowercased().contains(query)
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "tv.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("IPTV Trực Tuyến")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)

                    if let active = store.activePlaylist {
                        Menu {
                            ForEach(store.playlists) { p in
                                Button {
                                    store.selectPlaylist(id: p.id)
                                    selectedCategory = "ALL"
                                } label: {
                                    HStack {
                                        Text(p.name)
                                        if p.id == active.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                            Divider()
                            Button {
                                showAddPlaylistSheet = true
                            } label: {
                                Label("Thêm nguồn mới", systemImage: "plus")
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(active.name)
                                    .font(.caption.bold())
                                    .foregroundStyle(.cyan)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.cyan)
                            }
                        }
                    }
                }
            }

            Spacer()

            // Refresh
            if let active = store.activePlaylist {
                Button {
                    Task { await store.refreshPlaylist(id: active.id) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
            }

            // Storage Cleaner
            Button {
                showStorageCleaner = true
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.cyan)
                    .frame(width: 36, height: 36)
                    .background(Color.cyan.opacity(0.12), in: Circle())
            }

            // Playlist Manager
            Button {
                showPlaylistManager = true
            } label: {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
        }
    }

    // MARK: - Search Bar

    private var searchBarView: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(.gray)

            TextField("Tìm kiếm kênh, thể loại...", text: $searchText)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.gray)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Category Scroll View

    private var categoryScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(id: "ALL", title: "Tất cả", icon: "tv", count: store.currentChannels.count)

                if !store.favoriteChannels.isEmpty {
                    categoryChip(id: "FAVORITES", title: "Yêu thích", icon: "star.fill", count: store.favoriteChannels.count, tintColor: .yellow)
                }

                if !store.recentChannels.isEmpty {
                    categoryChip(id: "RECENTS", title: "Gần đây", icon: "clock.fill", count: store.recentChannels.count)
                }

                if let active = store.activePlaylist {
                    ForEach(active.categories, id: \.self) { cat in
                        let count = store.currentChannels.filter { $0.groupTitle == cat }.count
                        categoryChip(id: cat, title: cat, icon: "folder", count: count)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func categoryChip(
        id: String,
        title: String,
        icon: String,
        count: Int,
        tintColor: Color? = nil
    ) -> some View {
        let isSelected = selectedCategory == id
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedCategory = id
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(tintColor ?? (isSelected ? .black : .white.opacity(0.7)))

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? .black : .white)

                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        isSelected ? Color.black.opacity(0.2) : Color.white.opacity(0.12),
                        in: Capsule()
                    )
                    .foregroundStyle(isSelected ? .black : .white.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isSelected ? Color.white : Color.white.opacity(0.08),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Channels Grid View

    private var channelsGridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(filteredChannels) { channel in
                    channelCard(channel)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private func channelCard(_ channel: IPTVChannel) -> some View {
        Button {
            selectedChannelForPlayback = channel
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.04))
                        .frame(height: 90)
                        .overlay {
                            if let logo = channel.logoUrl, let url = URL(string: logo) {
                                AsyncImage(url: url) { phase in
                                    if let img = phase.image {
                                        img.resizable().scaledToFit().padding(12)
                                    } else {
                                        Image(systemName: "tv.fill").font(.system(size: 28)).foregroundStyle(.gray.opacity(0.5))
                                    }
                                }
                            } else {
                                Image(systemName: "tv.fill").font(.system(size: 28)).foregroundStyle(.gray.opacity(0.5))
                            }
                        }

                    HStack(spacing: 4) {
                        if channel.isMPEG_DASH {
                            Text(channel.isClearKey ? "MPD • KEY" : "MPD")
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(.cyan)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                        }

                        Button {
                            store.toggleFavorite(channel: channel)
                        } label: {
                            Image(systemName: store.isFavorite(channel: channel) ? "star.fill" : "star")
                                .font(.system(size: 13))
                                .foregroundStyle(store.isFavorite(channel: channel) ? .yellow : .white.opacity(0.6))
                                .padding(6)
                                .background(Color.black.opacity(0.5), in: Circle())
                        }
                    }
                    .padding(6)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Circle().fill(Color.red).frame(width: 5, height: 5)
                        Text(channel.groupTitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Welcome Empty View

    private var welcomeEmptyView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "tv.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            VStack(spacing: 8) {
                Text("Chào Mừng Đến Với IPTV")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text("Hỗ trợ M3U / M3U8, File lưu trên máy, Xtream Codes và Stalker Portal.")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }

            VStack(spacing: 12) {
                Button {
                    showAddPlaylistSheet = true
                } label: {
                    Label("Thêm Nguồn Kênh (M3U / Xtream / Stalker)", systemImage: "plus.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: 320)
                        .padding(.vertical, 14)
                        .background(Color.cyan, in: RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    showFileImporter = true
                } label: {
                    Label("Nhập File M3U Từ Máy", systemImage: "doc.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: 320)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                }
            }

            Spacer()
        }
        .padding(20)
    }

    private var noResultView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.gray)
            Text("Không có kênh nào phù hợp")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Thử tìm kiếm với từ khóa khác hoặc chuyển danh mục.")
                .font(.caption)
                .foregroundStyle(.gray)
            Spacer()
        }
    }

    // MARK: - Playlist Manager Sheet (Edit + Remove)

    private var playlistManagerSheet: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.09).ignoresSafeArea()

                List {
                    Section("Danh Sách Đã Thêm") {
                        ForEach(store.playlists) { playlist in
                            HStack(spacing: 12) {
                                Image(systemName: playlist.type.iconName)
                                    .font(.system(size: 18))
                                    .foregroundStyle(.cyan)
                                    .frame(width: 32, height: 32)
                                    .background(Color.cyan.opacity(0.12), in: Circle())

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(playlist.name)
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                        if playlist.id == store.activePlaylistId {
                                            Text("Đang chọn")
                                                .font(.system(size: 10, weight: .bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.cyan.opacity(0.2), in: Capsule())
                                                .foregroundStyle(.cyan)
                                        }
                                    }

                                    Text("\(playlist.channelCount) kênh • \(playlist.type.rawValue)")
                                        .font(.caption)
                                        .foregroundStyle(.gray)
                                }

                                Spacer()

                                // Edit Button
                                Button {
                                    playlistToEdit = playlist
                                    editPlaylistName = playlist.name
                                    showEditAlert = true
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .padding(8)
                                        .background(Color.white.opacity(0.08), in: Circle())
                                }
                                .buttonStyle(.plain)

                                // Delete Button
                                Button {
                                    playlistToDelete = playlist
                                    showDeleteConfirm = true
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.red)
                                        .padding(8)
                                        .background(Color.red.opacity(0.12), in: Circle())
                                }
                                .buttonStyle(.plain)

                                // Select Button
                                if playlist.id != store.activePlaylistId {
                                    Button("Chọn") {
                                        store.selectPlaylist(id: playlist.id)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.blue)
                                    .controlSize(.small)
                                }
                            }
                            .listRowBackground(Color.white.opacity(0.05))
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Quản Lý Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { showPlaylistManager = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showPlaylistManager = false
                        showAddPlaylistSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

// MARK: - Add Playlist Sheet with 4 Tabs

struct AddPlaylistSheetView: View {
    @Binding var isPresented: Bool
    @Binding var showFileImporter: Bool

    @ObservedObject var store = IPTVPlaylistStore.shared
    @State private var selectedTab: IPTVPlaylistType = .m3u

    // Form inputs
    @State private var name: String = ""
    @State private var m3uUrl: String = ""
    @State private var xtreamServer: String = ""
    @State private var xtreamUser: String = ""
    @State private var xtreamPass: String = ""
    @State private var stalkerUrl: String = ""
    @State private var stalkerMac: String = ""

    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.09).ignoresSafeArea()

                VStack(spacing: 16) {
                    // Type Picker
                    Picker("Loại", selection: $selectedTab) {
                        Text("Link M3U").tag(IPTVPlaylistType.m3u)
                        Text("File Local").tag(IPTVPlaylistType.localFile)
                        Text("Xtream").tag(IPTVPlaylistType.xtream)
                        Text("Stalker").tag(IPTVPlaylistType.stalker)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 12)

                    ScrollView {
                        VStack(spacing: 16) {
                            // Common Name Field
                            fieldContainer(title: "Tên danh sách (Tùy chọn)") {
                                TextField("Ví dụ: Kênh Thể Thao, Kênh Phim...", text: $name)
                                    .padding(12)
                                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                    .foregroundStyle(.white)
                            }

                            // Dynamic Fields Based on Type
                            switch selectedTab {
                            case .m3u:
                                fieldContainer(title: "Đường dẫn M3U / M3U8 Playlist URL") {
                                    TextField("https://example.com/playlist.m3u", text: $m3uUrl)
                                        .keyboardType(.URL)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .padding(12)
                                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                        .foregroundStyle(.white)
                                }

                            case .localFile:
                                VStack(spacing: 12) {
                                    Text("Chọn file .m3u hoặc .m3u8 đã tải về máy từ ứng dụng Tệp (Files)")
                                        .font(.caption)
                                        .foregroundStyle(.gray)
                                        .multilineTextAlignment(.center)

                                    Button {
                                        isPresented = false
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            showFileImporter = true
                                        }
                                    } label: {
                                        Label("Chọn File Từ Thiết Bị", systemImage: "folder.fill")
                                            .font(.headline)
                                            .foregroundStyle(.black)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .background(Color.cyan, in: RoundedRectangle(cornerRadius: 12))
                                    }
                                }
                                .padding(.top, 10)

                            case .xtream:
                                VStack(spacing: 14) {
                                    fieldContainer(title: "Máy chủ Server URL") {
                                        TextField("http://domain.com:8080", text: $xtreamServer)
                                            .keyboardType(.URL)
                                            .textInputAutocapitalization(.never)
                                            .padding(12)
                                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                            .foregroundStyle(.white)
                                    }

                                    fieldContainer(title: "Tên đăng nhập (Username)") {
                                        TextField("username", text: $xtreamUser)
                                            .textInputAutocapitalization(.never)
                                            .padding(12)
                                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                            .foregroundStyle(.white)
                                    }

                                    fieldContainer(title: "Mật khẩu (Password)") {
                                        SecureField("password", text: $xtreamPass)
                                            .padding(12)
                                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                            .foregroundStyle(.white)
                                    }
                                }

                            case .stalker:
                                VStack(spacing: 14) {
                                    fieldContainer(title: "Portal URL") {
                                        TextField("http://mag.example.com/c/", text: $stalkerUrl)
                                            .keyboardType(.URL)
                                            .textInputAutocapitalization(.never)
                                            .padding(12)
                                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                            .foregroundStyle(.white)
                                    }

                                    fieldContainer(title: "Địa chỉ MAC") {
                                        TextField("00:1A:79:XX:XX:XX", text: $stalkerMac)
                                            .textInputAutocapitalization(.characters)
                                            .padding(12)
                                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                            .foregroundStyle(.white)
                                    }
                                }
                            }

                            if let error = errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.center)
                            }

                            if selectedTab != .localFile {
                                Button {
                                    submit()
                                } label: {
                                    HStack {
                                        if isSubmitting {
                                            ProgressView().tint(.black).padding(.trailing, 4)
                                        }
                                        Text(isSubmitting ? "Đang kết nối & nạp kênh..." : "Lưu & Tải Danh Sách")
                                            .font(.headline)
                                    }
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(isFormValid ? Color.cyan : Color.gray, in: RoundedRectangle(cornerRadius: 12))
                                }
                                .disabled(!isFormValid || isSubmitting)
                                .padding(.top, 10)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Thêm Nguồn Kênh")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { isPresented = false }
                }
            }
        }
    }

    private var isFormValid: Bool {
        switch selectedTab {
        case .m3u:
            return !m3uUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .xtream:
            return !xtreamServer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                   !xtreamUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .stalker:
            return !stalkerUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                   !stalkerMac.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .localFile:
            return true
        }
    }

    private func fieldContainer<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.gray)
            content()
        }
    }

    private func submit() {
        Task {
            isSubmitting = true
            errorMessage = nil
            var ok = false

            switch selectedTab {
            case .m3u:
                ok = await store.addM3UPlaylist(name: name, url: m3uUrl)
            case .xtream:
                ok = await store.addXtreamPlaylist(name: name, server: xtreamServer, user: xtreamUser, pass: xtreamPass)
            case .stalker:
                ok = await store.addStalkerPlaylist(name: name, portalUrl: stalkerUrl, mac: stalkerMac)
            case .localFile:
                break
            }

            isSubmitting = false
            if ok {
                isPresented = false
            } else {
                errorMessage = store.errorMessage ?? "Không thể kết nối hoặc nạp kênh."
            }
        }
    }
}
