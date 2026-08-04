//
//  VoiceLingoApp.swift
//  VoiceLingo
//
//  Created by Kim, Chester on 8/4/26.
//

import SwiftUI
import AVFoundation
import VoiceLingoCore

@main
struct VoiceLingoApp: App {
    init() {
        configureAudioSession()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(
                .playAndRecord,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
}
