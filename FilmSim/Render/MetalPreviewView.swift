import CoreImage
import Metal
import MetalKit
import SwiftUI

// MARK: - Metal 预览渲染器

/// 把 CIImage 每帧画进 MTKView 的 drawable。
/// 胶片模拟就在这里生效，所以取景框看到的就是最终照片的样子。
final class PreviewRenderer: NSObject, MTKViewDelegate {
    private let filmRenderer: FilmRenderer
    private let ciContext: CIContext
    private let commandQueue: MTLCommandQueue?

    private weak var view: MTKView?
    private var latestImage: CIImage?

    /// 由 SwiftUI 的 updateUIView 同步过来
    var look = FilmLook()

    init(renderer: FilmRenderer) {
        filmRenderer = renderer
        ciContext = renderer.context
        commandQueue = MTLCreateSystemDefaultDevice()?.makeCommandQueue()
        super.init()
    }

    func attach(view: MTKView) {
        self.view = view
    }

    /// 相机线程推一帧进来
    func push(_ image: CIImage) {
        latestImage = image
        view?.setNeedsDisplay()
    }

    func requestRedraw() {
        view?.setNeedsDisplay()
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let source = latestImage,
              let drawable = view.currentDrawable,
              let queue = commandQueue,
              view.drawableSize.width >= 1,
              view.drawableSize.height >= 1 else { return }

        let target = CGRect(origin: .zero, size: view.drawableSize)
        let framed = Self.aspectFill(source, into: target.size).cropped(to: target)
        let rendered = filmRenderer.render(framed, look: look)

        guard let buffer = queue.makeCommandBuffer() else { return }
        ciContext.render(rendered,
                         to: drawable.texture,
                         commandBuffer: buffer,
                         bounds: target,
                         colorSpace: filmRenderer.previewColorSpace)
        buffer.present(drawable)
        buffer.commit()
    }

    /// aspect fill：等比放大到铺满，多的部分裁掉
    static func aspectFill(_ image: CIImage, into size: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.width >= 1, extent.height >= 1,
              size.width >= 1, size.height >= 1 else { return image }
        let scale = max(size.width / extent.width, size.height / extent.height)
        let originX = (size.width - extent.width * scale) * 0.5
        let originY = (size.height - extent.height * scale) * 0.5
        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: originX, y: originY))
        return image
            .transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
            .transformed(by: transform)
    }
}

// MARK: - SwiftUI 包装

struct MetalPreview: UIViewRepresentable {
    let renderer: FilmRenderer
    let look: FilmLook
    let onReady: (PreviewRenderer) -> Void

    func makeCoordinator() -> PreviewRenderer {
        PreviewRenderer(renderer: renderer)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.isOpaque = true
        view.autoResizeDrawable = true
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.delegate = context.coordinator
        context.coordinator.attach(view: view)
        context.coordinator.look = look
        onReady(context.coordinator)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.look = look
        uiView.setNeedsDisplay()
    }

    static func dismantleUIView(_ uiView: MTKView, coordinator: PreviewRenderer) {
        uiView.delegate = nil
    }
}
