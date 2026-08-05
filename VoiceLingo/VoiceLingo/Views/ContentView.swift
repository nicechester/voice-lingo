//
//  ContentView.swift
//  VoiceLingo
//
//  Created by Kim, Chester on 8/4/26.
//

import SwiftUI
import SwiftData
import VoiceLingoCore

struct ContentView: View {
    @Query private var userProgress: [UserProgress]

    var body: some View {
        if userProgress.isEmpty {
            LanguagePickerView()
        } else {
            HomeView()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: UserProgress.self, inMemory: true)
}
