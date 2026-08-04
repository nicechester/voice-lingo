//
//  ContentView.swift
//  VoiceLingo
//
//  Created by Kim, Chester on 8/4/26.
//

import SwiftUI
import VoiceLingoCore

struct ContentView: View {
    var body: some View {
        VStack {
            Text("VoiceLingo")
                .font(.title)
            Text("Learning Spanish through voice")
                .font(.subheadline)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
