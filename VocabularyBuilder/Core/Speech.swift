//
//  Speech.swift
//  vocabulary_builder
//
//  Thin wrapper around AVSpeechSynthesizer for the study screen's "speak the
//  word aloud" behaviour. Stops when the screen changes and honours the
//  device silent switch via `AVAudioSession`. See IOS_PORTING_GUIDE.md §6.
//

import Foundation
import AVFoundation

@MainActor
final class Speech: ObservableObject {
    static let shared = Speech()
    private let synth = AVSpeechSynthesizer()

    private init() {
        // Ambient so the silent switch is honoured, mix with others (e.g. music).
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .spokenAudio, options: [.mixWithOthers])
    }

    func speak(_ text: String, language: String = "en-US", rate: Float = 0.45) {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language) ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = rate
        utterance.preUtteranceDelay = 0
        synth.speak(utterance)
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }
}
