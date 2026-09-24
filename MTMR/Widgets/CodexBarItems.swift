// Codex-specific Touch Bar widgets.

import Foundation
import AppKit

/// A compact Codex allowance meter that pairs the native Touch Bar container
/// with SILO's green/amber/red quota states. The meter asks the locally
/// authenticated Codex app-server for a fresh snapshot every refresh cycle.
final class CodexQuotaBarItem: NSCustomTouchBarItem {
    private let refreshInterval: TimeInterval
    private let refreshQueue = DispatchQueue(label: "mtmr.codex-quota", qos: .utility)
    private var timer: DispatchSourceTimer?
    private let quotaView = CodexQuotaView(frame: NSRect(x: 0, y: 0, width: 230, height: 30))

    init(identifier: NSTouchBarItem.Identifier, refreshInterval: TimeInterval) {
        self.refreshInterval = max(5, refreshInterval)
        super.init(identifier: identifier)
        view = quotaView
        refreshAndSchedule()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func refreshAndSchedule() {
        refreshQueue.async { [weak self] in
            self?.refresh()
        }

        let timer = DispatchSource.makeTimerSource(queue: refreshQueue)
        timer.schedule(deadline: .now() + refreshInterval, repeating: refreshInterval)
        timer.setEventHandler { [weak self] in
            self?.refresh()
        }
        self.timer = timer
        timer.resume()
    }

    private func refresh() {
        let snapshot = CodexQuotaReader.snapshot()
        DispatchQueue.main.async { [weak self] in
            self?.quotaView.setSnapshot(snapshot)
        }
    }

    deinit {
        timer?.setEventHandler {}
        timer?.cancel()
    }
}

private final class CodexQuotaView: NSView {
    private let planLabel = NSTextField(labelWithString: "CODEX")
    private let progressTrack = NSView()
    private let progressFill = NSView()
    private let valueLabel = NSTextField(labelWithString: "—")
    private let resetLabel = NSTextField(labelWithString: "↻ —")
    private var fillWidthConstraint: NSLayoutConstraint!
    private let maximumFillWidth: CGFloat = 214

    private let successColor = NSColor(
        srgbRed: 82.0 / 255.0,
        green: 182.0 / 255.0,
        blue: 142.0 / 255.0,
        alpha: 1
    )
    private let warningColor = NSColor(
        srgbRed: 221.0 / 255.0,
        green: 161.0 / 255.0,
        blue: 71.0 / 255.0,
        alpha: 1
    )
    private let dangerColor = NSColor(
        srgbRed: 239.0 / 255.0,
        green: 116.0 / 255.0,
        blue: 107.0 / 255.0,
        alpha: 1
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.13).cgColor

        planLabel.translatesAutoresizingMaskIntoConstraints = false
        planLabel.textColor = NSColor(white: 1, alpha: 0.64)
        planLabel.font = NSFont.monospacedSystemFont(ofSize: 8, weight: .semibold)
        planLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        progressTrack.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.wantsLayer = true
        progressTrack.layer?.cornerRadius = 2
        progressTrack.layer?.backgroundColor = NSColor(white: 1, alpha: 0.20).cgColor

        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressFill.wantsLayer = true
        progressFill.layer?.cornerRadius = 2
        progressFill.layer?.backgroundColor = successColor.cgColor

        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.alignment = .right
        valueLabel.textColor = .white
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        valueLabel.lineBreakMode = .byClipping

        resetLabel.translatesAutoresizingMaskIntoConstraints = false
        resetLabel.alignment = .right
        resetLabel.textColor = NSColor(white: 1, alpha: 0.64)
        resetLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        resetLabel.lineBreakMode = .byClipping

        addSubview(planLabel)
        addSubview(progressTrack)
        progressTrack.addSubview(progressFill)
        addSubview(valueLabel)
        addSubview(resetLabel)

        fillWidthConstraint = progressFill.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            planLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            planLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            planLabel.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -6),
            progressTrack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            progressTrack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            progressTrack.widthAnchor.constraint(equalToConstant: maximumFillWidth),
            progressTrack.heightAnchor.constraint(equalToConstant: 4),
            progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            fillWidthConstraint,
            valueLabel.leadingAnchor.constraint(equalTo: planLabel.trailingAnchor, constant: 7),
            valueLabel.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            valueLabel.trailingAnchor.constraint(lessThanOrEqualTo: resetLabel.leadingAnchor, constant: -8),
            resetLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            resetLabel.centerYAnchor.constraint(equalTo: valueLabel.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSnapshot(_ snapshot: CodexQuotaSnapshot?) {
        guard let snapshot = snapshot else {
            valueLabel.stringValue = "—"
            resetLabel.stringValue = "↻ —"
            fillWidthConstraint.constant = 0
            return
        }

        let clamped = min(100, max(0, snapshot.remainingPercent))
        valueLabel.stringValue = String(format: "%.0f%%", clamped)
        if let resetsAt = snapshot.resetsAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d HH:mm"
            resetLabel.stringValue = "↻ " + formatter.string(from: resetsAt)
        } else {
            resetLabel.stringValue = "↻ —"
        }
        let color = clamped <= 10 ? dangerColor : (clamped <= 30 ? warningColor : successColor)
        progressFill.layer?.backgroundColor = color.cgColor
        fillWidthConstraint.constant = maximumFillWidth * CGFloat(clamped / 100)
    }
}

private struct CodexQuotaSnapshot {
    let remainingPercent: Double
    let resetsAt: Date?
}

private enum CodexQuotaReader {
    private final class AppServerRequestState {
        var buffer = Data()
        var didSendRateLimitRequest = false
        var result: CodexQuotaSnapshot?
        var isFinished = false
        let lock = NSLock()
        let completion = DispatchSemaphore(value: 0)
    }

    private static let snapshotLock = NSLock()
    private static var lastSnapshot: CodexQuotaSnapshot?
    private static var lastFetchAt: Date?
    private static let cacheLifetime: TimeInterval = 8

    static func snapshot() -> CodexQuotaSnapshot? {
        // Both Codex widgets refresh on their own utility queues. Serialize
        // requests and reuse a result for a few seconds so one 10-second tick
        // produces only one app-server connection.
        snapshotLock.lock()
        defer { snapshotLock.unlock() }

        if let lastFetchAt = lastFetchAt,
           Date().timeIntervalSince(lastFetchAt) < cacheLifetime {
            return lastSnapshot
        }

        let freshSnapshot = liveSnapshot()
        lastSnapshot = freshSnapshot
        lastFetchAt = Date()
        return freshSnapshot
    }

    private static func liveSnapshot() -> CodexQuotaSnapshot? {
        guard let codexURL = codexExecutableURL() else { return nil }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errorOutput = Pipe()

        process.executableURL = codexURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorOutput

        let state = AppServerRequestState()
        let inputHandle = input.fileHandleForWriting
        let outputHandle = output.fileHandleForReading

        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            var shouldSendRateLimitRequest = false
            var shouldSignal = false

            state.lock.lock()
            if data.isEmpty {
                if !state.isFinished {
                    state.isFinished = true
                    shouldSignal = true
                }
            } else {
                state.buffer.append(data)
                while let newlineIndex = state.buffer.firstIndex(of: 0x0A) {
                    let lineData = Data(state.buffer[..<newlineIndex])
                    state.buffer.removeSubrange(...newlineIndex)
                    guard !lineData.isEmpty,
                          let object = try? JSONSerialization.jsonObject(with: lineData),
                          let message = object as? [String: Any],
                          let messageID = (message["id"] as? NSNumber)?.intValue else { continue }

                    if messageID == 1 && !state.didSendRateLimitRequest {
                        state.didSendRateLimitRequest = true
                        shouldSendRateLimitRequest = true
                    } else if messageID == 2 {
                        if let result = message["result"] as? [String: Any],
                           let rateLimit = primaryRateLimit(from: result),
                           let used = rateLimit["usedPercent"] as? NSNumber {
                            let resetsAt = (rateLimit["resetsAt"] as? NSNumber).map {
                                Date(timeIntervalSince1970: $0.doubleValue)
                            }
                            state.result = CodexQuotaSnapshot(
                                remainingPercent: min(100, max(0, 100 - used.doubleValue)),
                                resetsAt: resetsAt
                            )
                        }
                        if !state.isFinished {
                            state.isFinished = true
                            shouldSignal = true
                        }
                    }
                }
            }
            state.lock.unlock()

            // The app-server protocol requires initialize to finish before
            // initialized and account/rateLimits/read are sent.
            if shouldSendRateLimitRequest {
                let requests = [
                    #"{"method":"initialized","params":{}}"#,
                    #"{"id":2,"method":"account/rateLimits/read"}"#
                ].joined(separator: "\n") + "\n"
                inputHandle.write(Data(requests.utf8))
            }
            if shouldSignal {
                state.completion.signal()
            }
        }

        do {
            try process.run()
            let initialize = #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"mtmr-codex-quota","version":"1.0"}}}"# + "\n"
            inputHandle.write(Data(initialize.utf8))
            _ = state.completion.wait(timeout: .now() + 5)
        } catch {
            outputHandle.readabilityHandler = nil
            return nil
        }

        outputHandle.readabilityHandler = nil
        inputHandle.closeFile()
        if process.isRunning {
            process.terminate()
        }

        state.lock.lock()
        let result = state.result
        state.lock.unlock()
        return result
    }

    private static func codexExecutableURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            home + "/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private static func primaryRateLimit(from result: [String: Any]) -> [String: Any]? {
        if let buckets = result["rateLimitsByLimitId"] as? [String: Any],
           let codex = buckets["codex"] as? [String: Any],
           let primary = codex["primary"] as? [String: Any] {
            return primary
        }
        guard let rateLimits = result["rateLimits"] as? [String: Any] else { return nil }
        return rateLimits["primary"] as? [String: Any]
    }

}

/// TokenTracker-style daily activity, compressed into a native Touch Bar pill.
final class CodexTodayBarItem: NSCustomTouchBarItem {
    private let refreshInterval: TimeInterval
    private let refreshQueue = DispatchQueue(label: "mtmr.codex-today", qos: .utility)
    private var timer: DispatchSourceTimer?
    private let todayView = CodexTodayView(frame: NSRect(x: 0, y: 0, width: 252, height: 30))

    init(identifier: NSTouchBarItem.Identifier, refreshInterval: TimeInterval) {
        self.refreshInterval = max(10, refreshInterval)
        super.init(identifier: identifier)
        view = todayView
        refreshAndSchedule()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func refreshAndSchedule() {
        refreshQueue.async { [weak self] in self?.refresh() }

        let timer = DispatchSource.makeTimerSource(queue: refreshQueue)
        timer.schedule(deadline: .now() + refreshInterval, repeating: refreshInterval)
        timer.setEventHandler { [weak self] in self?.refresh() }
        self.timer = timer
        timer.resume()
    }

    private func refresh() {
        let todaySnapshot = CodexTodayReader.snapshot()
        let quotaSnapshot = CodexQuotaReader.snapshot()
        DispatchQueue.main.async { [weak self] in
            self?.todayView.setSnapshots(today: todaySnapshot, quota: quotaSnapshot)
        }
    }

    deinit {
        timer?.setEventHandler {}
        timer?.cancel()
    }
}

private final class CodexTodayView: NSView {
    private let petView = CodexPetView()
    private let messageLabel = NSTextField(labelWithString: "Today · loading usage…")
    private let pillView = NSView()
    private let tailView = CodexSpeechTailView()
    private let switchButton = NSButton()
    private var todaySnapshot: CodexTodaySnapshot?
    private var quotaSnapshot: CodexQuotaSnapshot?
    private var pageIndex = 0
    private var hasPresentedFirstSnapshot = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        pillView.translatesAutoresizingMaskIntoConstraints = false
        pillView.wantsLayer = true
        pillView.layer?.cornerRadius = 12
        pillView.layer?.backgroundColor = NSColor(white: 1, alpha: 0.15).cgColor

        tailView.translatesAutoresizingMaskIntoConstraints = false

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.alignment = .center
        messageLabel.textColor = NSColor(white: 1, alpha: 0.92)
        messageLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        messageLabel.lineBreakMode = .byTruncatingMiddle
        messageLabel.maximumNumberOfLines = 1

        switchButton.translatesAutoresizingMaskIntoConstraints = false
        switchButton.title = ""
        switchButton.isBordered = false
        switchButton.setButtonType(.momentaryChange)
        switchButton.focusRingType = .none
        switchButton.target = self
        switchButton.action = #selector(cycleMessage(_:))

        petView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(petView)
        addSubview(tailView)
        addSubview(pillView)
        pillView.addSubview(messageLabel)
        pillView.addSubview(switchButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            petView.leadingAnchor.constraint(equalTo: leadingAnchor),
            petView.centerYAnchor.constraint(equalTo: centerYAnchor),
            petView.widthAnchor.constraint(equalToConstant: 30),
            petView.heightAnchor.constraint(equalToConstant: 28),
            tailView.widthAnchor.constraint(equalToConstant: 8),
            tailView.heightAnchor.constraint(equalToConstant: 12),
            tailView.leadingAnchor.constraint(equalTo: petView.trailingAnchor, constant: 7),
            tailView.centerYAnchor.constraint(equalTo: centerYAnchor),
            pillView.leadingAnchor.constraint(equalTo: petView.trailingAnchor, constant: 12),
            pillView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pillView.centerYAnchor.constraint(equalTo: centerYAnchor),
            pillView.heightAnchor.constraint(equalToConstant: 26),
            messageLabel.leadingAnchor.constraint(equalTo: pillView.leadingAnchor, constant: 10),
            messageLabel.trailingAnchor.constraint(equalTo: pillView.trailingAnchor, constant: -10),
            messageLabel.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
            switchButton.leadingAnchor.constraint(equalTo: pillView.leadingAnchor),
            switchButton.trailingAnchor.constraint(equalTo: pillView.trailingAnchor),
            switchButton.topAnchor.constraint(equalTo: pillView.topAnchor),
            switchButton.bottomAnchor.constraint(equalTo: pillView.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSnapshots(today: CodexTodaySnapshot?, quota: CodexQuotaSnapshot?) {
        todaySnapshot = today
        quotaSnapshot = quota
        renderCurrentPage(animatePet: !hasPresentedFirstSnapshot)
        hasPresentedFirstSnapshot = true
    }

    @objc private func cycleMessage(_: NSButton) {
        pageIndex = (pageIndex + 1) % 2
        renderCurrentPage(animatePet: true)
    }

    private func renderCurrentPage(animatePet: Bool) {
        if pageIndex == 0 {
            if let snapshot = todaySnapshot {
                messageLabel.stringValue = "Today · \(formatTokens(snapshot.totalTokens)) tokens · $\(String(format: "%.2f", snapshot.estimatedCost))"
            } else {
                messageLabel.stringValue = "Today · usage unavailable"
            }
            if animatePet { petView.showMood(.usage) }
        } else {
            messageLabel.stringValue = quotaMessage()
            let isLow = (quotaSnapshot?.remainingPercent ?? 100) <= 30
            if animatePet { petView.showMood(isLow ? .quotaLow : .quotaComfortable) }
        }
    }

    private func quotaMessage() -> String {
        guard let snapshot = quotaSnapshot else { return "Codex 7d · quota unavailable" }
        let remaining = min(100, max(0, snapshot.remainingPercent))
        let status: String
        if remaining <= 10 {
            status = "near limit"
        } else if remaining <= 30 {
            status = "running low"
        } else {
            status = "available"
        }
        guard let reset = snapshot.resetsAt else { return "Codex 7d · \(status)" }
        return "Codex 7d · \(status) · \(relativeReset(reset))"
    }

    private func relativeReset(_ date: Date) -> String {
        let seconds = max(0, date.timeIntervalSinceNow)
        if seconds >= 86_400 { return "in \(max(1, Int(ceil(seconds / 86_400))))d" }
        if seconds >= 3_600 { return "in \(max(1, Int(ceil(seconds / 3_600))))h" }
        return "in \(max(1, Int(ceil(seconds / 60))))m"
    }

    private func formatTokens(_ tokens: Int64) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
        if tokens >= 1_000 {
            return String(format: "%.0fK", Double(tokens) / 1_000)
        }
        return "\(tokens)"
    }
}

private final class CodexSpeechTailView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(white: 1, alpha: 0.15).setFill()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: bounds.midY))
        path.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY))
        path.line(to: NSPoint(x: bounds.maxX, y: bounds.minY))
        path.close()
        path.fill()
    }
}

private enum CodexPetMood {
    case usage
    case quotaComfortable
    case quotaLow
}

/// A native Core Animation recreation of TokenTracker's official Clawd. Its
/// geometry, colors, idle rhythm, and reactions mirror TokenTracker's SVG pet,
/// while avoiding WebKit's frozen animation layers inside NSTouchBar.
private final class CodexPetView: NSView {
    private let clawdColor = NSColor(calibratedRed: 0xDE / 255, green: 0x88 / 255, blue: 0x6D / 255, alpha: 1).cgColor
    private let cyanColor = NSColor(calibratedRed: 0x40 / 255, green: 0xC4 / 255, blue: 1, alpha: 1).cgColor
    private let characterLayer = CALayer()
    private let motionLayer = CALayer()
    private let breathLayer = CALayer()
    private let eyesLayer = CALayer()
    private let leftArmLayer = CALayer()
    private let rightArmLayer = CALayer()
    private let mouthLayer = CALayer()
    private let tearLayer = CALayer()
    private let questionLayer = CALayer()
    private let exclamationLayer = CALayer()
    private let interactionView = NSView()

    private var automaticActionTimer: Timer?
    private var frameTimer: Timer?
    private var pendingSingleTap: DispatchWorkItem?
    private var ignoreSingleTapUntil: CFTimeInterval = 0
    private var action: PetAction = .idle
    private var displayMood: CodexPetMood = .quotaComfortable
    private var actionStarted: CFTimeInterval = 0
    private var actionDuration: TimeInterval = 0

    private enum PetAction {
        case idle
        case side(CGFloat)
        case panic
        case happy
        case yawn
        case peek
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configurePet()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configurePet()
    }

    override func layout() {
        super.layout()
        let scale = min(bounds.width / 15, bounds.height / 12) * 0.90
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        characterLayer.bounds = CGRect(x: 0, y: 4, width: 15, height: 12)
        characterLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        characterLayer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        CATransaction.commit()
    }

    private func configurePet() {
        wantsLayer = true
        guard let hostLayer = layer else { return }

        characterLayer.bounds = CGRect(x: 0, y: 4, width: 15, height: 12)
        characterLayer.isGeometryFlipped = true
        characterLayer.masksToBounds = false
        hostLayer.addSublayer(characterLayer)

        motionLayer.frame = CGRect(x: 0, y: 0, width: 15, height: 16)
        motionLayer.isGeometryFlipped = true
        breathLayer.frame = CGRect(x: 0, y: 0, width: 15, height: 16)
        breathLayer.isGeometryFlipped = true
        characterLayer.addSublayer(motionLayer)
        motionLayer.addSublayer(breathLayer)

        let shadow = pixelRect(3, 15, 9, 1, NSColor.black.withAlphaComponent(0.5).cgColor)
        characterLayer.addSublayer(shadow)
        for x in [3, 5, 9, 11] {
            characterLayer.addSublayer(pixelRect(CGFloat(x), 13, 1, 2, clawdColor))
        }

        breathLayer.addSublayer(pixelRect(2, 6, 11, 7, clawdColor))
        configureArm(leftArmLayer, frame: CGRect(x: 0, y: 9, width: 2, height: 2), anchorX: 1)
        configureArm(rightArmLayer, frame: CGRect(x: 13, y: 9, width: 2, height: 2), anchorX: 0)
        breathLayer.addSublayer(leftArmLayer)
        breathLayer.addSublayer(rightArmLayer)

        eyesLayer.frame = breathLayer.bounds
        eyesLayer.isGeometryFlipped = true
        // Fixed, straight-ahead eyes: no pointer-following gaze toward the screen above.
        eyesLayer.addSublayer(pixelRect(4, 8, 2, 1, NSColor.black.cgColor))
        eyesLayer.addSublayer(pixelRect(9, 8, 2, 1, NSColor.black.cgColor))
        breathLayer.addSublayer(eyesLayer)

        mouthLayer.frame = CGRect(x: 6, y: 10, width: 3, height: 2)
        mouthLayer.backgroundColor = NSColor.black.cgColor
        mouthLayer.opacity = 0
        tearLayer.frame = CGRect(x: 3.5, y: 10, width: 1, height: 1)
        tearLayer.backgroundColor = cyanColor
        tearLayer.opacity = 0
        breathLayer.addSublayer(mouthLayer)
        breathLayer.addSublayer(tearLayer)

        buildQuestionMark()
        buildExclamationMark()
        startFrameUpdates()
        configureInteraction()

        let timer = Timer(timeInterval: 6, repeats: true) { [weak self] _ in
            self?.performAutomaticAction()
        }
        RunLoop.main.add(timer, forMode: .common)
        automaticActionTimer = timer

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self = self, self.actionDuration == 0 else { return }
            self.setAction(.happy, duration: 2.4)
        }
    }

    private func pixelRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: CGColor) -> CALayer {
        let result = CALayer()
        result.frame = CGRect(x: x, y: y, width: width, height: height)
        result.backgroundColor = color
        result.magnificationFilter = .nearest
        return result
    }

    private func configureArm(_ arm: CALayer, frame: CGRect, anchorX: CGFloat) {
        arm.bounds = CGRect(origin: .zero, size: frame.size)
        arm.anchorPoint = CGPoint(x: anchorX, y: 0)
        arm.position = CGPoint(
            x: frame.origin.x + frame.width * anchorX,
            y: frame.origin.y
        )
        arm.backgroundColor = clawdColor
    }

    private func buildQuestionMark() {
        questionLayer.frame = CGRect(x: 0, y: 0, width: 15, height: 16)
        questionLayer.isGeometryFlipped = true
        questionLayer.opacity = 0
        let blocks = [
            CGRect(x: 1, y: 0, width: 2, height: 1), CGRect(x: 0, y: 1, width: 1, height: 1),
            CGRect(x: 3, y: 1, width: 1, height: 2), CGRect(x: 2, y: 3, width: 1, height: 1),
            CGRect(x: 1, y: 4, width: 1, height: 1), CGRect(x: 1, y: 6, width: 1, height: 1)
        ]
        blocks.forEach { rect in
            questionLayer.addSublayer(pixelRect(rect.origin.x, rect.origin.y + 4, rect.width, rect.height, cyanColor))
        }
        characterLayer.addSublayer(questionLayer)
    }

    private func buildExclamationMark() {
        exclamationLayer.frame = CGRect(x: 0, y: 0, width: 15, height: 16)
        exclamationLayer.isGeometryFlipped = true
        exclamationLayer.opacity = 0
        exclamationLayer.addSublayer(pixelRect(13, 4, 1, 4, NSColor.white.cgColor))
        exclamationLayer.addSublayer(pixelRect(13, 9, 1, 1, NSColor.white.cgColor))
        characterLayer.addSublayer(exclamationLayer)
    }

    private func startFrameUpdates() {
        let timer = Timer(timeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            self?.updateAnimationFrame()
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
        updateAnimationFrame()
    }

    private func configureInteraction() {
        interactionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(interactionView)
        NSLayoutConstraint.activate([
            interactionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            interactionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            interactionView.topAnchor.constraint(equalTo: topAnchor),
            interactionView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let singleTap = NSClickGestureRecognizer(target: self, action: #selector(singleTapped(_:)))
        singleTap.numberOfClicksRequired = 1
        let doubleTap = NSClickGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfClicksRequired = 2
        interactionView.addGestureRecognizer(singleTap)
        interactionView.addGestureRecognizer(doubleTap)
        let press = NSPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        press.minimumPressDuration = 0.55
        interactionView.addGestureRecognizer(press)
    }

    @objc private func singleTapped(_ sender: NSClickGestureRecognizer) {
        guard CACurrentMediaTime() >= ignoreSingleTapUntil else { return }
        let direction: CGFloat = sender.location(in: interactionView).x < interactionView.bounds.midX ? -1 : 1
        pendingSingleTap?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.setAction(.side(direction), duration: 2.5)
        }
        pendingSingleTap = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    @objc private func doubleTapped(_: NSClickGestureRecognizer) {
        ignoreSingleTapUntil = CACurrentMediaTime() + 0.4
        pendingSingleTap?.cancel()
        setAction(.panic, duration: 3.5)
    }

    @objc private func longPressed(_ sender: NSPressGestureRecognizer) {
        guard sender.state == .began else { return }
        ignoreSingleTapUntil = CACurrentMediaTime() + 0.8
        pendingSingleTap?.cancel()
        setAction(.happy, duration: 3.2)
    }

    private func performAutomaticAction() {
        guard actionDuration == 0 else { return }
        switch Int.random(in: 0 ... 2) {
        case 0: setAction(.yawn, duration: 3.8)
        case 1: setAction(.peek, duration: 3.2)
        default: setAction(.side(Bool.random() ? -1 : 1), duration: 2.5)
        }
    }

    func showMood(_ mood: CodexPetMood) {
        displayMood = mood
        switch mood {
        case .usage:
            setAction(.happy, duration: 2.8)
        case .quotaComfortable:
            setAction(.peek, duration: 2.6)
        case .quotaLow:
            setAction(.panic, duration: 3.4)
        }
    }

    private func setAction(_ newAction: PetAction, duration: TimeInterval) {
        action = newAction
        actionStarted = CACurrentMediaTime()
        actionDuration = duration
        updateAnimationFrame()
    }

    private func updateAnimationFrame() {
        let now = CACurrentMediaTime()
        var progress: CGFloat = 0
        if actionDuration > 0 {
            progress = CGFloat((now - actionStarted) / actionDuration)
            if progress >= 1 {
                action = .idle
                actionDuration = 0
                progress = 0
            }
        }

        let breathePhase = CGFloat(fmod(now, 3.2) / 3.2)
        let breatheScale = 1 - 0.11 * (0.5 - 0.5 * cos(breathePhase * .pi * 2))
        let blinkPhase = fmod(now, 4.0)
        var motionTransform = CGAffineTransform(
            translationX: 0,
            y: sin(breathePhase * .pi * 2) * 0.9
        )
        var eyeTransform = CGAffineTransform.identity
        var leftArmAngle: CGFloat = 0
        var rightArmAngle: CGFloat = 0
        var leftArmOffset = CGPoint.zero
        var rightArmOffset = CGPoint.zero
        var eyeOpacity: Float = blinkPhase > 1.82 && blinkPhase < 2.02 ? 0.05 : 1
        var mouthOpacity: Float = 0
        var tearOpacity: Float = 0
        var questionOpacity: Float = 0
        var exclamationOpacity: Float = 0

        let idleWavePhase = fmod(now, 6.0)
        if idleWavePhase > 4.2 {
            let waveProgress = CGFloat((idleWavePhase - 4.2) / 1.8)
            leftArmAngle = sin(waveProgress * .pi * 4) * 0.34 * (1 - waveProgress)
            leftArmOffset = CGPoint(x: -0.8, y: -1.4 * sin(waveProgress * .pi))
        }

        switch action {
        case .idle:
            switch displayMood {
            case .usage:
                leftArmAngle = -0.17
                rightArmAngle = 0.17
                leftArmOffset = CGPoint(x: -0.5, y: -0.8)
                rightArmOffset = CGPoint(x: 0.5, y: -0.8)
            case .quotaComfortable:
                motionTransform = CGAffineTransform(rotationAngle: -0.045)
                leftArmAngle = -0.12
                leftArmOffset = CGPoint(x: -0.5, y: -0.6)
            case .quotaLow:
                leftArmAngle = -0.25
                rightArmAngle = 0.25
                leftArmOffset = CGPoint(x: -0.8, y: -1.2)
                rightArmOffset = CGPoint(x: 0.8, y: -1.2)
                exclamationOpacity = 1
            }
        case let .side(direction):
            let envelope = sin(min(max(progress, 0), 1) * .pi)
            motionTransform = CGAffineTransform(translationX: direction * 2.1 * envelope, y: 0)
            questionOpacity = progress > 0.10 && progress < 0.70 ? 1 : 0
            let wave = sin(progress * .pi * 5) * 0.30 * (1 - progress)
            if direction < 0 {
                leftArmAngle = -wave
                leftArmOffset = CGPoint(x: -0.8, y: -1.3 * envelope)
            } else {
                rightArmAngle = wave
                rightArmOffset = CGPoint(x: 0.8, y: -1.3 * envelope)
            }
        case .panic:
            let fade = max(0, 1 - progress)
            motionTransform = CGAffineTransform(translationX: sin(progress * .pi * 14) * 1.7 * fade, y: 0)
            questionOpacity = progress > 0.05 && progress < 0.42 ? 1 : 0
            exclamationOpacity = progress > 0.43 && progress < 0.78 ? 1 : 0
        case .happy:
            leftArmAngle = sin(progress * .pi * 12) * 0.34
            rightArmAngle = -sin(progress * .pi * 12) * 0.34
            let lift = abs(sin(progress * .pi * 6))
            leftArmOffset = CGPoint(x: -1, y: -2 * lift)
            rightArmOffset = CGPoint(x: 1, y: -2 * lift)
            exclamationOpacity = progress > 0.05 && progress < 0.82 ? 1 : 0
            eyeOpacity = progress > 0.28 && progress < 0.40 ? 0.05 : 1
        case .yawn:
            let yawnVisible = progress > 0.20 && progress < 0.78
            mouthOpacity = yawnVisible ? 1 : 0
            tearOpacity = progress > 0.35 && progress < 0.72 ? 1 : 0
            let squash = 1 - (yawnVisible ? 0.10 : 0)
            motionTransform = CGAffineTransform(scaleX: 1, y: squash)
            eyeOpacity = yawnVisible ? 0.05 : eyeOpacity
        case .peek:
            let envelope = sin(progress * .pi)
            motionTransform = CGAffineTransform(rotationAngle: -0.18 * envelope)
            leftArmAngle = sin(progress * .pi * 6) * 0.30 * envelope
            leftArmOffset = CGPoint(x: -0.8 * envelope, y: -1.5 * envelope)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        motionLayer.setAffineTransform(motionTransform)
        breathLayer.setAffineTransform(CGAffineTransform(scaleX: 1, y: breatheScale))
        eyesLayer.setAffineTransform(eyeTransform)
        eyesLayer.opacity = eyeOpacity
        leftArmLayer.setAffineTransform(CGAffineTransform(rotationAngle: leftArmAngle))
        rightArmLayer.setAffineTransform(CGAffineTransform(rotationAngle: rightArmAngle))
        leftArmLayer.position = CGPoint(x: 2 + leftArmOffset.x, y: 9 + leftArmOffset.y)
        rightArmLayer.position = CGPoint(x: 13 + rightArmOffset.x, y: 9 + rightArmOffset.y)
        mouthLayer.opacity = mouthOpacity
        tearLayer.opacity = tearOpacity
        questionLayer.opacity = questionOpacity
        exclamationLayer.opacity = exclamationOpacity
        CATransaction.commit()
        CATransaction.flush()
    }

    deinit {
        automaticActionTimer?.invalidate()
        frameTimer?.invalidate()
        pendingSingleTap?.cancel()
    }
}

private struct CodexTodaySnapshot {
    let totalTokens: Int64
    let estimatedCost: Double
}

private enum CodexTodayReader {
    private struct Price {
        let input: Double
        let cachedInput: Double
        let output: Double
    }

    private static var cachedSignature = ""
    private static var cachedSnapshot: CodexTodaySnapshot?

    static func snapshot() -> CodexTodaySnapshot? {
        if let tokenTrackerSnapshot = tokenTrackerSnapshot() {
            return tokenTrackerSnapshot
        }
        return localLogSnapshot()
    }

    /// TokenTracker's running macOS app exposes this read-only localhost API.
    /// Reading it keeps the Touch Bar total, deduplication, and pricing exactly
    /// aligned with the TokenTracker dashboard.
    private static func tokenTrackerSnapshot() -> CodexTodaySnapshot? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        let today = String(format: "%04d-%02d-%02d", year, month, day)

        var componentsURL = URLComponents(string: "http://127.0.0.1:7680/functions/tokentracker-usage-summary")
        componentsURL?.queryItems = [
            URLQueryItem(name: "from", value: today),
            URLQueryItem(name: "to", value: today),
            URLQueryItem(name: "tz", value: TimeZone.current.identifier)
        ]
        guard let url = componentsURL?.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                responseData = data
            }
            semaphore.signal()
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + 2.5) == .success,
              let data = responseData,
              let object = try? JSONSerialization.jsonObject(with: data),
              let response = object as? [String: Any],
              let totals = response["totals"] as? [String: Any] else {
            task.cancel()
            return nil
        }

        let totalTokens = int64(totals["total_tokens"])
        let estimatedCost: Double
        if let cost = totals["total_cost_usd"] as? NSNumber {
            estimatedCost = cost.doubleValue
        } else if let cost = totals["total_cost_usd"] as? String, let parsed = Double(cost) {
            estimatedCost = parsed
        } else {
            return nil
        }
        return CodexTodaySnapshot(totalTokens: totalTokens, estimatedCost: estimatedCost)
    }

    private static func localLogSnapshot() -> CodexTodaySnapshot? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }

        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(String(format: ".codex/sessions/%04d/%02d/%02d", year, month, day), isDirectory: true)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        var files: [(url: URL, size: Int, modified: TimeInterval)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            files.append((url, values.fileSize ?? 0, values.contentModificationDate?.timeIntervalSince1970 ?? 0))
        }
        files.sort { $0.url.path < $1.url.path }

        let signature = files.map { "\($0.url.path):\($0.size):\($0.modified)" }.joined(separator: "|")
        if signature == cachedSignature, let cachedSnapshot = cachedSnapshot {
            return cachedSnapshot
        }

        var totalTokens: Int64 = 0
        var estimatedCost = 0.0

        for file in files {
            guard let text = try? String(contentsOf: file.url, encoding: .utf8) else { continue }
            var currentModel = "gpt-5.6-sol"
            var modelByTurn: [String: String] = [:]

            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard line.contains("\"type\":\"turn_context\"") || line.contains("\"type\":\"token_usage_record\"") else { continue }
                guard let data = String(line).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data),
                      let record = object as? [String: Any],
                      let type = record["type"] as? String,
                      let payload = record["payload"] as? [String: Any] else { continue }

                if type == "turn_context" {
                    guard let model = payload["model"] as? String else { continue }
                    currentModel = model
                    if let turnID = payload["turn_id"] as? String {
                        modelByTurn[turnID] = model
                    }
                    continue
                }

                guard type == "token_usage_record",
                      let usage = payload["usage"] as? [String: Any] else { continue }
                let model = (payload["turn_id"] as? String).flatMap { modelByTurn[$0] } ?? currentModel
                let input = int64(usage["input_tokens"])
                let cached = int64(usage["cached_input_tokens"])
                let output = int64(usage["output_tokens"])
                let total = int64(usage["total_tokens"])
                let price = priceForModel(model)
                let uncached = max(0, input - cached)

                totalTokens += total
                estimatedCost += (
                    Double(uncached) * price.input
                    + Double(cached) * price.cachedInput
                    + Double(output) * price.output
                ) / 1_000_000
            }
        }

        let snapshot = CodexTodaySnapshot(totalTokens: totalTokens, estimatedCost: estimatedCost)
        cachedSignature = signature
        cachedSnapshot = snapshot
        return snapshot
    }

    private static func int64(_ value: Any?) -> Int64 {
        return (value as? NSNumber)?.int64Value ?? 0
    }

    /// USD per one million tokens. The cached-input rate is separate because
    /// Codex logs include cached tokens inside the input total.
    private static func priceForModel(_ model: String) -> Price {
        if model.contains("gpt-6") {
            return Price(input: 10.00, cachedInput: 1.00, output: 50.00)
        }
        if model.contains("gpt-5.6-luna") {
            return Price(input: 0.20, cachedInput: 0.02, output: 1.20)
        }
        if model.contains("gpt-5.6-terra") {
            return Price(input: 2.00, cachedInput: 0.20, output: 12.00)
        }
        if model.contains("gpt-5.5") {
            return Price(input: 5.00, cachedInput: 0.50, output: 30.00)
        }
        if model.contains("gpt-5.4") {
            return Price(input: 2.50, cachedInput: 0.25, output: 15.00)
        }
        if model.contains("gpt-5.3-codex") || model.contains("gpt-5.2") {
            return Price(input: 1.75, cachedInput: 0.175, output: 14.00)
        }
        return Price(input: 4.00, cachedInput: 0.40, output: 20.00)
    }
}
