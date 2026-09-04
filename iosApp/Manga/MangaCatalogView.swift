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
    @Published public var activeReadingSession: MangaReadingSession? = nil
    @Published public var showAddonsSheet: Bool = false
    @Published public var sourceStatus: MangaSourceStatus = .idle
    @Published public var loadError: MangaSourceError? = nil
    /// Trạng thái tải thêm trang kế (infinite scroll)
    @Published public var isLoadingMore: Bool = false
    @Published public var canLoadMore: Bool = false
    /// Lọc theo thể loại (áp dụng trên kết quả đã tải)
    @Published public var selectedGenre: String? = nil
    /// Ngăn xếp điều hướng chuẩn iOS 16+
    @Published public var navPath = NavigationPath()

    private let bridge = ProviderZBridge.shared
    private let addonManager = MangaAddonManager.shared
    private let libraryStore = MangaLibraryStore.shared
    private var searchDebounceTask: Task<Void, Never>?
    private var currentPage: Int = 1

    public init() {
        Task {
            await loadCatalog()
        }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Danh sách thể loại có trong kết quả đã tải (để hiện thanh lọc nhanh).
    public var availableGenres: [String] {
        Array(Set(mangaList.compactMap { $0.genres }.flatMap { $0 })).sorted()
    }

    /// Danh sách hiển thị sau khi áp dụng bộ lọc thể loại.
    public var displayedManga: [MangaItem] {
        guard let genre = selectedGenre else { return mangaList }
        return mangaList.filter { $0.genres?.contains(genre) == true }
    }

    public func loadCatalog(showLoading: Bool = true) async {
        searchDebounceTask?.cancel()
        currentPage = 1
        if showLoading {
            isLoading = true
        }
        sourceStatus = .connecting
        loadError = nil

        let result = await bridge.fetchHomeManga(addon: addonManager.activeAddon, page: 1)
        if let err = result.error {
            loadError = err
            sourceStatus = .offline(error: err)
            // Giữ danh sách trống để hiện màn hình lỗi rõ ràng
            mangaList = []
            canLoadMore = false
        } else {
            mangaList = result.items
            loadError = nil
            sourceStatus = .online(itemCount: result.items.count)
            canLoadMore = result.hasMorePages
        }
        isLoading = false
    }

    public func search() async {
        currentPage = 1
        let trimmed = trimmedSearchText
        guard !trimmed.isEmpty else {
            await loadCatalog()
            return
        }

        isLoading = true
        sourceStatus = .connecting
        loadError = nil

        let result = await bridge.searchManga(query: trimmed, addon: addonManager.activeAddon, page: 1)
        if let err = result.error {
            loadError = err
            sourceStatus = .offline(error: err)
            mangaList = []
            canLoadMore = false
        } else {
            mangaList = result.items
            loadError = nil
            sourceStatus = .online(itemCount: result.items.count)
            canLoadMore = result.hasMorePages
        }
        isLoading = false
    }

    /// Tự động tìm kiếm sau khi người dùng ngừng gõ ~0.5s,
    /// tránh gọi API liên tục theo từng ký tự.
    public func searchTextDidChange() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.search()
        }
    }

    /// Tìm ngay lập tức (khi người dùng bấm nút Search trên bàn phím).
    public func searchImmediately() {
        searchDebounceTask?.cancel()
        Task { await search() }
    }

    /// Tải trang kế tiếp và nối vào danh sách (infinite scroll).
    /// Có lọc trùng theo id để phòng nguồn trả về dữ liệu lặp.
    public func loadNextPage() async {
        guard canLoadMore, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        let nextPage = currentPage + 1

        let result: MangaCatalogLoadResult
        let trimmed = trimmedSearchText
        if trimmed.isEmpty {
            result = await bridge.fetchHomeManga(addon: addonManager.activeAddon, page: nextPage)
        } else {
            result = await bridge.searchManga(query: trimmed, addon: addonManager.activeAddon, page: nextPage)
        }

        if result.error == nil {
            let existingIDs = Set(mangaList.map(\.id))
            let newItems = result.items.filter { !existingIDs.contains($0.id) }
            if newItems.isEmpty {
                // Trang mới toàn dữ liệu trùng/rỗng -> coi như đã hết
                canLoadMore = false
            } else {
                mangaList.append(contentsOf: newItems)
                currentPage = nextPage
                canLoadMore = result.hasMorePages
                sourceStatus = .online(itemCount: mangaList.count)
            }
        }
        isLoadingMore = false
    }

    public func selectManga(_ item: MangaItem) {
        navPath.append(item)
    }

    public func startReading(_ chapter: MangaChapter, manga: MangaItem) {
        activeReadingSession = MangaReadingSession(manga: manga, chapter: chapter)
    }

    public func resume(_ progress: MangaReadingProgress) {
        activeReadingSession = MangaReadingSession(
            manga: progress.resumeManga,
            chapter: progress.chapter,
            initialPageIndex: progress.pageIndex
        )
    }

    public func openFollowed(_ followed: MangaFollowedSeries) {
        navPath.append(followed.sourceManga)
    }
}

// MARK: - Manga Source Status Badge (Chấm & Nhãn trạng thái nguồn)
struct MangaSourceStatusBadge: View {
    let status: MangaSourceStatus

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
        case .noAddonInstalled:
            return "puzzlepiece.extension"
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
        case .noAddonInstalled:
            return "Chưa cài đặt nguồn truyện"
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
            MangaCoverImageView(urlString: item.displayCover)
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
            MangaCoverImageView(urlString: progress.mangaCover)
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
            MangaCoverImageView(urlString: series.mangaCover)
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
            MangaCoverImageView(urlString: progress.mangaCover)
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

    /// Nút chip lọc thể loại
    private func genreChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(isSelected ? .white : Color(red: 196/255, green: 181/255, blue: 253/255))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected
                        ? Color(red: 139/255, green: 92/255, blue: 246/255)
                        : Color(red: 139/255, green: 92/255, blue: 246/255).opacity(0.15)
                )
                .clipShape(Capsule())
        }
        .accessibilityLabel("Thể loại \(title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    public var body: some View {
        NavigationStack(path: $viewModel.navPath) {
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

                        // Thanh tìm kiếm (tự động tìm sau khi ngừng gõ ~0.5s)
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                            TextField("Tìm truyện trên \(addonManager.activeAddon?.name ?? "nguồn đã cài")...", text: $viewModel.searchText)
                                .foregroundColor(.white)
                                .submitLabel(.search)
                                .onSubmit {
                                    viewModel.searchImmediately()
                                }
                                .onChange(of: viewModel.searchText) { _ in
                                    viewModel.searchTextDidChange()
                                }
                            if !viewModel.searchText.isEmpty {
                                Button(action: {
                                    // Xóa chữ -> onChange sẽ tự quay về trang chủ qua debounce
                                    viewModel.searchText = ""
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                                .accessibilityLabel("Xóa từ khóa tìm kiếm")
                            }
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 16)

                        // Thanh lọc nhanh theo thể loại (chỉ hiện khi kết quả có dữ liệu thể loại)
                        if viewModel.availableGenres.count > 1 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    genreChip(title: "Tất cả", isSelected: viewModel.selectedGenre == nil) {
                                        viewModel.selectedGenre = nil
                                    }
                                    ForEach(viewModel.availableGenres, id: \.self) { genre in
                                        genreChip(title: genre, isSelected: viewModel.selectedGenre == genre) {
                                            viewModel.selectedGenre = genre
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
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

                                MangaSourceStatusBadge(status: viewModel.sourceStatus)
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
                                    Text(addonManager.activeAddon?.name ?? "Chọn nguồn")
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
                                Text("Đang tải từ \(addonManager.activeAddon?.name ?? "nguồn truyện")...")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                        } else if let error = viewModel.loadError, viewModel.mangaList.isEmpty {
                            // HIỂN THỊ LỖI DỄ HIỂU VÀ NÚT THỬ LẠI
                            MangaSourceErrorCard(
                                error: error,
                                sourceName: addonManager.activeAddon?.name ?? "Chưa có",
                                onRetry: {
                                    Task { await viewModel.loadCatalog() }
                                },
                                onChangeSource: {
                                    viewModel.showAddonsSheet = true
                                }
                            )
                        } else if viewModel.displayedManga.isEmpty {
                            VStack(spacing: 12) {
                                Spacer(minLength: 60)
                                Image(systemName: viewModel.searchText.isEmpty ? "books.vertical" : "magnifyingglass")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray.opacity(0.7))
                                Text(emptyStateTitle)
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
                                ForEach(viewModel.displayedManga) { item in
                                    MangaPosterCard(item: item)
                                        .onTapGesture {
                                            viewModel.selectManga(item)
                                        }
                                        .accessibilityElement(children: .combine)
                                        .accessibilityLabel(item.title)
                                        .accessibilityHint("Chạm để xem chi tiết và danh sách chương")
                                        .onAppear {
                                            // Cuộn gần tới cuối -> tự tải trang kế tiếp
                                            if item.id == viewModel.displayedManga.last?.id {
                                                Task { await viewModel.loadNextPage() }
                                            }
                                        }
                                    }
                            }
                            .padding(.horizontal, 16)

                            // Chỉ báo đang tải thêm trang mới
                            if viewModel.isLoadingMore {
                                HStack(spacing: 8) {
                                    ProgressView().tint(.purple)
                                    Text("Đang tải thêm truyện...")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }

                            Spacer(minLength: 30)
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
                    .accessibilityLabel("Quản lý Add-on truyện")
                }
            }
            .sheet(isPresented: $viewModel.showAddonsSheet, onDismiss: {
                Task { await viewModel.loadCatalog() }
            }) {
                MangaAddonsView()
            }
            .navigationDestination(for: MangaItem.self) { manga in
                MangaDetailView(manga: manga) { chapter, detailedManga in
                    viewModel.startReading(chapter, manga: detailedManga)
                }
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

    /// Tiêu đề trạng thái trống tùy theo ngữ cảnh: lọc thể loại / tìm kiếm / nguồn rỗng
    private var emptyStateTitle: String {
        if viewModel.selectedGenre != nil, !viewModel.mangaList.isEmpty {
            return "Không có truyện thuộc thể loại này"
        }
        return viewModel.searchText.isEmpty ? "Không có truyện nào từ nguồn này" : "Không tìm thấy truyện phù hợp"
    }
}
