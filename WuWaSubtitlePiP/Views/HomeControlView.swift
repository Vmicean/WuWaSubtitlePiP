import ReplayKit
import SwiftUI
import UIKit

public struct HomeControlView: View {
    @Bindable public var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                livePiPPreviewCard
                stepOneOfflinePackCard
                stepTwoPiPControlCard
                stepThreeBroadcastCard
                diagnosticsCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(WuWaTheme.obsidianBackground.ignoresSafeArea())
        .navigationTitle("WuWa Dịch PiP")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Live PiP Inline Host Card

    private var livePiPPreviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Khung phụ đề trực tiếp (960 × 260)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WuWaTheme.gold)

                Spacer()

                statusDotLabel(
                    title: appState.pipManager.isPiPActive ? "Đang nổi PiP" : "Sẵn sàng",
                    color: appState.pipManager.isPiPActive ? WuWaTheme.emerald : WuWaTheme.gold
                )
            }

            PiPInlineHostRepresentable(displayLayer: appState.pipManager.displayLayer)
                .aspectRatio(960.0 / 260.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(WuWaTheme.gold.opacity(0.45), lineWidth: 1)
                )

            if let banner = appState.statusBannerMessage {
                Text(banner)
                    .font(.caption)
                    .foregroundStyle(WuWaTheme.gold)
            } else {
                Text("Khi chuyển sang Wuthering Waves, cửa sổ phụ đề sẽ tự động thu nhỏ nổi trên màn hình và không tắt tiếng game.")
                    .font(.caption)
                    .foregroundStyle(WuWaTheme.textSecondary)
            }
        }
        .padding(16)
        .background(WuWaTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(WuWaTheme.gold.opacity(0.22), lineWidth: 1)
        )
    }

    // MARK: - Step 1: Offline Language Pack

    private var stepOneOfflinePackCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                stepBadge(number: "1", title: "Gói dịch ngoại tuyến Anh → Việt")
                Spacer()
                packStatusBadge
            }

            Text(appState.translationService.packStatus.vietnameseLabel)
                .font(.footnote)
                .foregroundStyle(WuWaTheme.textSecondary)

            HStack(spacing: 10) {
                Button {
                    appState.requestOfflinePackDownload()
                } label: {
                    HStack(spacing: 8) {
                        if appState.translationService.isDownloadingPack {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Image(systemName: appState.translationService.packStatus.isReady ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                        }
                        Text(
                            appState.translationService.packStatus.isReady
                                ? "Kiểm tra lại gói Anh – Việt"
                                : "Tải gói dịch ngoại tuyến Anh – Việt"
                        )
                        .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(WuWaTheme.gold)
                    .foregroundStyle(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(appState.translationService.isDownloadingPack)

                Button {
                    appState.refreshOfflinePackStatus()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WuWaTheme.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(WuWaTheme.elevatedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .accessibilityLabel("Làm mới trạng thái gói dịch")
            }

            if let errorMessage = appState.translationService.lastErrorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(WuWaTheme.crimson)
            }
        }
        .padding(16)
        .background(WuWaTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Step 2: Floating PiP Window

    private var stepTwoPiPControlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                stepBadge(number: "2", title: "Cửa sổ phụ đề nổi (PiP)")
                Spacer()
                statusDotLabel(
                    title: appState.pipManager.isPiPActive ? "Đang chạy" : "Đang tắt",
                    color: appState.pipManager.isPiPActive ? WuWaTheme.emerald : WuWaTheme.textSecondary
                )
            }

            HStack(spacing: 10) {
                Button {
                    appState.pipManager.togglePictureInPicture()
                } label: {
                    Label(
                        appState.pipManager.isPiPActive ? "Tắt cửa sổ PiP" : "Bật cửa sổ phụ đề PiP",
                        systemImage: appState.pipManager.isPiPActive ? "pip.exit" : "pip.enter"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(appState.pipManager.isPiPActive ? WuWaTheme.crimson : WuWaTheme.gold)
                    .foregroundStyle(appState.pipManager.isPiPActive ? Color.white : Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Button {
                    appState.runDemoSubtitleOnPiP()
                } label: {
                    Text("Chạy thử phụ đề trên PiP")
                        .font(.footnote.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(WuWaTheme.elevatedSurface)
                        .foregroundStyle(WuWaTheme.gold)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(WuWaTheme.gold.opacity(0.35), lineWidth: 1)
                        )
                }
            }

            if let pipError = appState.pipManager.lastErrorMessage {
                Text(pipError)
                    .font(.caption)
                    .foregroundStyle(WuWaTheme.crimson)
            }
        }
        .padding(16)
        .background(WuWaTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Step 3: ReplayKit System Broadcast Picker

    private var stepThreeBroadcastCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                stepBadge(number: "3", title: "Bắt đầu quét màn hình game")
                Spacer()
                statusDotLabel(
                    title: appState.broadcastStatus.state == .active ? "Đang quét" : "Chưa bật",
                    color: appState.broadcastStatus.state == .active ? WuWaTheme.emerald : WuWaTheme.amber
                )
            }

            Text("Nhấn vào biểu tượng phát sóng bên dưới, chọn 'WuWaBroadcastExtension' rồi bấm Bắt đầu phát sóng. Sau đó mở Wuthering Waves để chơi.")
                .font(.footnote)
                .foregroundStyle(WuWaTheme.textSecondary)

            HStack(spacing: 14) {
                BroadcastPickerRepresentable(
                    preferredExtensionBundleID: appState.resolvedBroadcastExtensionBundleID
                )
                .frame(width: 56, height: 56)
                .background(WuWaTheme.gold.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(WuWaTheme.gold.opacity(0.55), lineWidth: 1.2)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Chạm nút Phát màn hình bên trái")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WuWaTheme.textPrimary)

                    Text("Extension đích: \(appState.resolvedBroadcastExtensionBundleID)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(WuWaTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
            }
            .padding(12)
            .background(WuWaTheme.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(16)
        .background(WuWaTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Live Diagnostics Card

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Chẩn đoán trực tiếp")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WuWaTheme.gold)

            diagnosticRow(
                label: "Kênh truyền IPC",
                value: appState.activeTransportDescription
            )
            diagnosticRow(
                label: "Trạng thái App Group",
                value: appState.appGroupDiagnosticDescription
            )
            diagnosticRow(
                label: "Phát màn hình (Broadcast)",
                value: appState.broadcastStatus.state.vietnameseLabel
            )
            diagnosticRow(
                label: "Cửa sổ nổi (PiP)",
                value: appState.pipManager.isPiPActive
                    ? "Đang hoạt động (\(appState.pipManager.renderedFrameCount) khung)"
                    : (appState.pipManager.isPiPPossible ? "Sẵn sàng kích hoạt" : "Đang khởi tạo...")
            )
            diagnosticRow(
                label: "Độ trễ OCR / Tổng dịch",
                value: "\(appState.broadcastStatus.lastOCRDurationMs) ms / \(appState.lastTotalLatencyMs) ms"
            )
            diagnosticRow(
                label: "RAM Extension & Khung hình",
                value: String(
                    format: "%.1f MB · Xử lý %d · Bỏ qua %d",
                    appState.broadcastStatus.estimatedMemoryMB,
                    appState.broadcastStatus.framesProcessed,
                    appState.broadcastStatus.framesDropped
                )
            )
        }
        .padding(16)
        .background(WuWaTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Helper Subviews

    private func stepBadge(number: String, title: String) -> some View {
        HStack(spacing: 8) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.black)
                .frame(width: 22, height: 22)
                .background(WuWaTheme.gold)
                .clipShape(Circle())

            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WuWaTheme.textPrimary)
        }
    }

    private var packStatusBadge: some View {
        let color: Color
        let text: String

        switch appState.translationService.packStatus {
        case .installed:
            color = WuWaTheme.emerald
            text = "Sẵn sàng"
        case .checking:
            color = WuWaTheme.gold
            text = "Đang kiểm tra"
        case .downloadRequired, .unknown:
            color = WuWaTheme.amber
            text = "Cần tải"
        case .unsupported, .error:
            color = WuWaTheme.crimson
            text = "Lỗi"
        }

        return statusDotLabel(title: text, color: color)
    }

    private func statusDotLabel(title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.14))
        .clipShape(Capsule())
    }

    private func diagnosticRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(WuWaTheme.textSecondary)
                .frame(width: 140, alignment: .leading)

            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(WuWaTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// UIViewRepresentable wrapper for ReplayKit's RPSystemBroadcastPickerView.
/// Dynamically computes preferredExtension from the active runtime bundle identifier
/// so it remains bound even after SideStore / AltStore rewrites the bundle ID.
public struct BroadcastPickerRepresentable: UIViewRepresentable {
    public let preferredExtensionBundleID: String

    public init(preferredExtensionBundleID: String) {
        self.preferredExtensionBundleID = preferredExtensionBundleID
    }

    public func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 56, height: 56))
        picker.showsMicrophoneButton = false
        picker.preferredExtension = resolvedExtensionID()
        picker.tintColor = UIColor(red: 0.902, green: 0.788, blue: 0.478, alpha: 1.0)
        styleInternalButton(in: picker)
        return picker
    }

    public func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        uiView.showsMicrophoneButton = false
        uiView.preferredExtension = resolvedExtensionID()
        styleInternalButton(in: uiView)
    }

    private func resolvedExtensionID() -> String {
        if !preferredExtensionBundleID.isEmpty {
            return preferredExtensionBundleID
        }
        return (Bundle.main.bundleIdentifier ?? "com.wuwatranslator.app") + ".BroadcastExtension"
    }

    private func styleInternalButton(in picker: RPSystemBroadcastPickerView) {
        for subview in picker.subviews {
            if let button = subview as? UIButton {
                button.imageView?.tintColor = UIColor(red: 0.902, green: 0.788, blue: 0.478, alpha: 1.0)
                button.contentHorizontalAlignment = .center
                button.contentVerticalAlignment = .center
            }
        }
    }
}
