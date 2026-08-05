//
//  HomeView.swift
//  VoiceLingo
//
//  Created by Kim, Chester on 8/4/26.
//

import SwiftUI
import SwiftData
import VoiceLingoCore

struct HomeView: View {
    @Query private var userProgress: [UserProgress]

    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to VoiceLingo")
                .font(.title)

            if let progress = userProgress.first,
               let language = Language.supportedLanguages.first(where: { $0.code == progress.languageCode }) {
                HStack(spacing: 12) {
                    Text(language.flag)
                        .font(.system(size: 48))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.nativeName)
                            .font(.headline)

                        Text(language.name)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }

            Spacer()
        }
        .padding()
    }
}

#Preview {
    HomeView()
        .modelContainer(for: UserProgress.self, inMemory: true)
}
