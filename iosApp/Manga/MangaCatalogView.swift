import Foundation
import SwiftUI

// MARK: - Trạng Thái Kết Nối Nguồn Truyện
public enum MangaSourceStatus: Equatable {
    case idle
    case connecting
    case online(itemCount: Int)
    case offline(error: MangaSourceError)

    public var isConnecting: Bool {
        if case .connecting = self { return true }
        return false
    }

    public var isOnline: Bool {
        if case .online = self { return true }
        return false
    }

    public var error: MangaSourceError? {
        if case .offline(let err) = self { return err }
        return nil
    }
}

// MARK: - Manga Catalog ViewModel
@MainActor
public final class MangaCatalogViewModel: ObservableObject {
    @Published public var mangaList: [MangaItem] = []
    @Published public var searchText: String = ""
    @Published public var isLoading: Bool = false
    @Published public var selectedManga: MangaItem? = nil
    @Published public var isLoadingDetail: Bool = false
    @Published public var activeReadingSession: MangaReadingSession? = nil
    @Published public var showAddonsSheet: Bool = false
    @Published public var sourceStatus: MangaSourceStatus = .idle
    @Published public var loadError: MangaSourceError? = nil
    @Published public var isUsingSampleData: Bool = false

    private let bridge = ProviderZBridge.shared
    private let addonManager = MangaAddonManager.shared
    private let libraryStore = MangaLibraryStore.shared

    public init() {
        Task {
            await loadCatalog()
        }
    }

    public func loadCatalog(showLoading: Bool = true) async {
        if showLoading {
            isLoading = true
        }
        sourceStatus = .connecting
        loadError = nil
        isUsingSampleData = false

        let result = await bridge.fetchHomeManga(addon: addonManager.activeAddon)
        if let err = result.error {
            loadError = err
            sourceStatus = .offline(error: err)
            // Không âm thầm rơi về dữ liệu mẫu - giữ danh sách trống để hiện màn hình lỗi rõ ràng
            mangaList = []
        } else {
            mangaList = result.items
            loadError = nil
            sourceStatus = .online(itemCount: result.items.count)
        }
        isLoading = false
    }

    public func search() async {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            await loadCatalog()
            return
        }

        isLoading = true
        sourceStatus = .connecting
        loadError = nil
        isUsingSampleData = false

        let result = await bridge.searchManga(query: trimmed, addon: addonManager.activeAddon)
        if let err = result.error {
            loadError = err
            sourceStatus = .offline(error: err)
            mangaList = []
        } else {
            mangaList = result.items
            loadError = nil
            sourceStatus = .online(itemCount: result.items.count)
        }
        isLoading = false
    }

    public func loadSampleData() {
        mangaList = bridge.mockHomeManga
        loadError = nil
        isUsingSampleData = true
        sourceStatus = .online(itemCount: mangaList.count)
    }

    public func selectManga(_ item: MangaItem) {
        selectedManga = item
        isLoadingDetail = true
        Task {
            let detailed = await bridge.fetchDetail(for: item, addon: addonManager.activeAddon)
            self.libraryStore.refresh(detailed)
            self.selectedManga = detailed
            self.isLoadingDetail = false
        }
    }

    public func startReading(_ chapter: MangaChapter) {
        guard let manga = selectedManga else { return }

        // A view controller cannot reliably present a full-screen cover while
        // it is already presenting the detail sheet. Dismiss first, then open
        // the reader after the sheet's dismissal animation has completed.
        let session = MangaReadingSession(manga: manga, chapter: chapter)
        selectedManga = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.activeReadingSession = session
        }
    }

    public func resume(_ progress: MangaReadingProgress) {
        activeReadingSession = MangaReadingSession(
            manga: progress.resumeManga,
            chapter: progress.chapter,
            initialPageIndex: progress.pageIndex
        )
    }

    public func openFollowed(_ followed: MangaFollowedSeries) {
        let addon = addonManager.addons.first(where: { $0.id == followed.addonID })
            ?? addonManager.activeAddon
        selectedManga = followed.sourceManga
        isLoadingDetail = true
        Task {
            let detailed = await bridge.fetchDetail(for: followed.sourceManga, addon: addon)
            libraryStore.refresh(detailed)
            selectedManga = detailed
            isLoadingDetail = false
        }
    }
}

// MARK: - Manga Source Status Badge (Chấm & Nhãn trạng thái nguồn)
struct MangaSourceStatusBadge: View {
    let status: MangaSourceStatus
    let isUsingSampleData: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 7, height: 7)

            Text(statusTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(textColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(indicatorColor.opacity(0.12))
        .clipShape(Capsule())
    }

    private var indicatorColor: Color {
        if isUsingSampleData {
            return .orange
        }
        switch status {
        case .idle:
            return .gray
        case .connecting:
            return .yellow
        case .online:
            return Color(red: 52/255, green: 211/255, blue: 153/255)
        case .offline:
            return Color(red: 248/255, green: 113/255, blue: 113/255)
        }
    }

    private var textColor: Color {
        if isUsingSampleData {
            return .orange
        }
        switch status {
        case .idle:
            return .gray
        case .connecting:
            return .yellow
        case .online:
            return Color(red: 167/255, green: 243/255, blue: 208/255)
        case .offline:
            return Color(red: 254/255, green: 202/255, blue: 202/255)
        }
    }

    private var statusTitle: String {
        if isUsingSampleData {
            return "Dữ liệu mẫu ngoại tuyến"
        }
        switch status {
        case .idle:
            return "Sẵn sàng"
        case .connecting:
            return "Đang kết nối..."
        case .online(let count):
            return count > 0 ? "Trực tuyến (\(count))" : "Trực tuyến"
        case .offline:
            return "Lỗi nguồn"
        }
    }
}

// MARK: - Manga Source Error Card (UI Lỗi Dễ Hiểu & Nút Thử Lại)
struct MangaSourceErrorCard: View {
    let error: MangaSourceError
    let sourceName: String
    let onRetry: () -> Void
    let onChangeSource: () -> Void
    let onUseSampleData: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Icon cảnh báo lớn
            ZStack {
                Circle()
                    .fill(Color(red: 239/255, green: 68/255, blue: 68/255).opacity(0.12))
                    .frame(width: 68, height: 68)

                Image(systemName: iconName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(Color(red: 248/255, green: 113/255, blue: 113/255))
            }
            .padding(.top, 8)

            // Tên nguồn & Badge
            HStack(spacing: 6) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 11))
                Text("Nguồn: \(sourceName)")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(Color(red: 167/255, green: 139/255, blue: 250/255))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(red: 139/255, green: 92/255, blue: 246/255).opacity(0.15))
            .clipShape(Capsule())

            // Tiêu đề lỗi thân thiện
            Text(titleText)
                .font(.headline.weight(.bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            // Mô tả lỗi dễ hiểu
            if let desc = error.errorDescription {
                Text(desc)
                    .font(.subheadline)
                    .foregroundColor(Color(white: 0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }

            // Gợi ý khắc phục
            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            // Nhóm nút hành động
            VStack(spacing: 10) {
                // Nút Thử Lại (Primary CTA)
                Button(action: onRetry) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .bold))
                        Text("Thử lại ngay")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 139/255, green: 92/255, blue: 246/255),
                                Color(red: 124/255, green: 58/255, blue: 237/255)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Nút Đổi Nguồn Khác (Secondary CTA)
                Button(action: onChangeSource) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Đổi sang nguồn truyện khác")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(Color(red: 196/255, green: 181/255, blue: 253/255))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Nút Xem Dữ Liệu Mẫu Ngoại Tuyến (Tertiary CTA)
                Button(action: onUseSampleData) {
                    Text("Xem tạm dữ liệu mẫu ngoại tuyến")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.gray)
                        .underline()
                        .padding(.vertical, 4)
                }
            }
            .padding(.top, 6)
            .padding(.horizontal, 8)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(red: 239/255, green: 68/255, blue: 68/255).opacity(0.22), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var iconName: String {
        switch error {
        case .noInternet:
            return "wifi.slash"
        case .timeout:
            return "hourglass.bottomhalf.filled"
        case .serverError:
            return "server.rack"
        case .invalidResponse:
            return "exclamationmark.icloud.fill"
        case .emptyData:
            return "tray.fill"
        case .invalidUrl, .custom:
            return "exclamationmark.triangle.fill"
        }
    }

    private var titleText: String {
        switch error {
        case .noInternet:
            return "Không có kết nối mạng"
        case .timeout:
            return "Hết thời gian kết nối máy chủ"
        case .serverError:
            return "Máy chủ nguồn gặp sự cố"
        case .invalidResponse:
            return "Dữ liệu nguồn không hợp lệ"
        case .emptyData:
            return "Không có dữ liệu truyện"
        case .invalidUrl, .custom:
            return "Không thể tải từ nguồn này"
        }
    }
}

// MARK: - Manga Poster Card
struct MangaPosterCard: View {
    let item: MangaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Color(red: 0.12, green: 0.12, blue: 0.12)

                AsyncImage(url: URL(string: item.displayCover)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .tint(.white)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.gray)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
            )

            Text(item.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }
}

struct MangaContinueReadingCard: View {
    let progress: MangaReadingProgress

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: progress.mangaCover)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.white.opacity(0.1)
                }
            }
            .frame(width: 54, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text("Đọc tiếp")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.purple)
                Text(progress.mangaTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(progress.chapter.title)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
                ProgressView(value: Double(progress.completedPageCount), total: Double(max(progress.pageCount, 1)))
                    .tint(.purple)
                Text("Trang \(progress.completedPageCount) / \(max(progress.pageCount, 1))")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            Spacer(minLength: 0)
            Image(systemName: "play.fill")
                .foregroundColor(.white)
                .padding(10)
                .background(Color.purple)
                .clipShape(Circle())
        }
        .padding(10)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct MangaFollowedCard: View {
    let series: MangaFollowedSeries

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: URL(string: series.mangaCover)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.white.opacity(0.1)
                }
            }
            .frame(width: 96, height: 132)
            .clipShape(RoundedRectangle(cornerRadius: 9))

            Text(series.mangaTitle)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: 96, alignment: .leading)

            if series.unreadCount > 0 {
                Text("\(series.unreadCount) chương mới")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.purple)
            } else {
                Text("Đã cập nhật")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
    }
}

struct MangaReadingHistoryCard: View {
    let progress: MangaReadingProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: URL(string: progress.mangaCover)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.white.opacity(0.1)
                }
            }
            .frame(width: 100, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 9))

            Text(progress.mangaTitle)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)
            Text("\(progress.chapter.title) · tr. \(progress.completedPageCount)")
                .font(.caption2)
                .foregroundColor(.gray)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)
        }
    }
}

// MARK: - Manga Detail Sheet
struct MangaDetailSheet: View {
    let manga: MangaItem
    let isLoadingDetail: Bool
    let onSelectChapter: (MangaChapter) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showChapterPicker = false
    @ObservedObject private var libraryStore = MangaLibraryStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header (Cover + Info)
                    HStack(alignment: .top, spacing: 16) {
                        AsyncImage(url: URL(string: manga.displayCover)) { phase in
                            if let img = phase.image {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Color.gray.opacity(0.2)
                            }
                        }
                        .frame(width: 110, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 6) {
                            Text(manga.title)
                                .font(.title3.bold())
                                .foregroundColor(.white)

                            if let authors = manga.authors, !authors.isEmpty {
                                Text("Tác giả: \(authors.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }

                            if let status = manga.status {
                                Text("Trạng thái: \(status)")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }

                            if let genres = manga.genres, !genres.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(genres, id: \.self) { genre in
                                            Text(genre)
                                                .font(.caption2)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.white.opacity(0.1))
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Tóm tắt truyện
                    if let desc = manga.description, !desc.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Nội dung")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text(desc)
                                .font(.footnote)
                                .foregroundColor(.gray)
                                .lineLimit(5)
                        }
                    }

                    Button {
                        if libraryStore.isFollowing(mangaID: manga.id) {
                            libraryStore.unfollow(mangaID: manga.id)
                        } else {
                            libraryStore.follow(manga, addonID: MangaAddonManager.shared.activeAddon.id)
                        }
                    } label: {
                        let isFollowing = libraryStore.isFollowing(mangaID: manga.id)
                        Label(
                            isFollowing ? "Đang theo dõi" : "Theo dõi truyện",
                            systemImage: isFollowing ? "checkmark.circle.fill" : "plus.circle"
                        )
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(isFollowing ? Color.green.opacity(0.20) : Color.purple.opacity(0.22))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .foregroundColor(.white)

                    Divider().background(Color.white.opacity(0.1))

                    // Danh sách Chapter
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Danh sách chương")
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                            if isLoadingDetail {
                                ProgressView()
                                    .tint(.red)
                                    .scaleEffect(0.8)
                            }
                        }

                        if let chapters = manga.chapters, !chapters.isEmpty {
                            LazyVStack(spacing: 8) {
                                ForEach(chapters.prefix(5)) { ch in
                                    Button(action: {
                                        onSelectChapter(ch)
                                    }) {
                                        HStack {
                                            Text(ch.title)
                                                .font(.subheadline)
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                            Spacer()
                                            if let date = ch.date {
                                                Text(date)
                                                    .font(.caption2)
                                                    .foregroundColor(.gray)
                                            }
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 12)
                                        .background(Color.white.opacity(0.06))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                            }

                            Button {
                                showChapterPicker = true
                            } label: {
                                Label("Xem và chọn tất cả \(chapters.count) chương", systemImage: "list.number")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(Color.purple.opacity(0.22))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .foregroundColor(.white)
                        } else if !isLoadingDetail {
                            Text("Không có dữ liệu chương.")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .padding(.vertical, 10)
                        }
                    }
                }
                .padding(18)
            }
            .background(Color(red: 0.07, green: 0.07, blue: 0.07).ignoresSafeArea())
            .navigationTitle("Chi tiết truyện")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Đóng") { dismiss() }
                        .foregroundColor(.red)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showChapterPicker) {
            if let chapters = manga.chapters {
                MangaChapterPickerView(
                    chapters: chapters,
                    readChapterIDs: libraryStore.readChapterIDs(mangaID: manga.id),
                    onSelectChapter: { chapter in
                        showChapterPicker = false
                        // Let the picker dismiss before the detail sheet closes and
                        // MangaCatalogView presents the reader.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onSelectChapter(chapter)
                        }
                    },
                    onMarkAllRead: {
                        libraryStore.markAllRead(mangaID: manga.id, chapters: chapters)
                    }
                )
                .presentationDetents([.large])
            }
        }
    }
}

// MARK: - Main Manga Catalog View
public struct MangaCatalogView: View {
    @StateObject private var viewModel = MangaCatalogViewModel()
    @ObservedObject private var addonManager = MangaAddonManager.shared
    @ObservedObject private var readingProgress = MangaReadingProgressStore.shared
    @ObservedObject private var libraryStore = MangaLibraryStore.shared

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.051, green: 0.051, blue: 0.051).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let progress = readingProgress.latest {
                            Button {
                                viewModel.resume(progress)
                            } label: {
                                MangaContinueReadingCard(progress: progress)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                        }

                        if readingProgress.recent.count > 1 {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Lịch sử đọc")
                                    .font(.title3.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(Array(readingProgress.recent.dropFirst().prefix(20))) { progress in
                                            Button {
                                                viewModel.resume(progress)
                                            } label: {
                                                MangaReadingHistoryCard(progress: progress)
                                            }
                                            .buttonStyle(.plain)
                                            .contextMenu {
                                                Button(role: .destructive) {
                                                    readingProgress.remove(mangaID: progress.mangaID)
                                                } label: {
                                                    Label("Xóa khỏi lịch sử", systemImage: "trash")
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                        }

                        if !libraryStore.followed.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Đang theo dõi")
                                    .font(.title3.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(libraryStore.followed) { series in
                                            Button {
                                                viewModel.openFollowed(series)
                                            } label: {
                                                MangaFollowedCard(series: series)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                        }

                        // Thanh tìm kiếm
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                            TextField("Tìm truyện trên \(addonManager.activeAddon.name)...", text: $viewModel.searchText)
                                .foregroundColor(.white)
                                .onSubmit {
                                    Task { await viewModel.search() }
                                }
                            if !viewModel.searchText.isEmpty {
                                Button(action: {
                                    viewModel.searchText = ""
                                    Task { await viewModel.loadCatalog() }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 16)

                        // 1. Banner thông báo nếu người dùng chủ động xem dữ liệu mẫu
                        if viewModel.isUsingSampleData {
                            HStack(alignment: .center, spacing: 10) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 15))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Đang xem dữ liệu mẫu ngoại tuyến")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(.white)
                                    Text("Dữ liệu này chỉ dùng để xem thử giao diện đọc truyện.")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }

                                Spacer(minLength: 0)

                                Button {
                                    Task { await viewModel.loadCatalog() }
                                } label: {
                                    Text("Kết nối nguồn thật")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.orange)
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(10)
                            .background(Color.orange.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal, 16)
                        }

                        // 2. Banner cảnh báo lỗi khi vẫn còn danh sách truyện cũ hiển thị
                        if let error = viewModel.loadError, !viewModel.mangaList.isEmpty {
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(error.errorDescription ?? error.localizedDescription)
                                    .font(.caption)
                                    .foregroundColor(.orange.opacity(0.95))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Button("Thử lại") {
                                    Task { await viewModel.loadCatalog() }
                                }
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white)
                            }
                            .padding(10)
                            .background(Color.orange.opacity(0.13))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal, 16)
                        }

                        // 3. Tiêu đề danh mục + Huy hiệu trạng thái nguồn + Bộ chọn nguồn Add-on nhanh
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(viewModel.searchText.isEmpty ? "Truyện mới cập nhật" : "Kết quả tìm kiếm")
                                    .font(.title3.bold())
                                    .foregroundColor(.white)

                                MangaSourceStatusBadge(
                                    status: viewModel.sourceStatus,
                                    isUsingSampleData: viewModel.isUsingSampleData
                                )
                            }

                            Spacer()

                            // Menu chuyển đổi nguồn Add-on
                            Menu {
                                Section("Nguồn truyện đang bật") {
                                    ForEach(addonManager.addons.filter { $0.isEnabled }) { addon in
                                        Button {
                                            addonManager.selectAddon(id: addon.id)
                                            Task { await viewModel.loadCatalog() }
                                        } label: {
                                            HStack {
                                                Text(addon.name)
                                                if addon.id == addonManager.activeAddonId {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                }

                                Divider()

                                Button {
                                    viewModel.showAddonsSheet = true
                                } label: {
                                    Label("Quản lý Add-on...", systemImage: "puzzlepiece.extension")
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "puzzlepiece.extension.fill")
                                        .font(.system(size: 11))
                                    Text(addonManager.activeAddon.name)
                                        .font(.system(size: 12, weight: .bold))
                                        .lineLimit(1)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color(red: 139/255, green: 92/255, blue: 246/255).opacity(0.18))
                                .foregroundColor(Color(red: 167/255, green: 139/255, blue: 250/255))
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 16)

                        // 4. Vùng hiển thị chính: Đang tải / Lỗi nguồn / Không có kết quả / Lưới truyện
                        if viewModel.isLoading {
                            VStack(spacing: 12) {
                                Spacer(minLength: 80)
                                ProgressView().tint(.purple).scaleEffect(1.2)
                                Text("Đang tải từ \(addonManager.activeAddon.name)...")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                        } else if let error = viewModel.loadError, viewModel.mangaList.isEmpty {
                            // HIỂN THỊ LỖI DỄ HIỂU VÀ NÚT THỬ LẠI (Không âm thầm rơi về dữ liệu mẫu)
                            MangaSourceErrorCard(
                                error: error,
                                sourceName: addonManager.activeAddon.name,
                                onRetry: {
                                    Task { await viewModel.loadCatalog() }
                                },
                                onChangeSource: {
                                    viewModel.showAddonsSheet = true
                                },
                                onUseSampleData: {
                                    viewModel.loadSampleData()
                                }
                            )
                        } else if viewModel.mangaList.isEmpty {
                            VStack(spacing: 12) {
                                Spacer(minLength: 60)
                                Image(systemName: viewModel.searchText.isEmpty ? "books.vertical" : "magnifyingglass")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray.opacity(0.7))
                                Text(viewModel.searchText.isEmpty ? "Không có truyện nào từ nguồn này" : "Không tìm thấy truyện phù hợp")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                if !viewModel.searchText.isEmpty {
                                    Text("Không có kết quả nào cho \"\(viewModel.searchText)\".")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                HStack(spacing: 12) {
                                    Button("Tải lại") {
                                        Task { await viewModel.loadCatalog() }
                                    }
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.purple.opacity(0.3))
                                    .clipShape(Capsule())

                                    Button("Đổi nguồn") {
                                        viewModel.showAddonsSheet = true
                                    }
                                    .font(.subheadline.bold())
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(Capsule())
                                }
                                .padding(.top, 4)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(viewModel.mangaList) { item in
                                    MangaPosterCard(item: item)
                                        .onTapGesture {
                                            viewModel.selectManga(item)
                                        }
                                    }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 30)
                        }
                    }
                    .padding(.top, 10)
                }
                .refreshable {
                    await viewModel.loadCatalog(showLoading: false)
                }
            }
            .navigationTitle("Truyện Tranh")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showAddonsSheet = true
                    } label: {
                        Image(systemName: "puzzlepiece.extension")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(red: 167/255, green: 139/255, blue: 250/255))
                    }
                }
            }
            .sheet(isPresented: $viewModel.showAddonsSheet, onDismiss: {
                Task { await viewModel.loadCatalog() }
            }) {
                MangaAddonsView()
            }
            .sheet(item: $viewModel.selectedManga) { manga in
                MangaDetailSheet(
                    manga: manga,
                    isLoadingDetail: viewModel.isLoadingDetail,
                    onSelectChapter: { chapter in
                        viewModel.startReading(chapter)
                    }
                )
            }
            .fullScreenCover(item: $viewModel.activeReadingSession) { session in
                MangaReaderView(
                    viewModel: MangaReaderViewModel(
                        manga: session.manga,
                        initialChapter: session.chapter,
                        initialPageIndex: session.initialPageIndex
                    )
                )
            }
        }
        .preferredColorScheme(.dark)
    }
}
