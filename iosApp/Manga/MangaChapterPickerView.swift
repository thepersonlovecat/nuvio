import Foundation
import SwiftUI

private enum MangaChapterSort: String, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst
    case numberAscending
    case numberDescending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newestFirst: return "Mới nhất → cũ nhất"
        case .oldestFirst: return "Cũ nhất → mới nhất"
        case .numberAscending: return "Số chương nhỏ → lớn"
        case .numberDescending: return "Số chương lớn → nhỏ"
        }
    }
}

private extension MangaChapter {
    /// Providers use different labels ("12", "Chương 12.5", or a title).
    /// Extracting the first number makes chapter ordering numeric rather than lexical.
    var numericChapterNumber: Double? {
        let value = chapterName?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? title
        guard let range = value.range(of: #"\d+(?:[.,]\d+)?"#, options: .regularExpression) else {
            return nil
        }
        return Double(value[range].replacingOccurrences(of: ",", with: "."))
    }

    var chapterSearchText: String {
        [chapterName, title].compactMap { $0 }.joined(separator: " ")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// A picker designed for series with hundreds or thousands of chapters.
/// It renders a page at a time, while search and sorting apply to the
/// complete chapter list provided by the active manga add-on.
struct MangaChapterPickerView: View {
    private let chapters: [MangaChapter]
    private let onSelectChapter: (MangaChapter) -> Void
    private let pageSize = 100

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var sort: MangaChapterSort = .newestFirst
    @State private var visibleLimit = 100
    @State private var jumpInput = ""
    @State private var jumpFeedback: String?
    @State private var jumpTargetID: String?

    init(chapters: [MangaChapter], onSelectChapter: @escaping (MangaChapter) -> Void) {
        self.chapters = chapters
        self.onSelectChapter = onSelectChapter
    }

    private var matchingChapters: [(chapter: MangaChapter, sourceIndex: Int)] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = chapters.enumerated().compactMap { index, chapter -> (MangaChapter, Int)? in
            guard trimmedQuery.isEmpty || chapter.chapterSearchText.localizedCaseInsensitiveContains(trimmedQuery) else {
                return nil
            }
            return (chapter, index)
        }

        return matching.sorted { lhs, rhs in
            switch sort {
            case .newestFirst:
                return lhs.1 < rhs.1
            case .oldestFirst:
                return lhs.1 > rhs.1
            case .numberAscending:
                return compareChapterNumbers(lhs, rhs, ascending: true)
            case .numberDescending:
                return compareChapterNumbers(lhs, rhs, ascending: false)
            }
        }.map { (chapter: $0.0, sourceIndex: $0.1) }
    }

    private var visibleChapters: [MangaChapter] {
        matchingChapters.prefix(visibleLimit).map { $0.chapter }
    }

    private func compareChapterNumbers(
        _ lhs: (MangaChapter, Int),
        _ rhs: (MangaChapter, Int),
        ascending: Bool
    ) -> Bool {
        switch (lhs.0.numericChapterNumber, rhs.0.numericChapterNumber) {
        case let (left?, right?) where left != right:
            return ascending ? left < right : left > right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.1 < rhs.1
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        searchAndSortControls

                        Text("Hiển thị \(visibleChapters.count) / \(matchingChapters.count) chương")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if visibleChapters.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                Text("Không tìm thấy chương phù hợp")
                                    .font(.subheadline.weight(.medium))
                                Text("Thử tìm theo số hoặc tên chương khác.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                                .padding(.top, 64)
                        } else {
                            ForEach(visibleChapters) { chapter in
                                Button {
                                    onSelectChapter(chapter)
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(chapter.title)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                            if let date = chapter.date, !date.isEmpty {
                                                Text(date)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.bold))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(Color.primary.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .id(chapter.id)
                            }

                            if visibleChapters.count < matchingChapters.count {
                                Button {
                                    visibleLimit += pageSize
                                } label: {
                                    Label("Tải thêm \(min(pageSize, matchingChapters.count - visibleChapters.count)) chương", systemImage: "plus")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(16)
                }
                .onChange(of: jumpTargetID) { targetID in
                    guard let targetID else { return }
                    withAnimation {
                        proxy.scrollTo(targetID, anchor: .center)
                    }
                }
            }
            .navigationTitle("Danh sách chương")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }

    private var searchAndSortControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Tìm tên hoặc số chương", text: $query)
                    .textInputAutocapitalization(.never)
                    .onChange(of: query) { _ in visibleLimit = pageSize }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(11)
            .background(Color.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 10) {
                Menu {
                    ForEach(MangaChapterSort.allCases) { option in
                        Button {
                            sort = option
                            visibleLimit = pageSize
                        } label: {
                            if sort == option {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                } label: {
                    Label(sort.title, systemImage: "arrow.up.arrow.down")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                TextField("Nhảy tới chap", text: $jumpInput)
                    .keyboardType(.decimalPad)
                    .padding(10)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                Button("Đi tới") { jumpToChapter() }
                    .buttonStyle(.borderedProminent)
            }

            if let jumpFeedback {
                Text(jumpFeedback)
                    .font(.caption)
                    .foregroundColor(jumpFeedback.hasPrefix("Không") ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func jumpToChapter() {
        let normalized = jumpInput.replacingOccurrences(of: ",", with: ".")
        guard let requested = Double(normalized) else {
            jumpFeedback = "Nhập số chương hợp lệ, ví dụ 12 hoặc 12.5."
            return
        }

        query = ""
        guard let index = matchingChapters.firstIndex(where: {
            guard let number = $0.chapter.numericChapterNumber else { return false }
            return abs(number - requested) < 0.000_001
        }) else {
            jumpFeedback = "Không tìm thấy chương \(jumpInput)."
            return
        }

        let target = matchingChapters[index].chapter
        visibleLimit = max(pageSize, ((index / pageSize) + 1) * pageSize)
        jumpFeedback = "Đã tìm thấy \(target.title)."
        jumpTargetID = target.id
    }
}
