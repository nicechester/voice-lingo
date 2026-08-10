//
//  SessionView.swift
//  VoiceLingo
//
//  Created by Kim, Chester on 8/4/26.
//

import SwiftUI
import SwiftData
import VoiceLingoCore

struct SessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let languageCode: String
    let levelId: String
    let lessonId: String

    @StateObject private var viewModel: SessionViewModel
    @Query private var progressRecords: [UserProgress]

    init(languageCode: String, levelId: String, lessonId: String) {
        self.languageCode = languageCode
        self.levelId = levelId
        self.lessonId = lessonId
        _viewModel = StateObject(wrappedValue: SessionViewModel())
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(viewModel.statusMessage)
                .font(.title2)
                .padding()

            if viewModel.currentPhase == .newContent || viewModel.currentPhase == .warmup {
                HStack(spacing: 20) {
                    Text("Phrase:")
                        .font(.headline)
                    Text(viewModel.phraseCount)
                        .font(.headline)
                        .foregroundColor(.blue)
                }
                .padding()
            }

            HStack(spacing: 20) {
                Text("Score:")
                    .font(.headline)
                Text("\(viewModel.sessionScore)")
                    .font(.headline)
                    .foregroundColor(.green)
            }
            .padding()

            Spacer()

            // State indicator icon
            stateIcon()
                .font(.system(size: 80))
                .frame(height: 120)

            Spacer()

            Button(action: {
                viewModel.repeatPhrase()
            }) {
                Text("Repeat")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding()
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    viewModel.stopSession()
                    dismiss()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
            }
        }
        .onChange(of: viewModel.isSessionActive) { _, active in
            if !active && viewModel.currentState == .sessionComplete { dismiss() }
        }
        .task {
            viewModel.attach(modelContext: modelContext,
                             userProgress: progressRecords.first { $0.languageCode == languageCode })
            viewModel.startSession(language: languageCode, levelId: levelId, lessonId: lessonId)
        }
        .onDisappear {
            viewModel.stopSession()
        }
    }

    @ViewBuilder
    private func stateIcon() -> some View {
        switch viewModel.currentState {
        case .speakingPrompt, .explaining:
            Image(systemName: "speaker.wave.2.fill")
                .foregroundColor(.blue)

        case .awaitingResponse:
            Image(systemName: "mic.fill")
                .foregroundColor(.red)

        case .evaluating:
            Image(systemName: "brain.head.profile")
                .foregroundColor(.orange)

        case .feedback:
            if viewModel.lastResponseCorrect == true {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if viewModel.lastResponseCorrect == false {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(.red)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.gray)
            }

        case .sessionComplete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)

        default:
            Image(systemName: "ellipsis")
                .foregroundColor(.gray)
        }
    }
}

#Preview {
    SessionView(languageCode: "es", levelId: "A1", lessonId: "lesson1")
        .modelContainer(for: UserProgress.self, inMemory: true)
}
