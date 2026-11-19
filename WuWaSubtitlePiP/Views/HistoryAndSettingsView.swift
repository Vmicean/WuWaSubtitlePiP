import SwiftUI
import UIKit

public struct HistoryAndSettingsView: View {
    @Bindable public var appState: AppState

    @State private var searchQuery: String = ""
    @State private var copiedEntryID: UUID?

    public init(appState: AppState) {
        self.appState = appState
    }

    private var filteredHistory: [TranslatedHistoryEntry] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return appState.history
        }
        return appState.history.filter { entry in
            entry.translatedVietnamese.localizedCaseInsensitiveContains(query)
                || entry.originalEnglish.localizedCaseInsensitiveContains(query)
                || (entry.speaker?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    public var body: some View {
        List {
            pipAndOCRSettingsSection
            dialogueHistorySection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(WuWaTheme.obsidianBackground.ignoresSafeArea())
        .navigationTitle("Lịch sử & Cài đặt")
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $searchQuery,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Tìm tiếng Việt, tiếng Anh hoặc tên nhân vật..."
        )
    }

    // MARK: - Settings Section

    private var pipAndOCRSettingsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Cỡ chữ phụ đề PiP")
                        .foregroundStyle(WuWaTheme.textPrimary)
                    Spacer()
                    Text("\(Int(appState.appearance.fontSize.rounded())) pt")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(WuWaTheme.gold)
                }
                Slider(value: $appState.appearance.fontSize, in: 16...36, step: 1)
                    .tint(WuWaTheme.gold)
            }
            .listRowBackground(WuWaTheme.cardSurface)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Độ mờ nền khung phụ đề")
                        .foregroundStyle(WuWaTheme.textPrimary)
                    Spacer()
                    Text("\(Int((appState.appearance.backgroundOpacity * 100).rounded()))%")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(WuWaTheme.gold)
                }
                Slider(value: $appState.appearance.backgroundOpacity, in: 0.55...1.0, step: 0.01)
                    .tint(WuWaTheme.gold)
            }
            .listRowBackground(WuWaTheme.cardSurface)

            Toggle(isOn: $appState.appearance.showOriginalEnglish) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hiển thị kèm câu gốc tiếng Anh")
                        .foregroundStyle(WuWaTheme.textPrimary)
                    Text("In dòng tiếng Anh nhỏ phía dưới bản dịch tiếng Việt trên cửa sổ PiP.")
                        .font(.caption)
                        .foregroundStyle(WuWaTheme.textSecondary)
                }
            }
            .tint(WuWaTheme.gold)
            .listRowBackground(WuWaTheme.cardSurface)

            Toggle(isOn: $appState.appearance.enableWuWaGlossary) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bật từ điển thuật ngữ Wuthering Waves")
                        .foregroundStyle(WuWaTheme.textPrimary)
                    Text("Chuẩn hóa hơn 130 thuật ngữ như Cộng Hưởng Giả, Tàn Tượng, Tuế Chủ, Bi Minh.")
                        .font(.caption)
                        .foregroundStyle(WuWaTheme.textSecondary)
                }
            }
            .tint(WuWaTheme.gold)
            .listRowBackground(WuWaTheme.cardSurface)

            Toggle(isOn: $appState.appearance.ocrAccurateMode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chế độ OCR Chính xác cao")
                        .foregroundStyle(WuWaTheme.textPrimary)
                    Text("Tắt = Nhanh (nhẹ RAM nhất). Bật = Chính xác cao hơn cho chữ nhỏ hoặc nền sáng.")
                        .font(.caption)
                        .foregroundStyle(WuWaTheme.textSecondary)
                }
            }
            .tint(WuWaTheme.gold)
            .listRowBackground(WuWaTheme.cardSurface)
        } header: {
            Text("Cài đặt hiển thị PiP & nhận diện OCR")
                .foregroundStyle(WuWaTheme.gold)
        }
    }

    // MARK: - History Section

    private var dialogueHistorySection: some View {
        Section {
            if filteredHistory.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.title2)
                        .foregroundStyle(WuWaTheme.textSecondary)
                    Text(
                        appState.history.isEmpty
                            ? "Chưa có câu hội thoại nào được dịch"
                            : "Không tìm thấy câu thoại khớp từ khóa"
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(WuWaTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .listRowBackground(WuWaTheme.cardSurface)
            } else {
                ForEach(filteredHistory) { entry in
                    historyRow(for: entry)
                        .listRowBackground(WuWaTheme.cardSurface)
                }
            }
        } header: {
            HStack {
                Text("Lịch sử hội thoại (\(appState.history.count)/\(AppState.maxHistoryEntries))")
                    .foregroundStyle(WuWaTheme.gold)
                Spacer()
                if !appState.history.isEmpty {
                    Button("Xóa lịch sử") {
                        appState.clearHistory()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WuWaTheme.crimson)
                }
            }
        }
    }

    private func historyRow(for entry: TranslatedHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                if let speaker = entry.speaker, !speaker.isEmpty {
                    Text(speaker)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(WuWaTheme.gold)
                        .clipShape(Capsule())
                }

                if entry.usedGlossary {
                    Text("Từ điển WuWa")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WuWaTheme.gold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(WuWaTheme.goldMuted)
                        .clipShape(Capsule())
                }

                Spacer()

                Text(entry.timestamp, style: .time)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(WuWaTheme.textSecondary)
            }

            Text(entry.translatedVietnamese)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WuWaTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(entry.originalEnglish)
                .font(.caption)
                .foregroundStyle(WuWaTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button {
                    copyEntry(entry)
                } label: {
                    Label(
                        copiedEntryID == entry.id ? "Đã sao chép" : "Sao chép",
                        systemImage: copiedEntryID == entry.id ? "checkmark" : "doc.on.doc"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(copiedEntryID == entry.id ? WuWaTheme.emerald : WuWaTheme.gold)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    private func copyEntry(_ entry: TranslatedHistoryEntry) {
        let prefix = entry.speaker.map { "\($0): " } ?? ""
        UIPasteboard.general.string = "\(prefix)\(entry.translatedVietnamese)\n(\(entry.originalEnglish))"
        copiedEntryID = entry.id

        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if copiedEntryID == entry.id {
                copiedEntryID = nil
            }
        }
    }
}
