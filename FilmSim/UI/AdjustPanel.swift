import SwiftUI

// MARK: - 参数面板

struct AdjustPanel: View {
    @ObservedObject var session: CameraSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("当前快门")
                        Spacer()
                        Text(session.shutter.label)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Picker("ISO", selection: $session.isoMode) {
                        ForEach(ISOMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if session.isoMode == .manual {
                        sliderRow("ISO 值",
                                  value: $session.manualISO,
                                  in: 25...3200,
                                  format: "%.0f")
                    }

                    sliderRow("曝光补偿",
                              value: $session.exposureBias,
                              in: -3...3,
                              format: "%+.1f EV")
                } header: {
                    Text("曝光")
                } footer: {
                    Text("快门在取景器下方的刻度拨盘上调整。选定固定快门后曝光会被锁定；只把 ISO 设为手动时，快门会沿用当前自动值。")
                }

                Section {
                    Picker("胶片", selection: $session.look.stock) {
                        ForEach(FilmStock.allCases) { stock in
                            Text("\(stock.name) · \(stock.chineseName)").tag(stock)
                        }
                    }

                    sliderRow("颗粒", value: $session.look.grain, in: 0...2, format: "%.1f×")
                    sliderRow("褪色", value: $session.look.fade, in: 0...1, format: "%.0f%%", displayScale: 100)
                    sliderRow("暗角", value: $session.look.vignette, in: 0...2, format: "%.1f×")
                    sliderRow("饱和", value: $session.look.saturation, in: 0...2, format: "%.1f×")

                    sliderRow("白平衡 R",
                              value: Binding(
                                get: { Double(session.look.wbShift.x) },
                                set: { session.look.wbShift.x = CGFloat($0) }
                              ),
                              in: -1...1,
                              format: "%+.2f")

                    sliderRow("白平衡 B",
                              value: Binding(
                                get: { Double(session.look.wbShift.y) },
                                set: { session.look.wbShift.y = CGFloat($0) }
                              ),
                              in: -1...1,
                              format: "%+.2f")
                } header: {
                    Text("胶片模拟")
                } footer: {
                    Text(session.look.stock.profile.tagline)
                }

                Section("信息") {
                    LabeledContent("设备 Apple Log", value: session.appleLogSupported ? "支持" : "不支持")
                    LabeledContent("手动曝光", value: session.supportsCustomExposure ? "支持" : "不支持")
                    LabeledContent("当前镜头", value: session.isFrontCamera ? "前置" : "后置")
                }
            }
            .navigationTitle("参数")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("重置") {
                        reset()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func sliderRow(_ title: String,
                           value: Binding<Double>,
                           in range: ClosedRange<Double>,
                           format: String,
                           displayScale: Double = 1) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue * displayScale))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func reset() {
        let stock = session.look.stock
        session.look = FilmLook(stock: stock)
        session.exposureBias = 0
        session.isoMode = .auto
    }
}

// MARK: - 说明页

struct InfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    block(
                        title: "它是什么",
                        body: "一台把富士胶片风格直接烘焙进取景器的相机。取景时就已经套好胶片曲线、颗粒和暗角，按下快门保存的就是这张「成片」，不需要后期再套滤镜。"
                    )

                    block(
                        title: "快门拨盘怎么用",
                        body: "取景器下方的刻度盘就是快门。左右拖动，拨到 A 是自动曝光，拨到 1/8000…1 秒则是手动快门：App 会调用 setExposureModeCustom 把曝光时间真正锁死。低于 1/30 秒的慢门受机身帧率限制，标题栏会显示实际生效的时长。"
                    )

                    block(
                        title: "Apple Log",
                        body: "在「视频」模式下打开 APPLE LOG，录制会切到 BT.2020 / 10-bit 的 Apple Log，方便后期套 LUT。取景器里看到的是近似还原，不是最终画面的精确还原。需要 iPhone 15 Pro 及更新机型。"
                    )

                    block(
                        title: "隐私",
                        body: "所有处理都在本机完成，不上传任何照片、视频或相机画面。App 只申请相机、麦克风和「添加到相册」权限。"
                    )

                    block(
                        title: "拍摄建议",
                        body: "手动快门下曝光被固定，画面亮度只跟光线有关；暗处可以把 ISO 调高，或者拨回 A 让机身自己算。VELVIA 适合风光，ASTIA 拍人，CLASSIC CHROME 适合阴天和街拍。"
                    )
                }
                .padding(20)
            }
            .navigationTitle("关于")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func block(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(body)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
