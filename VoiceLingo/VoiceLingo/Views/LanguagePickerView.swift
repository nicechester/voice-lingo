//
//  LanguagePickerView.swift
//  VoiceLingo
//
//  Created by Kim, Chester on 8/4/26.
//

import SwiftUI
import SwiftData
import VoiceLingoCore

struct LanguagePickerView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Choose your language")
                .font(.title)
                .padding(.horizontal)
                .padding(.top)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Language.supportedLanguages) { language in
                        Button(action: {
                            selectLanguage(language)
                        }) {
                            HStack(spacing: 16) {
                                Text(language.flag)
                                    .font(.system(size: 32))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(language.nativeName)
                                        .font(.headline)
                                        .foregroundColor(.primary)

                                    Text(language.name)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                            .frame(maxWidth: .infinity, minHeight: 80)
                            .padding(.horizontal)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)
            }

            Spacer()
        }
    }

    private func selectLanguage(_ language: Language) {
        let newProgress = UserProgress(languageCode: language.code)
        modelContext.insert(newProgress)
        try? modelContext.save()
    }
}

#Preview {
    LanguagePickerView()
        .modelContainer(for: UserProgress.self, inMemory: true)
}
