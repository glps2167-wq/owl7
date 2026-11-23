import Foundation
import AVFoundation
import Speech
import SwiftUI

struct Line: Identifiable, Equatable {
    let id = UUID()
    var time: String
    var text: String
    var star = false
    var mark = false
}

@MainActor
final class ScribeModel: ObservableObject {
    @Published var lines: [Line] = []
    @Published var interim = ""
    @Published var running = false
    @Published var status = "대기"
    @Published var errorMessage: String?
    @Published var elapsed: TimeInterval = 0
    @Published var limitMinutes = 60          // 0 = 제한 없음
    @Published var savedFiles: [URL] = []

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var feeder: AudioFeeder?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var timer: Timer?
    private var startDate: Date?
    private var fileURL: URL?

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.dateFormat = "HH:mm"; return f
    }()
    private let fileFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.dateFormat = "yyyyMMdd_HHmm"; return f
    }()

    init() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in self?.handleInterruption(rawType: raw) }
        }
        refreshFiles()
    }

    // MARK: - 녹음 시작/정지

    func toggle() {
        Task {
            if running { await stop() } else { await start() }
        }
    }

    func start() async {
        errorMessage = nil
        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "마이크 권한이 없습니다. 설정 > 앱 > owlSeven > 마이크를 켜 주세요."
            return
        }
        _ = await requestSpeechAuthorization()

        do {
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "ko-KR")) else {
                errorMessage = "이 기기에서 한국어 받아쓰기를 지원하지 않습니다."
                return
            }
            let tr = SpeechTranscriber(locale: locale,
                                       transcriptionOptions: [],
                                       reportingOptions: [.volatileResults],
                                       attributeOptions: [])
            status = "음성 모델 준비 중"
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [tr]) {
                status = "음성 모델 내려받는 중 (처음 한 번)"
                try await request.downloadAndInstall()
            }
            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [tr]) else {
                errorMessage = "음성 형식을 준비하지 못했습니다."
                status = "대기"
                return
            }

            let an = SpeechAnalyzer(modules: [tr])
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            transcriber = tr
            analyzer = an
            inputContinuation = continuation

            resultsTask = Task { [weak self] in
                do {
                    for try await result in tr.results {
                        let text = String(result.text.characters)
                        self?.handleResult(text: text, isFinal: result.isFinal)
                    }
                } catch {
                    self?.errorMessage = "받아쓰기가 중단되었습니다: \(error.localizedDescription)"
                }
            }

            try await an.start(inputSequence: stream)

            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default, options: [])
            try session.setActive(true)

            let input = engine.inputNode
            let inFormat = input.outputFormat(forBus: 0)
            guard let fd = AudioFeeder(from: inFormat, to: analyzerFormat, continuation: continuation) else {
                throw NSError(domain: "Scribe", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "오디오 변환기를 만들지 못했습니다."])
            }
            feeder = fd
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { buffer, _ in
                fd.feed(buffer)
            }
            engine.prepare()
            try engine.start()

            beginFile()
            appendLine(Line(time: now(), text: "— 기록 시작 —", mark: true))
            running = true
            status = "녹음 중"
            startDate = Date()
            elapsed = 0
            startTimer()
        } catch {
            errorMessage = "시작하지 못했습니다: \(error.localizedDescription)"
            await teardown()
            status = "대기"
        }
    }

    func stop() async {
        guard running else { return }
        running = false
        status = "정리 중"
        timer?.invalidate(); timer = nil
        await teardown()
        appendLine(Line(time: now(), text: "— 기록 정지 —", mark: true))
        interim = ""
        status = "대기"
        refreshFiles()
    }

    private func teardown() async {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        inputContinuation?.finish()
        inputContinuation = nil
        if let an = analyzer {
            try? await an.finalizeAndFinishThroughEndOfInput()
        }
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        feeder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - 결과 처리

    private func handleResult(text: String, isFinal: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isFinal {
            interim = ""
            if !trimmed.isEmpty { appendLine(Line(time: now(), text: trimmed)) }
        } else {
            interim = trimmed
        }
    }

    func markStar() {
        if let idx = lines.lastIndex(where: { !$0.mark }), !lines[idx].star {
            lines[idx].star = true
            appendToFile("★ 위 발언에 모르는 말 표시")
        } else {
            appendLine(Line(time: now(), text: "(여기서 모르는 말이 나옴)", star: true))
        }
    }

    // MARK: - 전화 등 중단 처리

    private func handleInterruption(rawType: UInt?) {
        guard let raw = rawType, let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            if running { status = "일시 중단 (전화 등)" }
        case .ended:
            guard running else { return }
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                if !engine.isRunning { try engine.start() }
                status = "녹음 중"
                appendLine(Line(time: now(), text: "— 중단 후 다시 시작 —", mark: true))
            } catch {
                errorMessage = "중단 후 다시 시작하지 못했습니다. 정지 후 다시 눌러 주세요."
            }
        @unknown default:
            break
        }
    }

    // MARK: - 타이머

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startDate, self.running else { return }
                self.elapsed = Date().timeIntervalSince(start)
                if self.limitMinutes > 0, self.elapsed >= Double(self.limitMinutes * 60) {
                    await self.stop()
                }
            }
        }
    }

    var elapsedText: String {
        let s = Int(elapsed)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    // MARK: - 파일 저장 (파일 앱 > 나의 iPhone > owlSeven)

    private var folderURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("받아쓰기", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func beginFile() {
        lines = []
        let url = folderURL.appendingPathComponent("받아쓰기_\(fileFormatter.string(from: Date())).txt")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        fileURL = url
    }

    private func appendLine(_ line: Line) {
        lines.append(line)
        appendToFile("[\(line.time)] \(line.star ? "★ " : "")\(line.text)")
    }

    private func appendToFile(_ text: String) {
        guard let url = fileURL, let data = (text + "\n").data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    func refreshFiles() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: nil)) ?? []
        savedFiles = urls.filter { $0.pathExtension == "txt" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        refreshFiles()
    }

    // MARK: - Claude에 보낼 글

    static func prompt(for body: String) -> String {
        let hasStar = body.contains("★")
        return """
        아래는 업무 대화를 받아쓴 기록입니다. 음성 인식이라 오타가 있을 수 있습니다.
        1) 나온 전산·IT 용어를 비전공자도 이해하게 쉽게 설명해 주세요\(hasStar ? " (★ 표시 부분 우선)" : "").
        2) 결정된 사항과 내가 할 일을 정리해 주세요.
        3) 다음에 물어보면 좋을 질문을 알려 주세요.

        [받아쓰기 기록]
        \(body)
        """
    }

    var currentShareText: String {
        let body = lines.map { "[\($0.time)] \($0.star ? "★ " : "")\($0.text)" }.joined(separator: "\n")
        return Self.prompt(for: body)
    }

    static func shareText(for url: URL) -> String {
        let body = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return prompt(for: body)
    }

    // MARK: - 보조

    private func now() -> String { timeFormatter.string(from: Date()) }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }
}
