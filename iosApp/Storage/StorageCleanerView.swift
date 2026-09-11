import SwiftUI

public struct StorageCleanerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = StorageCacheManager.shared
    @State private var showSuccessBanner = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.051, green: 0.051, blue: 0.051)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Circular Gauge / Hero
                        heroStorageCard
                            .padding(.top, 10)

                        // Breakdown Cards
                        breakdownSection

                        // Clean All Button
                        cleanAllButton

                        if let last = manager.lastCleanedAt {
                            Text("Dọn dẹp gần nhất: \(last.formatted(date: .omitted, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.gray)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
                }

                // Success Toast
                if showSuccessBanner {
                    VStack {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Đã dọn dẹp sạch bộ nhớ đệm!")
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(Color.green.opacity(0.3), lineWidth: 1)
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))

                        Spacer()
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Bộ Nhớ Đệm & Dung Lượng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await manager.calculateSizes() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }

    // MARK: - Hero Card

    private var heroStorageCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 12)
                    .frame(width: 150, height: 150)

                Circle()
                    .trim(from: 0, to: manager.totalCacheBytes > 0 ? 0.75 : 0.05)
                    .stroke(
                        LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 150, height: 150)

                VStack(spacing: 4) {
                    if manager.isCalculating {
                        ProgressView().tint(.cyan)
                    } else {
                        Text(manager.totalFormatted)
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Có thể dọn")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }
            }
            .padding(.top, 10)

            Text("Bộ nhớ đệm tích lũy khi đọc truyện và xem phim/live stream.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    // MARK: - Breakdown Section

    private var breakdownSection: some View {
        VStack(spacing: 12) {
            // Manga Cache
            storageItemRow(
                icon: "book.pages.fill",
                color: .orange,
                title: "Bộ nhớ đệm Truyện Tranh",
                subtitle: "Ảnh trang truyện đã nạp và lưu tạm",
                size: manager.mangaFormatted
            ) {
                Task {
                    await manager.clearManga()
                    triggerSuccessToast()
                }
            }

            // Video & IPTV Cache
            storageItemRow(
                icon: "tv.fill",
                color: .cyan,
                title: "Bộ nhớ đệm Video & IPTV",
                subtitle: "Phân đoạn đệm live stream và file tạm",
                size: manager.videoFormatted
            ) {
                Task {
                    await manager.clearVideoAndIPTV()
                    triggerSuccessToast()
                }
            }

            // System Temp
            storageItemRow(
                icon: "network",
                color: .purple,
                title: "Dữ liệu tạm hệ thống",
                subtitle: "Phản hồi API và manifest tạm thời",
                size: manager.systemFormatted,
                action: nil
            )
        }
    }

    private func storageItemRow(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        size: String,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(size)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)

                if let action {
                    Button("Xóa") {
                        action()
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.12), in: Capsule())
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    // MARK: - Clean All Button

    private var cleanAllButton: some View {
        Button {
            Task {
                await manager.clearAll()
                triggerSuccessToast()
            }
        } label: {
            HStack(spacing: 8) {
                if manager.isCleaning {
                    ProgressView().tint(.black)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                }

                Text(manager.isCleaning ? "Đang dọn dẹp..." : "Dọn Dẹp Tất Cả Bộ Nhớ Đệm")
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                manager.totalCacheBytes > 0
                ? LinearGradient(colors: [.cyan, Color(red: 0.2, green: 0.7, blue: 1.0)], startPoint: .leading, endPoint: .trailing)
                : LinearGradient(colors: [.gray, .gray.opacity(0.7)], startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .shadow(color: manager.totalCacheBytes > 0 ? Color.cyan.opacity(0.3) : .clear, radius: 10, y: 4)
        }
        .disabled(manager.isCleaning || manager.totalCacheBytes <= 0)
    }

    private func triggerSuccessToast() {
        withAnimation { showSuccessBanner = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                withAnimation { showSuccessBanner = false }
            }
        }
    }
}
