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
    @StateObject private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Header with language
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

                                    Spacer()
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                                .padding(.horizontal)
                                .padding(.top)
                            }

                            // Level grid
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                ForEach(viewModel.levelItems) { item in
                                    LevelCard(item: item, action: {
                                        viewModel.selectLevel(item)
                                    })
                                }
                            }
                            .padding()

                            // Error message
                            if let error = viewModel.errorMessage {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Error")
                                        .font(.headline)
                                        .foregroundColor(.red)
                                    Text(error)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color(.systemRed).opacity(0.1))
                                .cornerRadius(8)
                                .padding()
                            }

                            Spacer(minLength: 20)
                        }
                    }
                }
                .navigationDestination(item: $viewModel.activeSession) { params in
                    SessionView(
                        languageCode: params.languageCode,
                        levelId: params.levelId,
                        lessonId: params.lessonId
                    )
                }
                .sheet(isPresented: $viewModel.shouldShowLanguagePicker) {
                    LanguagePickerView()
                }
                .task {
                    let lang = userProgress.first?.languageCode ?? "es"
                    viewModel.loadLevels(progress: userProgress.first, languageCode: lang)
                    viewModel.setActive(true)
                    viewModel.startVoiceCommands(languageCode: lang)
                }
                .onDisappear {
                    viewModel.stopVoiceCommands()
                    viewModel.setActive(false)
                }
            }
        }
    }
}

private struct LevelCard: View {
    let item: LevelDisplayItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Text(item.id)
                    .font(.title)
                    .fontWeight(.bold)

                Text(item.title)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if !item.isContentAvailable {
                    VStack(spacing: 4) {
                        Image(systemName: "clock.badge.exclamationmark.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Coming soon")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if !item.isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                } else if item.scorePercent == 0 {
                    Text("New")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                } else {
                    Text("\(item.scorePercent)%")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 100)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .disabled(!item.isTappable)
        .opacity(item.isTappable ? 1.0 : 0.6)
    }
}

#Preview("All Level States") {
    NavigationStack {
        ScrollView {
            VStack(spacing: 20) {
                Text("Level States Preview")
                    .font(.title)
                    .padding()

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    // Locked
                    LevelCard(
                        item: LevelDisplayItem(
                            id: "A1",
                            title: "Beginner",
                            isUnlocked: false,
                            isContentAvailable: true,
                            scorePercent: 0,
                            firstLessonId: "lesson1"
                        ),
                        action: {}
                    )

                    // Unavailable
                    LevelCard(
                        item: LevelDisplayItem(
                            id: "A2",
                            title: "Elementary",
                            isUnlocked: false,
                            isContentAvailable: false,
                            scorePercent: 0,
                            firstLessonId: nil
                        ),
                        action: {}
                    )

                    // Unlocked/New
                    LevelCard(
                        item: LevelDisplayItem(
                            id: "B1",
                            title: "Intermediate",
                            isUnlocked: true,
                            isContentAvailable: true,
                            scorePercent: 0,
                            firstLessonId: "lesson1"
                        ),
                        action: {}
                    )

                    // Unlocked/Scored
                    LevelCard(
                        item: LevelDisplayItem(
                            id: "B2",
                            title: "Upper Intermediate",
                            isUnlocked: true,
                            isContentAvailable: true,
                            scorePercent: 85,
                            firstLessonId: "lesson1"
                        ),
                        action: {}
                    )
                }
                .padding()

                Spacer()
            }
        }
    }
}
