#if canImport(AVFoundation)
import AVFoundation
import Combine

public enum SYSVoiceGender: String, CaseIterable, Sendable {
    case female
    case male
}

struct SYSVoiceInfo: Equatable, Sendable {
    var identifier: String
    var language: String
    var isEnhanced: Bool
    var gender: SYSVoiceGender?

    init(identifier: String, language: String, isEnhanced: Bool, gender: SYSVoiceGender?) {
        self.identifier = identifier
        self.language = language
        self.isEnhanced = isEnhanced
        self.gender = gender
    }
}

enum SYSVoicePicker {
    private static let names: [SYSVoiceGender: [String]] = [
        .female: ["samantha", "karen", "moira", "tessa", "fiona", "ava", "allison", "susan"],
        .male: ["daniel", "alex", "tom", "oliver", "aaron", "fred", "lee"]
    ]

    static func best(from voices: [SYSVoiceInfo], language: String, gender: SYSVoiceGender) -> SYSVoiceInfo? {
        let opposite: SYSVoiceGender = gender == .female ? .male : .female
        let usable = voices.filter {
            $0.language.lowercased().hasPrefix(language.lowercased()) && $0.gender != opposite
        }
        func named(_ voice: SYSVoiceInfo) -> Bool {
            names[gender]?.contains { voice.identifier.lowercased().contains($0) } ?? false
        }
        let tiers: [(SYSVoiceInfo) -> Bool] = [
            { $0.isEnhanced && $0.gender == gender },
            { $0.gender == gender },
            { $0.isEnhanced && named($0) },
            { named($0) },
            { $0.isEnhanced }
        ]
        for tier in tiers {
            if let voice = usable.first(where: tier) { return voice }
        }
        return usable.first
    }
}

public struct SYSSpeechPhrase: Sendable {
    public var text: String
    public var rate: Float
    public var pitch: Float
    public var pauseBefore: TimeInterval
    var pauseAfter: TimeInterval

    public init(
        _ text: String,
        rate: Float = AVSpeechUtteranceDefaultSpeechRate,
        pitch: Float = 1,
        pauseBefore: TimeInterval = 0,
        pauseAfter: TimeInterval = 0
    ) {
        self.text = text
        self.rate = rate
        self.pitch = pitch
        self.pauseBefore = pauseBefore
        self.pauseAfter = pauseAfter
    }
}

@MainActor
public final class SYSSpeech: NSObject, ObservableObject {
    public static let shared = SYSSpeech()

    @Published public private(set) var isSpeaking = false

    @Published public var gender: SYSVoiceGender = .female {
        didSet {
            guard gender != oldValue else { return }
            if let genderKey { SYSSettings.shared[genderKey] = gender.rawValue }
            voice = pickVoice()
        }
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var language = "en"
    private var genderKey: SYSSettingsKey<String>?
    private var voiceInfos: [SYSVoiceInfo] = []
    private var voice: AVSpeechSynthesisVoice?
    private var batch = 0
    private var finishers: [ObjectIdentifier: (batch: Int, done: (Bool) -> Void)] = [:]
    private var deactivation: Task<Void, Never>?
    private var sessionActive = false
    private var interruptionObserver: NSObjectProtocol?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    public func configure(language: String = "en", genderKey key: String? = nil) {
        self.language = language
        if let key {
            let settingsKey = SYSSettingsKey<String>(key, default: "")
            genderKey = settingsKey
            if let stored = SYSVoiceGender(rawValue: SYSSettings.shared[settingsKey]) { gender = stored }
        }
        configureSession()
        loadVoices()
    }

    public func speak(_ phrases: [SYSSpeechPhrase]) async -> Bool {
        await withCheckedContinuation { continuation in
            begin(phrases) { continuation.resume(returning: $0) }
        }
    }

    public func speak(_ phrase: SYSSpeechPhrase) async -> Bool {
        await speak([phrase])
    }

    public func start(_ phrases: [SYSSpeechPhrase]) {
        begin(phrases, done: nil)
    }

    public func start(_ phrase: SYSSpeechPhrase) {
        begin([phrase], done: nil)
    }

    public func cancel() {
        resolveAll(completed: false)
        batch += 1
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        scheduleDeactivation()
    }

    private func begin(_ phrases: [SYSSpeechPhrase], done: ((Bool) -> Void)?) {
        let spoken = phrases.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !spoken.isEmpty else {
            done?(false)
            return
        }

        deactivation?.cancel()
        activateSession()
        resolveAll(completed: false)
        synthesizer.stopSpeaking(at: .immediate)

        batch += 1
        isSpeaking = true
        for (index, phrase) in spoken.enumerated() {
            let utterance = makeUtterance(phrase)
            if index == spoken.count - 1 {
                finishers[ObjectIdentifier(utterance)] = (batch, { done?($0) })
            }
            synthesizer.speak(utterance)
        }
    }

    private func finish(_ utterance: ObjectIdentifier, completed: Bool) {
        guard let finisher = finishers.removeValue(forKey: utterance) else { return }
        if finisher.batch == batch {
            isSpeaking = false
            scheduleDeactivation()
        }
        finisher.done(completed)
    }

    private func resolveAll(completed: Bool) {
        let pending = finishers
        finishers.removeAll()
        for finisher in pending.values { finisher.done(completed) }
    }

    private func makeUtterance(_ phrase: SYSSpeechPhrase) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: phrase.text)
        utterance.voice = voice
        utterance.rate = phrase.rate
        utterance.pitchMultiplier = phrase.pitch
        utterance.volume = 1
        utterance.preUtteranceDelay = phrase.pauseBefore
        utterance.postUtteranceDelay = phrase.pauseAfter
        return utterance
    }

    private func loadVoices() {
        Task.detached(priority: .utility) {
            let infos = AVSpeechSynthesisVoice.speechVoices().map { voice in
                SYSVoiceInfo(
                    identifier: voice.identifier,
                    language: voice.language,
                    isEnhanced: voice.quality != .default,
                    gender: Self.gender(of: voice)
                )
            }
            await self.finishLoading(infos)
        }
    }

    private func finishLoading(_ infos: [SYSVoiceInfo]) {
        voiceInfos = infos
        voice = pickVoice()
        let warmUp = AVSpeechUtterance(string: " ")
        warmUp.voice = voice
        warmUp.volume = 0
        synthesizer.speak(warmUp)
    }

    private func pickVoice() -> AVSpeechSynthesisVoice? {
        SYSVoicePicker.best(from: voiceInfos, language: language, gender: gender)
            .flatMap { AVSpeechSynthesisVoice(identifier: $0.identifier) }
    }

    private nonisolated static func gender(of voice: AVSpeechSynthesisVoice) -> SYSVoiceGender? {
        switch voice.gender {
        case .female: return .female
        case .male: return .male
        default: return nil
        }
    }

    #if os(iOS)
    private func configureSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let began = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began
            Task { @MainActor in
                guard let self else { return }
                self.sessionActive = false
                if began { self.cancel() }
            }
        }
    }

    private static let sessionQueue = DispatchQueue(label: "sys.speech.session", qos: .userInitiated)

    private func activateSession() {
        guard !sessionActive else { return }
        sessionActive = true
        Self.sessionQueue.async { try? AVAudioSession.sharedInstance().setActive(true) }
    }

    private func scheduleDeactivation() {
        deactivation?.cancel()
        deactivation = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, let self, !self.isSpeaking else { return }
            self.sessionActive = false
            Self.sessionQueue.async {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }
    #else
    private func configureSession() {}
    private func activateSession() {}
    private func scheduleDeactivation() {}
    #endif
}

extension SYSSpeech: AVSpeechSynthesizerDelegate {
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finish(id, completed: true) }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finish(id, completed: false) }
    }
}
#endif
