import Foundation
import AVFoundation
import UIKit
import CoreGraphics

/// 歌词画面 → 视频段（1.0.5 PiP 实验引擎的画面层）。
///
/// PiP（AVPictureInPictureController）只能播视频，不能直接挂歌词视图，
/// 所以把一行文字画成一段无声视频（黑底白字、居中），再交给 AVPlayer 播。
/// 每段固定 4 秒、2fps（8 帧静态画面）；测试文字与实时歌词走同一条路，
/// 只是文字来源不同。视频写进 tmp 目录，用完由调用方清理。
/// 注意：这是实验管线——编码耗时、后台行为、LC 里的表现都以真机为准，
/// 生成失败只记日志、不 crash、不卡主线程（全部在后台队列做）。
enum PiPFrameRenderer {

    static let videoSize = CGSize(width: 960, height: 540)
    static let segmentDuration: TimeInterval = 4.0
    private static let framesPerSecond = 2

    static func testVideoURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("tlds-pip-test.mp4")
    }

    static func segmentURL(forLine line: String) -> URL {
        let hash = abs(line.hashValue)
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("tlds-pip-\(hash).mp4")
    }

    /// 把主文字（＋可选副文字）渲染成一段视频。完成时主线程回调 completion。
    static func renderVideo(
        mainText: String,
        subText: String?,
        to url: URL,
        completion: @escaping (Error?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                // 文件本来就不存在时 removeItem 会抛错，忽略。
            }
            do {
                try render(mainText: mainText, subText: subText, to: url)
                DispatchQueue.main.async { completion(nil) }
            } catch {
                LyricLogger.log("诊断1.0.5 PiP：视频生成失败：\(error.localizedDescription)")
                DispatchQueue.main.async { completion(error) }
            }
        }
    }

    private static func render(mainText: String, subText: String?, to url: URL) throws {
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            throw NSError(domain: "TLDS.PiPFrameRenderer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "AVAssetWriter 创建失败"])
        }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(videoSize.width),
            AVVideoHeightKey: Int(videoSize.height),
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else {
            throw NSError(domain: "TLDS.PiPFrameRenderer", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "AVAssetWriter 不能加视频输入"])
        }
        writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(videoSize.width),
                kCVPixelBufferHeightKey as String: Int(videoSize.height),
            ]
        )
        guard writer.startWriting() else {
            throw NSError(domain: "TLDS.PiPFrameRenderer", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "AVAssetWriter startWriting 失败：\(writer.error?.localizedDescription ?? "?")"])
        }
        writer.startSession(atSourceTime: .zero)

        let frameCount = Int(segmentDuration) * framesPerSecond
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(framesPerSecond))
        let group = DispatchGroup()
        group.enter()
        var frameIndex = 0
        var renderError: Error?
        input.requestMediaDataWhenReady(on: DispatchQueue.global(qos: .userInitiated)) {
            while input.isReadyForMoreMediaData && frameIndex < frameCount {
                let time = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
                guard let pool = adaptor.pixelBufferPool else {
                    renderError = NSError(domain: "TLDS.PiPFrameRenderer", code: 4,
                                          userInfo: [NSLocalizedDescriptionKey: "pixelBufferPool 为空"])
                    break
                }
                var pixelBuffer: CVPixelBuffer?
                let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
                guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
                    renderError = NSError(domain: "TLDS.PiPFrameRenderer", code: 5,
                                          userInfo: [NSLocalizedDescriptionKey: "CVPixelBuffer 创建失败"])
                    break
                }
                draw(mainText: mainText, subText: subText, into: buffer)
                if !adaptor.append(buffer, withPresentationTime: time) {
                    renderError = NSError(domain: "TLDS.PiPFrameRenderer", code: 6,
                                          userInfo: [NSLocalizedDescriptionKey: "append 失败：\(writer.error?.localizedDescription ?? "?")"])
                    break
                }
                frameIndex += 1
            }
            if frameIndex >= frameCount || renderError != nil {
                input.markAsFinished()
                writer.finishWriting {
                    group.leave()
                }
            }
        }
        group.wait()
        if let renderError { throw renderError }
        if writer.status == .failed {
            throw writer.error ?? NSError(domain: "TLDS.PiPFrameRenderer", code: 7,
                                          userInfo: [NSLocalizedDescriptionKey: "finishWriting 失败"])
        }
    }

    /// 一帧画面：黑底，文字居中；太长自动缩小字号，直到放得下。
    private static func draw(mainText: String, subText: String?, into buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard let ctx = CGContext(
            data: base, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return }
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let rect = CGRect(x: 40, y: 0, width: width - 80, height: height)
        var fontSize: CGFloat = 64
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        func drawMain(size: CGFloat) -> CGSize {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph,
            ]
            let text = mainText as NSString
            let bounds = text.boundingRect(
                with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: attrs, context: nil
            )
            return bounds.size
        }
        while fontSize > 20 && drawMain(size: fontSize).height > height * 0.6 {
            fontSize -= 4
        }
        let mainAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraph,
        ]
        let mainSize = drawMain(size: fontSize)
        let mainRect = CGRect(
            x: rect.minX, y: (CGFloat(height) - mainSize.height) / 2 - (subText == nil ? 0 : 30),
            width: rect.width, height: mainSize.height
        )
        (mainText as NSString).draw(in: mainRect, withAttributes: mainAttrs)

        if let subText {
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 32, weight: .regular),
                .foregroundColor: UIColor.white.withAlphaComponent(0.75),
                .paragraphStyle: paragraph,
            ]
            let subRect = CGRect(
                x: rect.minX, y: mainRect.maxY + 16,
                width: rect.width, height: 48
            )
            (subText as NSString).draw(in: subRect, withAttributes: subAttrs)
        }
        // 金色细线：与桌面歌词品牌色呼应，证明画面是本 App 画的。
        ctx.setFillColor(UIColor(red: 0.85, green: 0.65, blue: 0.2, alpha: 1).cgColor)
        ctx.fill(CGRect(x: width / 2 - 60, y: height - 48, width: 120, height: 4))
    }
}
