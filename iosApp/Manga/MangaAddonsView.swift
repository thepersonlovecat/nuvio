import SwiftUI

/// Màn hình Quản lý Add-on Truyện Tranh (Manga Add-ons Manager)
/// Hoàn toàn độc lập và không ảnh hưởng đến các Add-on phim của Nuvio.
public struct MangaAddonsView: View {
    @ObservedObject var addonManager = MangaAddonManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var inputUrl: String = ""
    @State private var isInstalling: Bool = false
    @State private var statusMessage: String?
    @State private var isErrorMessage: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 13/255, green: 13/255, blue: 13/255)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Section 1: Thêm Add-on mới
                        installSection

                        // Section 2: Danh sách Add-ons đã cài đặt
                        installedSection

                        // Ghi chú về tính độc lập
                        isolationNote
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Nguồn truyện tranh")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Xong")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(red: 139/255, green: 92/255, blue: 246/255))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Section 1: Cài đặt Add-on mới
    private var installSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Cài đặt Add-on mới", systemImage: "plus.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .foregroundColor(.gray)
                        .font(.system(size: 14))

                    TextField("Dán link Manifest JSON hoặc Provider-Z...", text: $inputUrl)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    if !inputUrl.isEmpty {
                        Button {
                            inputUrl = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(red: 26/255, green: 26/255, blue: 26/255))
                .cornerRadius(10)

                Button {
                    Task { await handleInstall() }
                } label: {
                    HStack(spacing: 6) {
                        if isInstalling {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                        }
                        Text(isInstalling ? "Đang cài đặt..." : "Cài đặt Add-on")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        inputUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isInstalling
                            ? Color.gray.opacity(0.3)
                            : Color(red: 139/255, green: 92/255, blue: 246/255)
                    )
                    .cornerRadius(10)
                }
                .disabled(inputUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isInstalling)

                if let msg = statusMessage {
                    HStack(spacing: 6) {
                        Image(systemName: isErrorMessage ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 12))
                        Text(msg)
                            .font(.system(size: 12))
                    }
                    .foregroundColor(isErrorMessage ? .red : .green)
                    .padding(.top, 2)
                }
            }
            .padding(14)
            .background(Color(red: 20/255, green: 20/255, blue: 20/255))
            .cornerRadius(14)
        }
    }

    // MARK: - Section 2: Danh sách Add-ons đã cài đặt
    private var installedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Add-on đã cài đặt (\(addonManager.addons.count))", systemImage: "puzzlepiece.extension.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }

            VStack(spacing: 10) {
                ForEach(addonManager.addons) { addon in
                    addonCard(addon)
                }
            }
        }
    }

    private func addonCard(_ addon: MangaAddon) -> some View {
        let isActive = addonManager.activeAddonId == addon.id

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // Icon Add-on
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isActive ? Color(red: 139/255, green: 92/255, blue: 246/255).opacity(0.2) : Color.white.opacity(0.08))
                        .frame(width: 42, height: 42)

                    Image(systemName: addon.isBuiltIn ? "sparkles" : "puzzlepiece.fill")
                        .font(.system(size: 18))
                        .foregroundColor(isActive ? Color(red: 139/255, green: 92/255, blue: 246/255) : .gray)
                }

                // Thông tin Add-on
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(addon.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)

                        if addon.isBuiltIn {
                            Text("Có sẵn")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.25))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        } else {
                            Text(addon.type.displayName)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.25))
                                .foregroundColor(.purple)
                                .cornerRadius(4)
                        }

                        Spacer()

                        // Nút bật/tắt
                        Toggle("", isOn: Binding(
                            get: { addon.isEnabled },
                            set: { _ in addonManager.toggleAddon(id: addon.id) }
                        ))
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: Color(red: 139/255, green: 92/255, blue: 246/255)))
                    }

                    Text(addon.description)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .lineLimit(2)

                    // Thanh trạng thái hoạt động & Chọn làm nguồn mặc định
                    HStack {
                        Button {
                            if addon.isEnabled {
                                addonManager.selectAddon(id: addon.id)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 13))
                                Text(isActive ? "Đang sử dụng" : "Chọn nguồn này")
                                    .font(.system(size: 12, weight: isActive ? .bold : .regular))
                            }
                            .foregroundColor(isActive ? Color(red: 139/255, green: 92/255, blue: 246/255) : .gray)
                        }
                        .disabled(!addon.isEnabled)

                        Spacer()

                        if !addon.isBuiltIn {
                            Button {
                                addonManager.removeAddon(id: addon.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 13))
                                    .foregroundColor(.red.opacity(0.8))
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(12)
        .background(Color(red: 20/255, green: 20/255, blue: 20/255))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color(red: 139/255, green: 92/255, blue: 246/255).opacity(0.5) : Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Section 3: Ghi chú độc lập
    private var isolationNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundColor(.green.opacity(0.8))
                .font(.system(size: 14))

            Text("Các Add-on truyện tranh hoạt động riêng biệt trong tab Truyện và không ảnh hưởng đến trang Home hay hệ thống phim của Nuvio.")
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
    }

    // MARK: - Xử lý cài đặt
    private func handleInstall() async {
        isInstalling = true
        statusMessage = nil
        isErrorMessage = false

        do {
            let installed = try await addonManager.installAddon(from: inputUrl)
            statusMessage = "Đã cài đặt thành công: \(installed.name)"
            inputUrl = ""
        } catch {
            isErrorMessage = true
            statusMessage = error.localizedDescription
        }

        isInstalling = false
    }
}
