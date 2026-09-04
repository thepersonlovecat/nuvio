import SwiftUI
import UIKit

// MARK: - Chiều Đọc (LTR / RTL cho Manga Nhật)
public enum MangaReadingDirection: String, CaseIterable, Identifiable {
    case leftToRight = "Trái → Phải"
    case rightToLeft = "Phải → Trái (Manga)"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .leftToRight: return "arrow.right.to.line"
        case .rightToLeft: return "arrow.left.to.line"
        }
    }
}

// MARK: - Màu Nền Trình Đọc
public enum MangaReaderTheme: String, CaseIterable, Identifiable {
    case black = "Đen"
    case darkGray = "Xám tối"
    case white = "Trắng"

    public var id: String { rawValue }

    public var backgroundColor: Color {
        switch self {
        case .black: return Color(red: 0.051, green: 0.051, blue: 0.051)
        case .darkGray: return Color(red: 0.16, green: 0.16, blue: 0.17)
        case .white: return Color(white: 0.92)
        }
    }

    public var pagePlaceholderColor: Color {
        switch self {
        case .white: return Color(white: 0.82)
        case .darkGray: return Color(red: 0.22, green: 0.22, blue: 0.23)
        case .black: return Color(red: 0.08, green: 0.08, blue: 0.08)
        }
    }
}

// MARK: - Reader Preferences (Lưu lựa chọn đọc của người dùng)
private enum MangaReaderPreferences {
    private static let readingModeKey = "nuvio_manga_reading_mode_v1"
    private static let pageSpacingKey = "nuvio_manga_page_spacing_v1"
    private static let directionKey = "nuvio_manga_reading_direction_v1"
    private static let themeKey = "nuvio_manga_reader_theme_v1"

    static var readingMode: ReadingMode {
        guard let stored = UserDefaults.standard.string(forKey: readingModeKey),
              let mode = ReadingMode(rawValue: stored) else {
            return .webtoon
        }
        return mode
    }

    static var pageSpacing: CGFloat {
        let stored = UserDefaults.standard.object(forKey: pageSpacingKey) as? Double
        return CGFloat(stored ?? 2)
    }

    static var readingDirection: MangaReadingDirection {
        guard let stored = UserDefaults.standard.string(forKey: directionKey),
              let direction = MangaReadingDirection(rawValue: stored) else {
            return .leftToRight
        }
        return direction
    }

    static var readerTheme: MangaReaderTheme {
        guard let stored = UserDefaults.standard.string(forKey: themeKey),
              let theme = MangaReaderTheme(rawValue: stored) else {
            return .black
        }
        return theme
    }

    static func save(readingMode: ReadingMode) {
        UserDefaults.standard.set(readingMode.rawValue, forKey: readingModeKey)
    }

    static func save(pageSpacing: CGFloat) {
        UserDefaults.standard.set(Double(pageSpacing), forKey: pageSpacingKey)
    }

    static func save(readingDirection: MangaReadingDirection) {
        UserDefaults.standard.set(readingDirection.rawValue, forKey: directionKey)
    }

    static func save(readerTheme: MangaReaderTheme) {
        UserDefaults.standard.set(readerTheme.rawValue, forKey: themeKey)
    }
}

// MARK: - Manga Reader ViewModel
@MainActor
public final class MangaReaderViewModel: ObservableObject {
    @Published public var manga: MangaItem
    @Published public var currentChapter: MangaChapter
    @Published public var pages: [MangaPage] = []
    @Published public var currentPageIndex: Int = 0
    @Published public var isLoading: Bool = false
    @Published public var readingMode: ReadingMode = MangaReaderPreferences.readingMode
    @Published public var pageSpacing: CGFloat = MangaReaderPreferences.pageSpacing
    @Published public var readingDirection: MangaReadingDirection = MangaReaderPreferences.readingDirection
    @Published public var readerTheme: MangaReaderTheme = MangaReaderPreferences.readerTheme
    @Published public var showControls: Bool = true
    @Published public var showChapterList: Bool = false
    @Published public var errorMessage: String? = nil

    private let bridge = ProviderZBridge.shared
    private let initialPageIndex: Int
    private var saveProgressTask: Task<Void, Never>?

    public init(manga: MangaItem, initialChapter: MangaChapter, initialPageIndex: Int = 0) {
        self.manga = manga
        self.currentChapter = initialChapter
        self.initialPageIndex = max(0, initialPageIndex)
        loadPages(for: initialChapter)
    }

    public func loadPages(for chapter: MangaChapter) {
        saveProgressTask?.cancel()
        let shouldRestoreInitialPage = chapter.id == currentChapter.id && pages.isEmpty
        self.currentChapter = chapter
        self.isLoading = true
        self.errorMessage = nil
        self.currentPageIndex = shouldRestoreInitialPage ? initialPageIndex : 0

        Task {
            let loadedPages = await bridge.fetchPages(chapterUrl: chapter.url)
            if loadedPages.isEmpty {
                self.pages = []
                self.errorMessage = "Không tải được trang truyện của chương này. Nguồn có thể đang lỗi hoặc chương đã bị gỡ."
            } else {
                self.pages = loadedPages
                self.currentPageIndex = min(self.currentPageIndex, loadedPages.count - 1)
                self.prefetchUpcomingPages()
                self.saveProgress()
            }
            self.isLoading = false
        }
    }

    public func toggleControls() {
        withAnimation(.easeInOut(duration: 0.22)) {
            showControls.toggle()
        }
    }

    public func setReadingMode(_ mode: ReadingMode) {
        readingMode = mode
        MangaReaderPreferences.save(readingMode: mode)
    }

    public func setPageSpacing(_ spacing: CGFloat) {
        pageSpacing = spacing
        MangaReaderPreferences.save(pageSpacing: spacing)
    }

    public func setReadingDirection(_ direction: MangaReadingDirection) {
        readingDirection = direction
        MangaReaderPreferences.save(readingDirection: direction)
    }

    public func setReaderTheme(_ theme: MangaReaderTheme) {
        readerTheme = theme
        MangaReaderPreferences.save(readerTheme: theme)
    }

    // MARK: Điều hướng trang (Tap-zone)

    public func goToNextPage() {
        if currentPageIndex < pages.count - 1 {
            currentPageIndex += 1
        } else if hasNextChapter {
            // Chạm sang trang ở trang cuối -> tự chuyển chương tiếp theo
            goToNextChapter()
        }
    }

    public func goToPreviousPage() {
        if currentPageIndex > 0 {
            currentPageIndex -= 1
        } else if hasPreviousChapter {
            goToPreviousChapter()
        }
    }

    /// Xử lý chạm vào vùng trái/giữa/phải của trang (theo tỉ lệ ngang 0...1).
    /// Tôn trọng chiều đọc RTL: với manga Nhật, chạm bên trái là sang trang kế.
    public func handlePageTap(horizontalFraction fraction: CGFloat) {
        switch fraction {
        case ..<(1.0 / 3.0):
            readingDirection == .rightToLeft ? goToNextPage() : goToPreviousPage()
        case (2.0 / 3.0)...:
            readingDirection == .rightToLeft ? goToPreviousPage() : goToNextPage()
        default:
            toggleControls()
        }
    }

    // MARK: Lưu tiến độ đọc

    /// Ghi tiến độ sau khi người dùng dừng đổi trang ~0.7s,
    /// tránh ghi UserDefaults liên tục khi đang cuộn.
    public func scheduleSaveProgress() {
        saveProgressTask?.cancel()
        saveProgressTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self?.saveProgress()
        }
    }

    public func saveProgress() {
        saveProgressTask?.cancel()
        guard !pages.isEmpty else { return }
        MangaReadingProgressStore.shared.save(
            manga: manga,
            chapter: currentChapter,
            pageIndex: currentPageIndex,
            pageCount: pages.count
        )
        MangaLibraryStore.shared.markRead(mangaID: manga.id, chapterID: currentChapter.id)
    }

    // MARK: Prefetch ảnh

    /// Tải trước tối đa 3 trang kế tiếp để việc cuộn/sang trang mượt hơn.
    public func prefetchUpcomingPages() {
        guard !pages.isEmpty else { return }
        let start = currentPageIndex + 1
        let end = min(currentPageIndex + 3, pages.count - 1)
        guard start <= end else { return }
        MangaImageLoader.shared.prefetch(Array(pages[start...end]))
    }

    // MARK: Điều hướng chương

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

// MARK: - Zoomable Page (UIScrollView: pinch + double-tap zoom, pan khi đã zoom)

/// ScrollView UIKit chuẩn cho ảnh truyện: zoom mượt, pan được khi đã phóng to,
/// và chuyển tiếp single-tap (kèm vị trí chạm) ra ngoài để xử lý tap-zone.
private final class MangaZoomScrollView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()
    var onSingleTap: ((CGFloat) -> Void)?

    init(image: UIImage) {
        super.init(frame: .zero)
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)

        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        bouncesZoom = true
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        contentSize = bounds.size
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > 1.01 {
            setZoomScale(1, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let zoomRect = CGRect(
                x: point.x - bounds.width / 4,
                y: point.y - bounds.height / 4,
                width: bounds.width / 2,
                height: bounds.height / 2
            )
            zoom(to: zoomRect, animated: true)
        }
    }

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        let x = gesture.location(in: self).x
        onSingleTap?(bounds.width > 0 ? x / bounds.width : 0.5)
    }
}

private struct ZoomablePageView: UIViewRepresentable {
    let image: UIImage
    let onSingleTap: (CGFloat) -> Void

    func makeUIView(context: Context) -> MangaZoomScrollView {
        let view = MangaZoomScrollView(image: image)
        view.onSingleTap = onSingleTap
        return view
    }

    func updateUIView(_ uiView: MangaZoomScrollView, context: Context) {
        uiView.imageView.image = image
    }
}

// MARK: - Thành phần trang dùng chung

private struct MangaPagePlaceholder: View {
    let theme: MangaReaderTheme

    var body: some View {
        ZStack {
            theme.pagePlaceholderColor
            ProgressView()
                .tint(theme == .white ? .gray : .white)
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
    }
}

private struct MangaPageErrorView: View {
    let page: MangaPage
    let theme: MangaReaderTheme
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            theme.pagePlaceholderColor
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundColor(.orange)
                Text("Trang \(page.index + 1) tải lỗi")
                    .font(.caption)
                    .foregroundColor(theme == .white ? .black.opacity(0.6) : .gray)
                Button(action: onRetry) {
                    Label("Tải lại trang này", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.purple.opacity(0.8))
                        .clipShape(Capsule())
                }
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
    }
}

/// Trang truyện chế độ cuộn dọc (Webtoon): không gắn cử chỉ zoom để tránh
/// xung đột với cử chỉ cuộn; người dùng cần zoom có thể chuyển chế độ Lật trang.
private struct MangaWebtoonPage: View {
    let page: MangaPage
    let theme: MangaReaderTheme

    var body: some View {
        MangaAsyncImage(urlString: page.url, headers: page.headers) { image in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } placeholder: {
            MangaPagePlaceholder(theme: theme)
        } failure: { retry in
            MangaPageErrorView(page: page, theme: theme, onRetry: retry)
        }
        .accessibilityLabel("Trang \(page.index + 1)")
    }
}

/// Trang truyện chế độ lật trang (Paged): hỗ trợ zoom + tap-zone điều hướng.
private struct MangaPagedPage: View {
    let page: MangaPage
    let theme: MangaReaderTheme
    let onTapZone: (CGFloat) -> Void

    var body: some View {
        MangaAsyncImage(urlString: page.url, headers: page.headers) { image in
            ZoomablePageView(image: image, onSingleTap: onTapZone)
        } placeholder: {
            MangaPagePlaceholder(theme: theme)
        } failure: { retry in
            MangaPageErrorView(page: page, theme: theme, onRetry: retry)
        }
        .accessibilityLabel("Trang \(page.index + 1)")
    }
}

// MARK: - Main Manga Reader View
public struct MangaReaderView: View {
    @StateObject public var viewModel: MangaReaderViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var libraryStore = MangaLibraryStore.shared

    /// Proxy cuộn của chế độ Webtoon: chỉ dùng khi người dùng kéo Slider,
    /// tránh vòng lặp "cuộn -> cập nhật trang -> ép cuộn về đầu trang".
    @State private var webtoonScrollProxy: ScrollViewProxy?
    @State private var didRestoreInitialPosition = false

    public init(viewModel: MangaReaderViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        ZStack {
            viewModel.readerTheme.backgroundColor.ignoresSafeArea()

            // ── Reader Content ──
            if viewModel.isLoading {
                VStack(spacing: 14) {
                    ProgressView()
                        .tint(.red)
                        .scaleEffect(1.3)
                    Text("Đang tải dữ liệu từ nguồn...")
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
                        .foregroundColor(viewModel.readerTheme == .white ? .black : .white)
                        .multilineTextAlignment(.center)
                    Button("Thử lại") {
                        viewModel.loadPages(for: viewModel.currentChapter)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding()
            } else {
                readerContent
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
            viewModel.scheduleSaveProgress()
            viewModel.prefetchUpcomingPages()
        }
        .onDisappear {
            viewModel.saveProgress()
        }
        .sheet(isPresented: $viewModel.showChapterList) {
            chapterListSheet
        }
    }

    // ── Nội dung đọc theo chế độ ──
    @ViewBuilder
    private var readerContent: some View {
        if viewModel.readingMode == .webtoon {
            // Cuộn dọc liên tục (Webtoon)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: viewModel.pageSpacing) {
                        ForEach(viewModel.pages) { page in
                            MangaWebtoonPage(page: page, theme: viewModel.readerTheme)
                                .id(page.index)
                                .onAppear {
                                    // Chỉ cập nhật vị trí hiện tại, KHÔNG ép cuộn ngược lại
                                    viewModel.currentPageIndex = page.index
                                }
                        }
                    }
                }
                .onTapGesture {
                    viewModel.toggleControls()
                }
                .onAppear {
                    webtoonScrollProxy = proxy
                    restoreInitialPosition(using: proxy)
                }
                .onChange(of: viewModel.pages.count) { _ in
                    restoreInitialPosition(using: proxy)
                }
            }
        } else {
            // Lật từng trang (Paged Manga) + tap-zone trái/giữa/phải
            TabView(selection: $viewModel.currentPageIndex) {
                ForEach(viewModel.pages) { page in
                    MangaPagedPage(page: page, theme: viewModel.readerTheme) { fraction in
                        viewModel.handlePageTap(horizontalFraction: fraction)
                    }
                    .tag(page.index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    /// Khôi phục vị trí trang đã lưu (đọc tiếp) đúng 1 lần sau khi trang được tải.
    private func restoreInitialPosition(using proxy: ScrollViewProxy) {
        guard !didRestoreInitialPosition, !viewModel.pages.isEmpty else { return }
        didRestoreInitialPosition = true
        let target = min(viewModel.currentPageIndex, viewModel.pages.count - 1)
        guard target > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            proxy.scrollTo(target, anchor: .top)
        }
    }

    // ── Danh sách chương ngay trong Reader ──
    @ViewBuilder
    private var chapterListSheet: some View {
        if let chapters = viewModel.manga.chapters {
            MangaChapterPickerView(
                chapters: chapters,
                readChapterIDs: libraryStore.readChapterIDs(mangaID: viewModel.manga.id),
                onSelectChapter: { chapter in
                    viewModel.showChapterList = false
                    // Chờ sheet đóng hẳn rồi mới tải chương để tránh giật giao diện
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        didRestoreInitialPosition = false
                        viewModel.loadPages(for: chapter)
                    }
                },
                onMarkAllRead: {
                    libraryStore.markAllRead(mangaID: viewModel.manga.id, chapters: chapters)
                }
            )
            .presentationDetents([.large])
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
            .accessibilityLabel("Quay lại")

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

            // Mở danh sách chương ngay trong Reader
            if let chapters = viewModel.manga.chapters, !chapters.isEmpty {
                Button(action: { viewModel.showChapterList = true }) {
                    Image(systemName: "list.number")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Danh sách chương")
            }

            // Mode Selector
            Menu {
                ForEach(ReadingMode.allCases) { mode in
                    Button(action: { viewModel.setReadingMode(mode) }) {
                        Label(mode.rawValue, systemImage: mode.iconName)
                    }
                }

                Divider()

                Section("Chiều đọc (chế độ lật trang)") {
                    ForEach(MangaReadingDirection.allCases) { direction in
                        Button(action: { viewModel.setReadingDirection(direction) }) {
                            if viewModel.readingDirection == direction {
                                Label(direction.rawValue, systemImage: "checkmark")
                            } else {
                                Label(direction.rawValue, systemImage: direction.iconName)
                            }
                        }
                    }
                }

                Section("Màu nền") {
                    ForEach(MangaReaderTheme.allCases) { theme in
                        Button(action: { viewModel.setReaderTheme(theme) }) {
                            if viewModel.readerTheme == theme {
                                Label(theme.rawValue, systemImage: "checkmark")
                            } else {
                                Text(theme.rawValue)
                            }
                        }
                    }
                }

                if viewModel.readingMode == .webtoon {
                    Divider()
                    Section("Khoảng cách trang") {
                        ForEach([CGFloat(0), 2, 6, 12], id: \.self) { spacing in
                            Button {
                                viewModel.setPageSpacing(spacing)
                            } label: {
                                if viewModel.pageSpacing == spacing {
                                    Label("\(Int(spacing)) pt", systemImage: "checkmark")
                                } else {
                                    Text("\(Int(spacing)) pt")
                                }
                            }
                        }
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
            .accessibilityLabel("Cài đặt đọc truyện")
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
                            set: { newValue in
                                let maxIndex = max(viewModel.pages.count - 1, 0)
                                let target = min(max(Int(newValue), 0), maxIndex)
                                viewModel.currentPageIndex = target
                                // Chế độ Webtoon: Slider là nơi duy nhất chủ động cuộn,
                                // nên không còn vòng lặp giật khi người dùng tự cuộn.
                                if viewModel.readingMode == .webtoon {
                                    webtoonScrollProxy?.scrollTo(target, anchor: .top)
                                }
                            }
                        ),
                        in: 0...Double(max(viewModel.pages.count - 1, 1)),
                        step: 1
                    )
                    .tint(.red)
                    .accessibilityLabel("Trang hiện tại")
                    .accessibilityValue("Trang \(viewModel.currentPageIndex + 1) trên \(viewModel.pages.count)")

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
