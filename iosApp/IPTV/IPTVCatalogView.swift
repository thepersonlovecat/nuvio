import SwiftUI

public struct IPTVCatalogView: View {
    @StateObject private var store = IPTVPlaylistStore.shared

    @State private var searchText: String = ""
    @State private var selectedCategory: String = "ALL"
    @State private var selectedChannelForPlayback: IPTVChannel? = nil
    @State private var showPlaylistManager: Bool = false
    @State private var showAddPlaylistSheet: Bool = false
    @State private var newPlaylistName: String = ""
    @State private var newPlaylistURL: String = ""
    @State private var isAddingPlaylist: Bool = false
    @State private var addErrorMessage: String? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 14)
    ]

    public init() {}

    public var body: some View {
        ZStack {
            // Nền tối chuẩn Nuvio
            Color(red: 0.051, green: 0.051, blue: 0.051)
                .ignoresSafeArea()

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
                    ProgressView("Đang tải danh sách kênh...")
                        .tint(.white)
                        .foregroundStyle(.white)
                    Spacer()
                } else if filteredChannels.isEmpty {
                    emptyStateView
                } else {
                    channelsGridView
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
            addPlaylistSheet
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
        if query.isEmpty {
            return base
        }
        return base.filter {
            $0.name.lowercased().contains(query) ||
            $0.groupTitle.lowercased().contains(query)
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack(spacing: 12) {
            // Logo & Title
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
                                Label("Thêm danh sách mới", systemImage: "plus")
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(active.name)
                                    .font(.caption)
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

            // Refresh Button
            if let active = store.activePlaylist {
                Button {
                    Task {
                        await store.refreshPlaylist(id: active.id)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
            }

            // Manage Playlists Button
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
                // Tất cả
                categoryChip(
                    id: "ALL",
                    title: "Tất cả",
                    icon: "tv",
                    count: store.currentChannels.count
                )

                // Yêu thích
                if !store.favoriteChannels.isEmpty {
                    categoryChip(
                        id: "FAVORITES",
                        title: "Yêu thích",
                        icon: "star.fill",
                        count: store.favoriteChannels.count,
                        tintColor: .yellow
                    )
                }

                // Gần đây
                if !store.recentChannels.isEmpty {
                    categoryChip(
                        id: "RECENTS",
                        title: "Gần đây",
                        icon: "clock.fill",
                        count: store.recentChannels.count
                    )
                }

                // Danh mục từ playlist
                if let active = store.activePlaylist {
                    ForEach(active.categories, id: \.self) { cat in
                        let count = store.currentChannels.filter { $0.groupTitle == cat }.count
                        categoryChip(
                            id: cat,
                            title: cat,
                            icon: "folder",
                            count: count
                        )
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
                // Logo & Badges Area
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.04))
                        .frame(height: 90)
                        .overlay {
                            if let logo = channel.logoUrl, let url = URL(string: logo) {
                                AsyncImage(url: url) { phase in
                                    if let img = phase.image {
                                        img.resizable()
                                            .scaledToFit()
                                            .padding(12)
                                    } else {
                                        Image(systemName: "tv")
                                            .font(.system(size: 30))
                                            .foregroundStyle(.gray.opacity(0.6))
                                    }
                                }
                            } else {
                                Image(systemName: "tv")
                                    .font(.system(size: 30))
                                    .foregroundStyle(.gray.opacity(0.6))
                            }
                        }

                    // Top Badges
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

                // Channel Name & Category
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 5, height: 5)
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

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tv.slash")
                .font(.system(size: 48))
                .foregroundStyle(.gray.opacity(0.5))

            Text("Không tìm thấy kênh nào")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Thử thay đổi bộ lọc hoặc thêm danh sách phát M3U mới.")
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            Button {
                showAddPlaylistSheet = true
            } label: {
                Label("Thêm Danh Sách M3U", systemImage: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.cyan, in: Capsule())
            }
            Spacer()
        }
    }

    // MARK: - Playlist Manager Sheet

    private var playlistManagerSheet: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.09).ignoresSafeArea()

                List {
                    Section("Danh Sách Đang Có") {
                        ForEach(store.playlists) { playlist in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(playlist.name)
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                        if playlist.id == store.activePlaylistId {
                                            Text("Đang chọn")
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.cyan.opacity(0.2), in: Capsule())
                                                .foregroundStyle(.cyan)
                                        }
                                    }

                                    Text("\(playlist.channelCount) kênh • \(playlist.categories.count) danh mục")
                                        .font(.caption)
                                        .foregroundStyle(.gray)
                                }

                                Spacer()

                                if playlist.id != store.activePlaylistId {
                                    Button("Chọn") {
                                        store.selectPlaylist(id: playlist.id)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.blue)
                                }
                            }
                            .listRowBackground(Color.white.opacity(0.05))
                            .swipeActions(edge: .trailing) {
                                if !playlist.isBuiltIn {
                                    Button(role: .destructive) {
                                        store.deletePlaylist(id: playlist.id)
                                    } label: {
                                        Label("Xoá", systemImage: "trash")
                                    }
                                }
                            }
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

    // MARK: - Add Playlist Sheet

    private var addPlaylistSheet: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.09).ignoresSafeArea()

                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tên danh sách (Tùy chọn)")
                            .font(.caption.bold())
                            .foregroundStyle(.gray)

                        TextField("Ví dụ: Kênh Việt Nam, Kênh Thể Thao...", text: $newPlaylistName)
                            .padding(12)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Đường dẫn M3U / M3U8 Playlist URL")
                            .font(.caption.bold())
                            .foregroundStyle(.gray)

                        TextField("https://example.com/playlist.m3u", text: $newPlaylistURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.white)
                    }

                    if let error = addErrorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        Task {
                            isAddingPlaylist = true
                            addErrorMessage = nil
                            let success = await store.addPlaylist(name: newPlaylistName, url: newPlaylistURL)
                            isAddingPlaylist = false
                            if success {
                                newPlaylistName = ""
                                newPlaylistURL = ""
                                showAddPlaylistSheet = false
                            } else {
                                addErrorMessage = store.errorMessage ?? "Không thể tải danh sách phát."
                            }
                        }
                    } label: {
                        HStack {
                            if isAddingPlaylist {
                                ProgressView()
                                    .tint(.black)
                                    .padding(.trailing, 4)
                            }
                            Text(isAddingPlaylist ? "Đang tải và nạp kênh..." : "Lưu & Tải Danh Sách")
                                .font(.headline)
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            newPlaylistURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.gray
                            : Color.cyan,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    }
                    .disabled(newPlaylistURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAddingPlaylist)

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Thêm Playlist M3U")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { showAddPlaylistSheet = false }
                }
            }
        }
    }
}
