import SwiftUI

// MARK: - Manga Reader ViewModel
@MainActor
public final class MangaReaderViewModel: ObservableObject {
    @Published public var manga: MangaItem
    @Published public var currentChapter: MangaChapter
    @Published public var pages: [MangaPage] = []
    @Published public var currentPageIndex: Int = 0
    @Published public var isLoading: Bool = false
    @Published public var readingMode: ReadingMode = .webtoon
    @Published public var showControls: Bool = true
    @Published public var errorMessage: String? = nil

    private let bridge = ProviderZBridge.shared
    private let initialPageIndex: Int

    public init(manga: MangaItem, initialChapter: MangaChapter, initialPageIndex: Int = 0) {
        self.manga = manga
        self.currentChapter = initialChapter
        self.initialPageIndex = max(0, initialPageIndex)
        loadPages(for: initialChapter)
    }

    public func loadPages(for chapter: MangaChapter) {
        let shouldRestoreInitialPage = chapter.id == currentChapter.id && pages.isEmpty
        self.currentChapter = chapter
        self.isLoading = true
        self.errorMessage = nil
        self.currentPageIndex = shouldRestoreInitialPage ? initialPageIndex : 0

        Task {
            let loadedPages = await bridge.fetchPages(chapterUrl: chapter.url)
            if loadedPages.isEmpty {
                self.errorMessage = "Không tìm thấy trang truyện của chương này."
            } else {
                self.pages = loadedPages
                self.currentPageIndex = min(self.currentPageIndex, loadedPages.count - 1)
            }
            self.isLoading = false
        }
    }

    public func toggleControls() {
        withAnimation(.easeInOut(duration: 0.22)) {
            showControls.toggle()
        }
    }

    public func saveProgress() {
        guard !pages.isEmpty else { return }
        MangaReadingProgressStore.shared.save(
            manga: manga,
            chapter: currentChapter,
            pageIndex: currentPageIndex,
            pageCount: pages.count
        )
    }

    public var hasPreviousChapter: Bool {
        guard let chapters = manga.chapters,
              let currentIndex = chapters.firstIndex(where: { $0.id == currentChapter.id }) else {
            return false
        }
        return currentIndex < chapters.count - 1
    }

    public var hasNextChapter: Bool {
        guard let chapters = manga.chapters,
              let currentIndex = chapters.firstIndex(where: { $0.id == currentChapter.id }) else {
            return false
        }
        return currentIndex > 0
    }

    public func goToPreviousChapter() {
        guard let chapters = manga.chapters,
              let currentIndex = chapters.firstIndex(where: { $0.id == currentChapter.id }),
              currentIndex < chapters.count - 1 else { return }
        loadPages(for: chapters[currentIndex + 1])
    }

    public func goToNextChapter() {
        guard let chapters = manga.chapters,
              let currentIndex = chapters.firstIndex(where: { $0.id == currentChapter.id }),
              currentIndex > 0 else { return }
        loadPages(for: chapters[currentIndex - 1])
    }
}

// MARK: - Single Manga Page View
struct MangaPageView: View {
    let page: MangaPage
    @State private var currentZoom: CGFloat = 1.0
    @State private var finalZoom: CGFloat = 1.0

    var body: some View {
        AsyncImage(url: URL(string: page.url)) { phase in
            switch phase {
            case .empty:
                ZStack {
                    Color(red: 0.08, green: 0.08, blue: 0.08)
                    ProgressView()
                        .tint(.white)
                }
                .aspectRatio(2.0 / 3.0, contentMode: .fit)

            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(currentZoom * finalZoom)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { val in
                                currentZoom = val
                            }
                            .onEnded { val in
                                finalZoom = max(1.0, min(finalZoom * val, 3.5))
                                currentZoom = 1.0
                                if finalZoom < 1.05 {
                                    withAnimation(.spring()) {
                                        finalZoom = 1.0
                                    }
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            finalZoom = finalZoom > 1.2 ? 1.0 : 2.0
                        }
                    }

            case .failure:
                ZStack {
                    Color(red: 0.1, green: 0.1, blue: 0.1)
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundColor(.orange)
                        Text("Trang \(page.index + 1) tải lỗi")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .aspectRatio(2.0 / 3.0, contentMode: .fit)

            @unknown default:
                EmptyView()
            }
        }
    }
}

// MARK: - Main Manga Reader View
public struct MangaReaderView: View {
    @StateObject public var viewModel: MangaReaderViewModel
    @Environment(\.dismiss) private var dismiss

    private let nuvioDarkBackground = Color(red: 0.051, green: 0.051, blue: 0.051)

    public init(viewModel: MangaReaderViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        ZStack {
            nuvioDarkBackground.ignoresSafeArea()

            // ── Reader Content ──
            if viewModel.isLoading {
                VStack(spacing: 14) {
                    ProgressView()
                        .tint(.red)
                        .scaleEffect(1.3)
                    Text("Đang tải dữ liệu từ Provider...")
                        .font(.footnote)
                        .foregroundColor(.gray)
                }
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 44))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Button("Thử lại") {
                        viewModel.loadPages(for: viewModel.currentChapter)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding()
            } else {
                Group {
                    if viewModel.readingMode == .webtoon {
                        // Cuộn dọc liên tục (Webtoon)
                        ScrollViewReader { proxy in
                            ScrollView(.vertical, showsIndicators: false) {
                                LazyVStack(spacing: 2) {
                                    ForEach(viewModel.pages) { page in
                                        MangaPageView(page: page)
                                            .id(page.index)
                                            .onAppear {
                                                viewModel.currentPageIndex = page.index
                                            }
                                    }
                                }
                            }
                            .onChange(of: viewModel.currentPageIndex) { newIndex in
                                proxy.scrollTo(newIndex, anchor: .top)
                            }
                        }
                    } else {
                        // Lật từng trang (Paged Manga)
                        TabView(selection: $viewModel.currentPageIndex) {
                            ForEach(viewModel.pages) { page in
                                MangaPageView(page: page)
                                    .tag(page.index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    }
                }
                .onTapGesture {
                    viewModel.toggleControls()
                }
            }

            // ── HUD Overlay ──
            if viewModel.showControls {
                VStack {
                    topHUD
                    Spacer()
                    bottomHUD
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(!viewModel.showControls)
        .onChange(of: viewModel.currentPageIndex) { _ in
            viewModel.saveProgress()
        }
        .onChange(of: viewModel.currentChapter.id) { _ in
            viewModel.saveProgress()
        }
        .onDisappear {
            viewModel.saveProgress()
        }
    }

    // ── Top HUD ──
    private var topHUD: some View {
        HStack(spacing: 12) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.manga.title)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(viewModel.currentChapter.title)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            Spacer()

            // Mode Selector
            Menu {
                ForEach(ReadingMode.allCases) { mode in
                    Button(action: { viewModel.readingMode = mode }) {
                        Label(mode.rawValue, systemImage: mode.iconName)
                    }
                }
            } label: {
                Image(systemName: viewModel.readingMode.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Color.black.opacity(0.8)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
        )
    }

    // ── Bottom HUD ──
    private var bottomHUD: some View {
        VStack(spacing: 12) {
            if !viewModel.pages.isEmpty {
                HStack(spacing: 12) {
                    Text("\(viewModel.currentPageIndex + 1)")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundColor(.white)
                        .frame(width: 28, alignment: .trailing)

                    Slider(
                        value: Binding(
                            get: { Double(viewModel.currentPageIndex) },
                            set: { viewModel.currentPageIndex = Int($0) }
                        ),
                        in: 0...Double(max(viewModel.pages.count - 1, 1)),
                        step: 1
                    )
                    .tint(.red)

                    Text("\(viewModel.pages.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.gray)
                        .frame(width: 28, alignment: .leading)
                }
            }

            HStack {
                Button(action: { viewModel.goToPreviousChapter() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Chap trước")
                    }
                    .font(.caption.bold())
                }
                .foregroundColor(viewModel.hasPreviousChapter ? .white : .gray.opacity(0.4))
                .disabled(!viewModel.hasPreviousChapter)

                Spacer()

                Text("Trang \(viewModel.currentPageIndex + 1) / \(max(viewModel.pages.count, 1))")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.gray)

                Spacer()

                Button(action: { viewModel.goToNextChapter() }) {
                    HStack(spacing: 4) {
                        Text("Chap sau")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.bold())
                }
                .foregroundColor(viewModel.hasNextChapter ? .white : .gray.opacity(0.4))
                .disabled(!viewModel.hasNextChapter)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            Color.black.opacity(0.85)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}
