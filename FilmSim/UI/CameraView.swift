import SwiftUI
import UIKit

struct CameraView: View {
    @StateObject private var session = CameraSession()
    @State private var showAdjust = false
    @State private var showInfo = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            previewContainer

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                if let message = session.statusMessage {
                    statusBanner(message)
                }
                bottomPanel
            }

            if session.permissionDenied {
                permissionView
            }

            if let toast = session.toast {
                toastView(toast)
            }
        }
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.2), value: session.toast)
        .animation(.easeInOut(duration: 0.2), value: session.permissionDenied)
        .sheet(isPresented: $showAdjust) {
            AdjustPanel(session: session)
        }
        .sheet(isPresented: $showInfo) {
            InfoSheet()
        }
        .onAppear {
            session.start()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                session.start()
            case .background:
                session.stop()
            default:
                break
            }
        }
    }

    // MARK: - 取景器

    private var previewContainer: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                MetalPreview(renderer: session.renderer, look: session.previewLook) { renderer in
                    session.attach(preview: renderer)
                }
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            session.focus(atViewPoint: value.location, viewSize: proxy.size)
                        }
                )
                .simultaneousGesture(zoomGesture)

                if let point = session.focusIndicator {
                    FocusReticle()
                        .offset(x: point.x - 34, y: point.y - 34)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
        }
        .ignoresSafeArea()
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                session.beginZoomGesture()
                session.updateZoom(magnification: value.magnification)
            }
            .onEnded { _ in
                session.endZoomGesture()
            }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                showInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 34, height: 34)
            }

            Spacer(minLength: 0)

            modePicker

            Spacer(minLength: 0)

            Button {
                showAdjust = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 34, height: 34)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(
            LinearGradient(colors: [.black.opacity(0.55), .clear],
                           startPoint: .top,
                           endPoint: .bottom)
                .allowsHitTesting(false)
        )
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(CaptureMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        session.mode = mode
                    }
                } label: {
                    Text(mode.label)
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(1)
                        .frame(width: 56, height: 28)
                        .background {
                            if session.mode == mode {
                                Capsule().fill(Color.white)
                            }
                        }
                        .foregroundStyle(session.mode == mode ? Color.black : Color.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.45)))
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    // MARK: - 底部控制区

    private var bottomPanel: some View {
        VStack(spacing: 10) {
            if session.mode == .photo {
                FilmStockStrip(selection: $session.look.stock)
            } else {
                logRow
            }

            shutterDial

            infoRow

            captureRow
        }
        .padding(.top, 14)
        .padding(.bottom, 4)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.62), .black.opacity(0.94)],
                           startPoint: .top,
                           endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        )
    }

    private var shutterDial: some View {
        VStack(spacing: 2) {
            HStack {
                Text("SHUTTER")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.38))

                Spacer(minLength: 0)

                if session.shutter != .auto, let actual = session.actualExposureSeconds {
                    Text("实际 " + actualExposureLabel(actual))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.38))
                }
            }
            .padding(.horizontal, 22)

            TactileDial(
                items: ShutterSpeed.dialOrder.map {
                    DialItem(id: $0.rawValue, title: $0.label, caption: $0.caption)
                },
                selectedID: Binding(
                    get: { session.shutter.rawValue },
                    set: { newValue in
                        if let speed = ShutterSpeed(rawValue: newValue) {
                            session.shutter = speed
                        }
                    }
                ),
                accent: session.look.stock.accent
            )
        }
    }

    private var infoRow: some View {
        HStack(spacing: 8) {
            InfoChip(title: "ISO", value: isoLabel) { showAdjust = true }
            InfoChip(title: "EV", value: String(format: "%+.1f", session.exposureBias)) { showAdjust = true }
            InfoChip(title: "WB", value: wbLabel) { showAdjust = true }

            if session.zoomFactor > 1.02 {
                InfoChip(title: "ZOOM", value: String(format: "%.1fx", session.zoomFactor)) {}
            }

            Spacer(minLength: 0)

            Button {
                session.switchCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 40, height: 30)
                    .background(Capsule().fill(Color.white.opacity(0.09)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 20)
    }

    private var captureRow: some View {
        ZStack {
            HStack {
                if session.isRecording {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text(timeString(session.recordSeconds))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }
                Spacer(minLength: 0)
                Text(session.look.stock.name)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, 26)

            captureButton
        }
        .frame(height: 86)
    }

    private var captureButton: some View {
        Button {
            if session.mode == .photo {
                session.capturePhoto()
            } else {
                session.toggleRecording()
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.85), lineWidth: 3)
                    .frame(width: 74, height: 74)
                if session.mode == .photo {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 60, height: 60)
                } else {
                    RoundedRectangle(cornerRadius: session.isRecording ? 5 : 26, style: .continuous)
                        .fill(Color.red)
                        .frame(width: session.isRecording ? 28 : 58,
                               height: session.isRecording ? 28 : 58)
                }
            }
            .opacity(session.isCapturing ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(session.isCapturing || !session.isRunning)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: session.isRecording)
    }

    private var logRow: some View {
        HStack(spacing: 10) {
            Button {
                session.appleLogEnabled.toggle()
            } label: {
                Text("APPLE LOG")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(session.appleLogEnabled ? Color.orange : Color.white.opacity(0.12))
                    )
                    .foregroundStyle(session.appleLogEnabled ? Color.black : Color.white)
            }
            .buttonStyle(.plain)
            .opacity(session.appleLogSupported ? 1 : 0.35)
            .disabled(!session.appleLogSupported)

            Text(logHint)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(height: 34)
    }

    private var logHint: String {
        if !session.appleLogSupported {
            return "这台设备不支持 Apple Log（需 iPhone 15 Pro 及更新机型）"
        }
        if session.appleLogEnabled {
            return "BT.2020 / 10-bit Log 原片，取景为近似显示，未烘焙胶片"
        }
        return "标准动态范围，可直接分享；打开后录制 Log 供后期调色"
    }

    // MARK: - 覆盖层

    private func statusBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
            Text(message)
                .font(.system(size: 11))
                .lineLimit(2)
            Button {
                session.clearStatus()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.red.opacity(0.6)))
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func toastView(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.black.opacity(0.72)))
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                .padding(.bottom, 250)
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    private var permissionView: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 30))
                .foregroundStyle(.white.opacity(0.85))
            Text("需要相机权限")
                .font(.headline)
                .foregroundStyle(.white)
            Text("请在「设置 → 胶片模拟 → 相机」中允许访问相机，然后回到这里。")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.6))
            Button("打开设置") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
            .tint(session.look.stock.accent)
            .foregroundStyle(.black)
        }
        .padding(26)
        .frame(maxWidth: 300)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(40)
    }

    // MARK: - 文案

    private var isoLabel: String {
        session.isoMode == .manual ? String(format: "%.0f", session.manualISO) : "AUTO"
    }

    private var wbLabel: String {
        let x = session.look.wbShift.x
        let y = session.look.wbShift.y
        if abs(x) < 0.01, abs(y) < 0.01 { return "0/0" }
        return String(format: "%+.1f/%+.1f", x, y)
    }

    private func actualExposureLabel(_ seconds: Double) -> String {
        guard seconds > 0 else { return "—" }
        if seconds >= 0.95 { return String(format: "%.1fs", seconds) }
        return "1/" + String(Int((1.0 / seconds).rounded()))
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - 对焦框

struct FocusReticle: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.yellow.opacity(0.9), lineWidth: 1.2)
            Rectangle()
                .fill(Color.yellow.opacity(0.8))
                .frame(width: 12, height: 1)
            Rectangle()
                .fill(Color.yellow.opacity(0.8))
                .frame(width: 1, height: 12)
        }
        .frame(width: 68, height: 68)
        .shadow(color: .black.opacity(0.35), radius: 2)
    }
}
