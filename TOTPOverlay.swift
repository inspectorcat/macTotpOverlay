import Cocoa
import CommonCrypto

// MARK: - TOTP Generation (SHA-256, 6 digits, 30s period)

func generateTOTP(secret: String) -> String {
    guard let keyData = base32Decode(secret) else { return "------" }
    let time = UInt64(Date().timeIntervalSince1970) / 30
    var bigEndianTime = time.bigEndian
    let timeData = Data(bytes: &bigEndianTime, count: 8)

    var hmacResult = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    timeData.withUnsafeBytes { timePtr in
        keyData.withUnsafeBytes { keyPtr in
            CCHmac(
                CCHmacAlgorithm(kCCHmacAlgSHA256),
                keyPtr.baseAddress, keyData.count,
                timePtr.baseAddress, timeData.count,
                &hmacResult
            )
        }
    }

    let offset = Int(hmacResult[hmacResult.count - 1] & 0x0F)
    let truncated = (UInt32(hmacResult[offset]) & 0x7F) << 24
        | UInt32(hmacResult[offset + 1]) << 16
        | UInt32(hmacResult[offset + 2]) << 8
        | UInt32(hmacResult[offset + 3])
    let code = truncated % 1_000_000
    return String(format: "%06d", code)
}

func base32Decode(_ input: String) -> Data? {
    let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    let cleaned = input.uppercased().filter { alphabet.contains($0) }
    var bits = ""
    for char in cleaned {
        guard let index = alphabet.firstIndex(of: char) else { return nil }
        let val = alphabet.distance(from: alphabet.startIndex, to: index)
        bits += String(val, radix: 2).leftPadded(to: 5)
    }
    var bytes = [UInt8]()
    var i = bits.startIndex
    while bits.distance(from: i, to: bits.endIndex) >= 8 {
        let end = bits.index(i, offsetBy: 8)
        if let byte = UInt8(bits[i..<end], radix: 2) {
            bytes.append(byte)
        }
        i = end
    }
    return Data(bytes)
}

extension String {
    func leftPadded(to length: Int) -> String {
        String(repeating: "0", count: max(0, length - count)) + self
    }
}

// MARK: - Overlay Window

class OverlayWindow: NSWindow {
    init() {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let windowWidth: CGFloat = 260
        let windowHeight: CGFloat = 80
        let x = screenFrame.maxX - windowWidth - 20
        let y = screenFrame.maxY - windowHeight - 50

        super.init(
            contentRect: NSRect(x: x, y: y, width: windowWidth, height: windowHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        ignoresMouseEvents = false
    }
}

class OverlayView: NSView {
    var code: String = "------"
    var remaining: Int = 30

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14)
        NSColor(white: 0.08, alpha: 0.88).setFill()
        path.fill()

        // Border
        NSColor(white: 0.3, alpha: 0.5).setStroke()
        path.lineWidth = 1
        path.stroke()

        // TOTP code
        let codeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 34, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let spaced = code.map { String($0) }.joined(separator: " ")
        let codeStr = NSAttributedString(string: spaced, attributes: codeAttrs)
        let codeSize = codeStr.size()
        let codeX = (bounds.width - codeSize.width) / 2
        codeStr.draw(at: NSPoint(x: codeX, y: 24))

        // Countdown bar
        let barY: CGFloat = 10
        let barHeight: CGFloat = 4
        let barInset: CGFloat = 16
        let barWidth = bounds.width - barInset * 2
        let barRect = NSRect(x: barInset, y: barY, width: barWidth, height: barHeight)
        let barPath = NSBezierPath(roundedRect: barRect, xRadius: 2, yRadius: 2)
        NSColor(white: 0.25, alpha: 1).setFill()
        barPath.fill()

        let fraction = CGFloat(remaining) / 30.0
        let color: NSColor = remaining <= 5
            ? NSColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)
            : NSColor(red: 0.3, green: 0.85, blue: 0.5, alpha: 1)
        let fillRect = NSRect(x: barInset, y: barY, width: barWidth * fraction, height: barHeight)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2)
        color.setFill()
        fillPath.fill()

        // Countdown text
        let timerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor(white: 0.55, alpha: 1),
        ]
        let timerStr = NSAttributedString(string: "\(remaining)s", attributes: timerAttrs)
        let timerSize = timerStr.size()
        timerStr.draw(at: NSPoint(x: bounds.width - barInset - timerSize.width, y: barY + barHeight + 2))
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: OverlayWindow!
    var overlayView: OverlayView!
    var timer: Timer?
    let secret: String

    init(secret: String) {
        self.secret = secret
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = OverlayWindow()
        overlayView = OverlayView(frame: window.contentView!.bounds)
        overlayView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(overlayView)
        window.orderFrontRegardless()

        updateCode()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateCode()
        }
    }

    func updateCode() {
        overlayView.code = generateTOTP(secret: secret)
        overlayView.remaining = 30 - (Int(Date().timeIntervalSince1970) % 30)
        overlayView.needsDisplay = true
    }
}

// MARK: - Main

guard let secret = ProcessInfo.processInfo.environment["TOTP_SECRET"], !secret.isEmpty else {
    fputs("Error: TOTP_SECRET environment variable not set\n", stderr)
    exit(1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // No dock icon
let delegate = AppDelegate(secret: secret)
app.delegate = delegate
app.run()
