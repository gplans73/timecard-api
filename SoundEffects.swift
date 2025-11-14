import Foundation
import AVFoundation
import AudioToolbox

enum AppSound: String {
    case send

    var fileCandidates: [String] {
        switch self {
        case .send:
            return ["MailSwish.m4a", "MailSwish.wav"]
        }
    }
}

enum SoundEffects {
    private static var players: [String: AVAudioPlayer] = [:]
    private static let session = AVAudioSession.sharedInstance()

    static func play(_ sound: AppSound) {
        // Configure a non-intrusive session that respects silent switch
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true, options: [.notifyOthersOnDeactivation])

        // Attempt to reuse a cached player
        for name in sound.fileCandidates {
            if let player = players[name] {
                player.currentTime = 0
                player.play()
                return
            }
        }

        // Load from bundle
        let bundle = Bundle.main
        for name in sound.fileCandidates {
            let parts = name.split(separator: ".")
            guard parts.count == 2 else { continue }
            let base = String(parts[0])
            let ext = String(parts[1])
            if let url = bundle.url(forResource: base, withExtension: ext) {
                do {
                    let player = try AVAudioPlayer(contentsOf: url)
                    player.prepareToPlay()
                    players[name] = player
                    player.play()
                    return
                } catch {
                    // continue to next candidate
                }
            }
        }

        // Fallback: try a system sound that is subtle (may vary by OS)
        // Note: There is no public Mail "swoosh" ID. 1057 is a subtle whoosh on many versions.
        let fallbackID: SystemSoundID = 1057
        AudioServicesPlaySystemSound(fallbackID)
    }
}
