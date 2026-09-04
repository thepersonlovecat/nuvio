import SwiftUI

// MARK: - Manga Catalog ViewModel
@MainActor
public final class MangaCatalogViewModel: ObservableObject {
    @Published public var mangaList: [MangaItem] = []
    @Published public var searchText: String = ""
    @Published public var isLoading: Bool = false
    @Published public var selectedManga: MangaItem? = nil
    @Published public var isLoadingDetail: Bool = false
    @Published public var activeReadingChapter: MangaChapter? = nil

    private let bridge = ProviderZBridge.shared

    public init() {
        Task {
            await loadCatalog()
        }
    }

    public func loadCatalog() async {
        isLoading = true
        mangaList = await bridge.fetchHomeManga()
        isLoading = false
    }

    public func search() async {
        isLoading = true
        mangaList = await bridge.searchManga(query: searchText)
        isLoading = false
    }

    public func selectManga(_ item: MangaItem) {
        selectedManga = item
        isLoadingDetail = true
        Task {
            let detailed = await bridge.fetchDetail(for: item)
            self.selectedManga = detailed
            self.isLoadingDetail = false
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

// MARK: - Manga Detail Sheet
struct MangaDetailSheet: View {
    let manga: MangaItem
    let isLoadingDetail: Bool
    let onSelectChapter: (MangaChapter) -> Void
    @Environment(\.dismiss) private var dismiss

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
                            }
                        }

                        if let chapters = manga.chapters, !chapters.isEmpty {
                            LazyVStack(spacing: 8) {
                                ForEach(chapters) { chapter in
                                    Button(action: {
                                        onSelectChapter(chapter)
                                    }) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(chapter.title)
                                                    .font(.subheadline.weight(.medium))
                                                    .foregroundColor(.white)
                                                if let date = chapter.date {
                                                    Text(date)
                                                        .font(.caption2)
                                                        .foregroundColor(.gray)
                                                }
                                            }
                                            Spacer()
                                            Image(systemName: "book.fill")
                                                .font(.caption)
                                                .foregroundColor(.red)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .background(Color.white.opacity(0.05))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        } else if !isLoadingDetail {
                            Text("Chưa có danh sách chương.")
                                .font(.footnote)
                                .foregroundColor(.gray)
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
    }
}

// MARK: - Main Manga Catalog View
public struct MangaCatalogView: View {
    @StateObject private var viewModel = MangaCatalogViewModel()

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
                        // Thanh tìm kiếm
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                            TextField("Tìm truyện tranh...", text: $viewModel.searchText)
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

                        // Tiêu đề danh mục
                        HStack {
                            Text(viewModel.searchText.isEmpty ? "Truyện mới cập nhật" : "Kết quả tìm kiếm")
                                .font(.title3.bold())
                                .foregroundColor(.white)
                            Spacer()
                            Text("Provider-Z")
                                .font(.caption.bold())
                                .foregroundColor(.red)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.red.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 16)

                        // Lưới hiển thị danh sách
                        if viewModel.isLoading {
                            VStack {
                                Spacer(minLength: 80)
                                ProgressView().tint(.red).scaleEffect(1.2)
                                Text("Đang tải danh sách truyện...")
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
            .sheet(item: $viewModel.selectedManga) { manga in
                MangaDetailSheet(
                    manga: manga,
                    isLoadingDetail: viewModel.isLoadingDetail,
                    onSelectChapter: { chapter in
                        viewModel.activeReadingChapter = chapter
                    }
                )
            }
            .fullScreenCover(item: $viewModel.activeReadingChapter) { chapter in
                if let manga = viewModel.selectedManga {
                    MangaReaderView(
                        viewModel: MangaReaderViewModel(
                            manga: manga,
                            initialChapter: chapter
                        )
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
