import SwiftUI

public struct ROICalibrationView: View {
    @Bindable public var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    private var topEdge: Double {
        appState.roi.y
    }

    private var bottomEdge: Double {
        appState.roi.y + appState.roi.height
    }

    private var leftEdge: Double {
        appState.roi.x
    }

    private var rightEdge: Double {
        appState.roi.x + appState.roi.width
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                phoneLandscapeMockupCard
                quickPresetButtonsCard
                edgeSlidersCard
                coordinatesInfoCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(WuWaTheme.obsidianBackground.ignoresSafeArea())
        .navigationTitle("Căn chỉnh vùng quét")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - 19.5:9 Landscape iPhone 14 Pro Max Mockup

    private var phoneLandscapeMockupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mô phỏng màn hình ngang iPhone 14 Pro Max (19.5:9)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WuWaTheme.gold)

            Text("Khung màu vàng là khu vực Vision OCR đọc chữ. Giữ khung gọn quanh hộp thoại sẽ giúp dịch nhanh hơn và tiết kiệm RAM dưới 25 MB.")
                .font(.caption)
                .foregroundStyle(WuWaTheme.textSecondary)

            GeometryReader { proxy in
                let size = proxy.size
                let roiRect = CGRect(
                    x: appState.roi.x * size.width,
                    y: appState.roi.y * size.height,
                    width: appState.roi.width * size.width,
                    height: appState.roi.height * size.height
                )

                ZStack(alignment: .topLeading) {
                    // Simulated Wuthering Waves dark landscape backdrop.
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.11, blue: 0.18),
                            Color(red: 0.05, green: 0.07, blue: 0.12),
                            Color(red: 0.03, green: 0.04, blue: 0.07)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    // Dynamic Island indicator on left side (landscape orientation).
                    Capsule()
                        .fill(Color.black)
                        .frame(width: 9, height: 34)
                        .position(x: 11, y: size.height / 2)

                    // Simulated top-right WuWa HUD controls (filtered out by DialogueTextCleaner).
                    HStack(spacing: 6) {
                        hudPill("Auto")
                        hudPill("Skip")
                        hudPill("Log")
                    }
                    .padding(.top, 8)
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                    // Simulated dialogue choice buttons in mid-right zone.
                    VStack(alignment: .trailing, spacing: 4) {
                        choiceChip("Let us investigate the Tacet Field.")
                        choiceChip("Tell me more about the Sentinel.")
                    }
                    .padding(.trailing, 18)
                    .position(x: size.width * 0.72, y: size.height * 0.56)

                    // Simulated bottom Wuthering Waves dialogue box.
                    VStack(spacing: 3) {
                        Text("Yangyang")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(WuWaTheme.gold)
                        Text("Rover, a Tacet Field just erupted near Jinzhou! Watch out for Overclocking.")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.92))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 26)
                    }
                    .frame(width: size.width * 0.82)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .position(x: size.width * 0.50, y: size.height * 0.82)

                    // Active ROI selection overlay.
                    Rectangle()
                        .fill(WuWaTheme.gold.opacity(0.16))
                        .frame(width: roiRect.width, height: roiRect.height)
                        .overlay(
                            Rectangle()
                                .strokeBorder(
                                    WuWaTheme.gold,
                                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                                )
                        )
                        .position(x: roiRect.midX, y: roiRect.midY)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                )
            }
            .aspectRatio(19.5 / 9.0, contentMode: .fit)
        }
        .padding(16)
        .background(WuWaTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(WuWaTheme.gold.opacity(0.22), lineWidth: 1)
        )
    }

    // MARK: - Presets

    private var quickPresetButtonsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mẫu vùng quét nhanh")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WuWaTheme.textPrimary)

            HStack(spacing: 10) {
                presetButton(
                    title: "Khung thoại WuWa mặc định",
                    subtitle: "Hội thoại đáy màn hình",
                    preset: .wuWaDialogueDefault
                )
                presetButton(
                    title: "Khung thoại + Lựa chọn",
                    subtitle: "Quét thêm nhánh trả lời",
                    preset: .wuWaDialogueWithChoices
                )
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

    private func presetButton(title: String, subtitle: String, preset: SubtitleROI) -> some View {
        let isSelected = appState.roi == preset
        return Button {
            appState.applyROIPreset(preset)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(isSelected ? Color.black : WuWaTheme.textPrimary)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.black.opacity(0.75) : WuWaTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(isSelected ? WuWaTheme.gold : WuWaTheme.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? WuWaTheme.gold : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    // MARK: - Edge Sliders

    private var edgeSlidersCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Tinh chỉnh 4 cạnh vùng quét")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WuWaTheme.textPrimary)
                Spacer()
                Button("Khôi phục mặc định") {
                    appState.applyROIPreset(.wuWaDialogueDefault)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(WuWaTheme.gold)
            }

            edgeSlider(
                label: "Cạnh trên (Top)",
                value: Binding(
                    get: { topEdge },
                    set: { newTop in
                        let clampedTop = min(bottomEdge - 0.10, max(0.0, newTop))
                        appState.roi = SubtitleROI(
                            x: leftEdge,
                            y: clampedTop,
                            width: rightEdge - leftEdge,
                            height: bottomEdge - clampedTop
                        )
                    }
                )
            )

            edgeSlider(
                label: "Cạnh dưới (Bottom)",
                value: Binding(
                    get: { bottomEdge },
                    set: { newBottom in
                        let clampedBottom = max(topEdge + 0.10, min(1.0, newBottom))
                        appState.roi = SubtitleROI(
                            x: leftEdge,
                            y: topEdge,
                            width: rightEdge - leftEdge,
                            height: clampedBottom - topEdge
                        )
                    }
                )
            )

            edgeSlider(
                label: "Cạnh trái (Left)",
                value: Binding(
                    get: { leftEdge },
                    set: { newLeft in
                        let clampedLeft = min(rightEdge - 0.12, max(0.0, newLeft))
                        appState.roi = SubtitleROI(
                            x: clampedLeft,
                            y: topEdge,
                            width: rightEdge - clampedLeft,
                            height: bottomEdge - topEdge
                        )
                    }
                )
            )

            edgeSlider(
                label: "Cạnh phải (Right)",
                value: Binding(
                    get: { rightEdge },
                    set: { newRight in
                        let clampedRight = max(leftEdge + 0.12, min(1.0, newRight))
                        appState.roi = SubtitleROI(
                            x: leftEdge,
                            y: topEdge,
                            width: clampedRight - leftEdge,
                            height: bottomEdge - topEdge
                        )
                    }
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

    private func edgeSlider(label: String, value: Binding<Double>) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(WuWaTheme.textSecondary)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(WuWaTheme.gold)
            }
            Slider(value: value, in: 0.0...1.0, step: 0.01)
                .tint(WuWaTheme.gold)
        }
    }

    // MARK: - Coordinate Readout

    private var coordinatesInfoCard: some View {
        let vision = appState.roi.visionRect
        return VStack(alignment: .leading, spacing: 8) {
            Text("Tọa độ chuẩn hóa gửi sang Broadcast Extension")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WuWaTheme.gold)

            Text(
                String(
                    format: "UI (gốc trên-trái): x=%.2f, y=%.2f, w=%.2f, h=%.2f",
                    appState.roi.x,
                    appState.roi.y,
                    appState.roi.width,
                    appState.roi.height
                )
            )
            .font(.caption.monospaced())
            .foregroundStyle(WuWaTheme.textPrimary)

            Text(
                String(
                    format: "Vision ROI (gốc dưới-trái): x=%.2f, y=%.2f, w=%.2f, h=%.2f",
                    vision.origin.x,
                    vision.origin.y,
                    vision.size.width,
                    vision.size.height
                )
            )
            .font(.caption.monospaced())
            .foregroundStyle(WuWaTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(WuWaTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func hudPill(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.75))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.45))
            .clipShape(Capsule())
    }

    private func choiceChip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
