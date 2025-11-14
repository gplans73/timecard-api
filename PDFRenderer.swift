//
//  PDFRenderer.swift
//
//  ⚠️ DEPRECATED: This file is no longer used.
//  PDF generation is now handled by the Go API at /api/generate-pdf
//  You can safely delete this file.
//
import SwiftUI
import PDFKit

@available(*, deprecated, message: "Use Go API /api/generate-pdf instead")
enum PDFRenderer {
    static let a4Portrait: CGSize = CGSize(width: 595.0, height: 842.0)
    static let a4Landscape: CGSize = CGSize(width: 842.0, height: 595.0)

    static func render(view: AnyView, size: CGSize = PDFRenderer.a4Landscape) -> Data {
#if canImport(UIKit)
        let controller = UIHostingController(rootView: view
            .frame(width: size.width, height: size.height)
            .ignoresSafeArea())
        let v = controller.view!
        v.frame = CGRect(origin: .zero, size: size)
        v.bounds = CGRect(origin: .zero, size: size)
        v.isOpaque = true
        v.backgroundColor = .white
        let pageBounds = CGRect(origin: .zero, size: size)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            if let cg = UIGraphicsGetCurrentContext() {
                v.layer.render(in: cg)
            }
        }
#else
        // macOS fallback: render SwiftUI view into a bitmap, then into a single-page PDF
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = CGRect(origin: .zero, size: size)

        // Create a bitmap and ask AppKit to draw the view into it
        let scale: CGFloat = 2.0
        let pixelSize = NSSize(width: size.width * scale, height: size.height * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(pixelSize.width),
                                         pixelsHigh: Int(pixelSize.height),
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else {
            return Data()
        }
        rep.size = size // point size of the image
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let img = NSImage(size: size)
        img.addRepresentation(rep)

        let pdfDoc = PDFDocument()
        if let page = PDFPage(image: img) {
            pdfDoc.insert(page, at: 0)
        }
        return pdfDoc.dataRepresentation() ?? Data()
#endif
    }
}

