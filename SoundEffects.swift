import Foundation
import AVFoundation
import AudioToolbox
#if canImport(UIKit)
import UIKit
#endif

enum AppSound: String {
    case send

    var fileCandidates: [String] {
        switch self {
        case .send:
            return [
                "MailSwish.m4a",
                "MailSwish.wav"
            ]
        }
    }
}

enum SoundEffects {
    private static var players: [String: AVAudioPlayer] = [:]
    private static let session = AVAudioSession.sharedInstance()

    static func play(_ sound: AppSound, overrideSilent: Bool = false) {
        // Configure a non-intrusive session that respects silent switch
        if overrideSilent {
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        } else {
            try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        }
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

        #if canImport(UIKit)
        // Try loading from Asset Catalog (Data Set) named "MailSwish"
        if let dataAsset = NSDataAsset(name: "MailSwish") {
            do {
                let player = try AVAudioPlayer(data: dataAsset.data)
                player.prepareToPlay()
                players["MailSwish.asset"] = player
                player.play()
                return
            } catch {
                // continue to other fallbacks
            }
        }
        #endif

        // Secondary lookup: try to find any plausible swish file in the bundle
        let candidateBases = ["MailSwish", "SendSwish", "Whoosh", "Swish", "MailWhoosh", "Send"]
        let candidateExts = ["m4a", "wav", "aif", "aiff", "caf"]
        let fm = FileManager.default
        if let bundlePath = Bundle.main.resourcePath {
            do {
                let contents = try fm.contentsOfDirectory(atPath: bundlePath)
                // Try exact base names first (case-insensitive)
                for base in candidateBases {
                    for ext in candidateExts {
                        let target = "\(base).\(ext)"
                        if let match = contents.first(where: { $0.caseInsensitiveCompare(target) == .orderedSame }) {
                            let url = URL(fileURLWithPath: bundlePath).appendingPathComponent(match)
                            if let player = try? AVAudioPlayer(contentsOf: url) {
                                player.prepareToPlay()
                                players[match] = player
                                player.play()
                                return
                            }
                        }
                    }
                }
                // Try a fuzzy contains("swish"|"whoosh"|"email") search
                if let match = contents.first(where: { name in
                    let lower = name.lowercased()
                    return (lower.contains("swish") || lower.contains("whoosh") || lower.contains("email")) && candidateExts.contains((name as NSString).pathExtension.lowercased())
                }) {
                    let url = URL(fileURLWithPath: bundlePath).appendingPathComponent(match)
                    if let player = try? AVAudioPlayer(contentsOf: url) {
                        player.prepareToPlay()
                        players[match] = player
                        player.play()
                        return
                    }
                }
            } catch {
                // ignore and fall through
            }
        }

        print("[SoundEffects] Failed to find swish sound. Expected one of: \(sound.fileCandidates.joined(separator: ", ")). Add MailSwish.m4a to Copy Bundle Resources OR add a Data Asset named 'MailSwish' to your Assets catalog. Falling back to system sound.")

        // Fallback: try a short list of system sound IDs that are subtle
        let fallbackIDs: [SystemSoundID] = [1057, 1001, 1002, 1306]
        for id in fallbackIDs {
            AudioServicesPlaySystemSound(id)
            break
        }
    }
}
