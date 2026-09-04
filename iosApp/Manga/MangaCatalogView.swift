import Foundation
import SwiftUI

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

    private let bridge = ProviderZBridge.shared
    private let addonManager = MangaAddonManager.shared
    private let libraryStore = MangaLibraryStore.shared

    public init() {
        Task {
            await loadCatalog()
        }
    }

    public func loadCatalog() async {
        isLoading = true
        mangaList = await bridge.fetchHomeManga(addon: addonManager.activeAddon)
        isLoading = false
    }

    public func search() async {
        isLoading = true
        mangaList = await bridge.searchManga(query: searchText, addon: addonManager.activeAddon)
        isLoading = false
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

                        // Tiêu đề danh mục + Bộ chọn nguồn Add-on nhanh
                        HStack(alignment: .center) {
                            Text(viewModel.searchText.isEmpty ? "Truyện mới cập nhật" : "Kết quả tìm kiếm")
                                .font(.title3.bold())
                                .foregroundColor(.white)

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

                        // Lưới hiển thị danh sách
                        if viewModel.isLoading {
                            VStack {
                                Spacer(minLength: 80)
                                ProgressView().tint(.purple).scaleEffect(1.2)
                                Text("Đang tải từ \(addonManager.activeAddon.name)...")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(.top, 8)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                        } else if viewModel.mangaList.isEmpty {
                            VStack(spacing: 8) {
                                Spacer(minLength: 80)
                                Image(systemName: "books.vertical")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                Text("Không tìm thấy truyện phù hợp")
                                    .foregroundColor(.gray)
                                Button("Tải lại") {
                                    Task { await viewModel.loadCatalog() }
                                }
                                .font(.caption.bold())
                                .foregroundColor(Color(red: 167/255, green: 139/255, blue: 250/255))
                                .padding(.top, 6)
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
