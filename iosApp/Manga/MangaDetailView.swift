import SwiftUI

// MARK: - Manga Detail View (Màn hình chi tiết truyện theo luồng Navigation)
public struct MangaDetailView: View {
    public let initialManga: MangaItem
    public let onSelectChapter: (MangaChapter, MangaItem) -> Void

    @State private var manga: MangaItem
    @State private var isLoadingDetail: Bool = false
    @State private var showChapterPicker: Bool = false
    @State private var isDescriptionExpanded: Bool = false

    @ObservedObject private var libraryStore = MangaLibraryStore.shared
    @ObservedObject private var progressStore = MangaReadingProgressStore.shared
    @ObservedObject private var addonManager = MangaAddonManager.shared

    public init(
        manga: MangaItem,
        onSelectChapter: @escaping (MangaChapter, MangaItem) -> Void
    ) {
        self.initialManga = manga
        self._manga = State(initialValue: manga)
        self.onSelectChapter = onSelectChapter
    }

    public var body: some View {
        ZStack {
            Color(red: 0.051, green: 0.051, blue: 0.051)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // ── Header Backdrop & Cover Info ──
                    headerSection

                    // ── Primary Action Buttons (Đọc từ đầu / Đọc tiếp / Theo dõi) ──
                    actionButtonsSection

                    // ── Tóm tắt nội dung ──
                    if let desc = manga.description, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        descriptionSection(desc)
                    }

                    Divider()
                        .background(Color.white.opacity(0.12))

                    // ── Danh sách các chương ──
                    chaptersSection

                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .navigationTitle(manga.title)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .tabBar)
        .task {
            await loadDetailIfNeeded()
        }
        .sheet(isPresented: $showChapterPicker) {
            if let chapters = manga.chapters {
                MangaChapterPickerView(
                    chapters: chapters,
                    readChapterIDs: libraryStore.readChapterIDs(mangaID: manga.id),
                    onSelectChapter: { chapter in
                        showChapterPicker = false
                        onSelectChapter(chapter, manga)
                    },
                    onMarkAllRead: {
                        libraryStore.markAllRead(mangaID: manga.id, chapters: chapters)
                    }
                )
                .presentationDetents([.large])
            }
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 16) {
            // Ảnh bìa
            MangaCoverImageView(urlString: manga.displayCover)
                .frame(width: 125, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)

            // Thông tin cơ bản
            VStack(alignment: .leading, spacing: 8) {
                Text(manga.title)
                    .font(.title3.bold())
                    .foregroundColor(.white)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let authors = manga.authors, !authors.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Text(authors.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }

                if let status = manga.status, !status.isEmpty {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(status.lowercased().contains("hoàn") ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(status)
                            .font(.caption.weight(.medium))
                            .foregroundColor(status.lowercased().contains("hoàn") ? .green : .orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                }

                if let genres = manga.genres, !genres.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(genres, id: \.self) { genre in
                                Text(genre)
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.85))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.purple.opacity(0.25))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Action Buttons
    private var actionButtonsSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                // Nút Đọc tiếp hoặc Đọc từ đầu
                if let progress = progressStore.progress(for: manga.id) {
                    Button {
                        onSelectChapter(progress.chapter, manga)
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Đọc tiếp \(progress.chapter.chapterName ?? progress.chapter.title)")
                                .lineLimit(1)
                        }
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [Color.red, Color(red: 0.8, green: 0.1, blue: 0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                } else if let firstChapter = firstAvailableChapter {
                    Button {
                        onSelectChapter(firstChapter, manga)
                    } label: {
                        HStack {
                            Image(systemName: "book.fill")
                            Text("Đọc từ đầu")
                        }
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [Color.red, Color(red: 0.8, green: 0.1, blue: 0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                // Nút Theo dõi truyện
                Button {
                    toggleFollow()
                } label: {
                    let isFollowing = libraryStore.isFollowing(mangaID: manga.id)
                    HStack(spacing: 6) {
                        Image(systemName: isFollowing ? "checkmark" : "plus")
                        Text(isFollowing ? "Đã lưu" : "Theo dõi")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(isFollowing ? Color.green.opacity(0.18) : Color.white.opacity(0.10))
                    .foregroundColor(isFollowing ? .green : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isFollowing ? Color.green.opacity(0.3) : Color.white.opacity(0.15), lineWidth: 1)
                    )
                }
            }
        }
    }

    // MARK: - Description
    private func descriptionSection(_ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tóm tắt nội dung")
                .font(.headline)
                .foregroundColor(.white)

            Text(desc)
                .font(.footnote)
                .foregroundColor(.gray)
                .lineSpacing(3)
                .lineLimit(isDescriptionExpanded ? nil : 4)

            if desc.count > 180 {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isDescriptionExpanded.toggle()
                    }
                }) {
                    Text(isDescriptionExpanded ? "Thu gọn" : "Xem thêm")
                        .font(.caption.bold())
                        .foregroundColor(.red)
                }
            }
        }
    }

    // MARK: - Chapters List
    private var chaptersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Danh sách chương")
                    .font(.headline)
                    .foregroundColor(.white)

                if let count = manga.chapters?.count {
                    Text("(\(count))")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                Spacer()

                if isLoadingDetail {
                    ProgressView()
                        .tint(.red)
                        .scaleEffect(0.8)
                }
            }

            if let chapters = manga.chapters, !chapters.isEmpty {
                // Hiển thị 6 chương mới nhất
                LazyVStack(spacing: 8) {
                    ForEach(chapters.prefix(6)) { ch in
                        chapterRow(ch)
                    }
                }

                if chapters.count > 6 {
                    Button {
                        showChapterPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "list.bullet.indent")
                            Text("Xem tất cả \(chapters.count) chương")
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.08))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.top, 4)
                }
            } else if !isLoadingDetail {
                Text("Không tìm thấy danh sách chương từ nguồn.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.vertical, 14)
            }
        }
    }

    private func chapterRow(_ ch: MangaChapter) -> some View {
        let isRead = libraryStore.isRead(mangaID: manga.id, chapterID: ch.id)
        return Button {
            onSelectChapter(ch, manga)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ch.title)
                        .font(.subheadline.weight(isRead ? .regular : .medium))
                        .foregroundColor(isRead ? .gray : .white)
                        .lineLimit(1)

                    if let date = ch.date, !date.isEmpty {
                        Text(date)
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.8))
                    }
                }

                Spacer()

                if isRead {
                    Text("Đã đọc")
                        .font(.caption2)
                        .foregroundColor(.green.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundColor(.gray.opacity(0.6))
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .background(Color.white.opacity(isRead ? 0.03 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers
    private var firstAvailableChapter: MangaChapter? {
        guard let chapters = manga.chapters, !chapters.isEmpty else { return nil }
        // Thường chapter 1 là cuối danh sách (nếu xếp mới nhất lên đầu) hoặc đầu danh sách
        return chapters.last
    }

    private func toggleFollow() {
        if libraryStore.isFollowing(mangaID: manga.id) {
            libraryStore.unfollow(mangaID: manga.id)
        } else {
            libraryStore.follow(manga, addonID: addonManager.activeAddon?.id ?? "")
        }
    }

    private func loadDetailIfNeeded() async {
        if manga.chapters != nil && !(manga.chapters?.isEmpty ?? true) {
            return
        }
        isLoadingDetail = true
        let matchedAddon = libraryStore.followed.first(where: { $0.sourceManga.id == manga.id }).flatMap { followed in
            addonManager.addons.first(where: { $0.id == followed.addonID })
        } ?? addonManager.activeAddon

        let detailed = await ProviderZBridge.shared.fetchDetail(
            for: manga,
            addon: matchedAddon
        )
        libraryStore.refresh(detailed)
        self.manga = detailed
        self.isLoadingDetail = false
    }
}
