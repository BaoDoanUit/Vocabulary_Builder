//
//  QuizView.swift
//  Vocabulary
//

import SwiftUI

struct QuizView: View {
    @EnvironmentObject var store: WordStore

    @State private var questions: [Question] = []
    @State private var index: Int = 0
    @State private var correctCount: Int = 0
    @State private var selected: String? = nil
    @State private var finished: Bool = false

    private static let questionCount = 10

    struct Question: Identifiable {
        let id = UUID()
        let word: Word
        let choices: [String]
        var correctChoice: String { word.vietnamese }
    }

    var body: some View {
        NavigationView {
            VStack {
                if finished {
                    scoreCard
                } else if let q = current {
                    questionView(q)
                } else {
                    startView
                }
            }
            .padding()
            .navigationTitle("Quiz")
        }
    }

    private var current: Question? {
        guard index < questions.count else { return nil }
        return questions[index]
    }

    // MARK: - Subviews

    private var startView: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Ready to quiz?").font(.title2).bold()
            Text("You'll see \(Self.questionCount) English words. Pick the right Vietnamese meaning for each.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Start") { start() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scoreCard: some View {
        VStack(spacing: 16) {
            Image(systemName: correctCount >= 7 ? "trophy.fill" : "hand.thumbsup.fill")
                .font(.system(size: 64))
                .foregroundStyle(correctCount >= 7 ? .yellow : .accentColor)
            Text("\(correctCount) / \(Self.questionCount)")
                .font(.system(size: 56, weight: .bold))
            Text(correctCount >= 7 ? "Great job!" : "Keep practicing!")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Try again") { start() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func questionView(_ q: Question) -> some View {
        VStack(spacing: 20) {
            HStack {
                Text("Question \(index + 1) of \(Self.questionCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Score: \(correctCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 8) {
                Text(q.word.english)
                    .font(.system(size: 36, weight: .bold))
                if let p = q.word.pronunciation {
                    Text(p).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 20))

            VStack(spacing: 10) {
                ForEach(q.choices, id: \.self) { choice in
                    choiceButton(choice, correct: q.correctChoice)
                }
            }

            Spacer()

            if selected != nil {
                Button {
                    withAnimation { advance() }
                } label: {
                    Text(index + 1 == Self.questionCount ? "See result" : "Next")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    @ViewBuilder
    private func choiceButton(_ choice: String, correct: String) -> some View {
        let isSelected = selected == choice
        let isCorrect  = choice == correct
        let bg: Color = {
            if selected == nil { return Color(.systemGray6) }
            if isCorrect        { return .green.opacity(0.2) }
            if isSelected       { return .red.opacity(0.2) }
            return Color(.systemGray6)
        }()
        let fg: Color = {
            if selected == nil { return .primary }
            if isCorrect        { return .green }
            if isSelected       { return .red }
            return .primary
        }()
        Button {
            guard selected == nil else { return }
            selected = choice
            if isCorrect { correctCount += 1 }
            // Mark the word's status based on whether the user got it right
            store.setStatus(isCorrect ? .known : .learning, for: q_word)
        } label: {
            HStack {
                Text(choice)
                    .multilineTextAlignment(.leading)
                Spacer()
                if selected != nil {
                    if isCorrect  { Image(systemName: "checkmark.circle.fill") }
                    if isSelected && !isCorrect { Image(systemName: "xmark.circle.fill") }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(bg)
            .foregroundStyle(fg)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(selected != nil)
    }

    // Helper to access the current word from inside the choice button
    private var q_word: Word { current?.word ?? store.words[0] }

    // MARK: - Lifecycle

    private func start() {
        let pool = store.words.shuffled().prefix(Self.questionCount)
        questions = pool.map { word in
            Question(word: word, choices: store.quizChoices(for: word, count: 4))
        }
        index = 0
        correctCount = 0
        selected = nil
        finished = false
    }

    private func advance() {
        selected = nil
        if index + 1 < questions.count {
            index += 1
        } else {
            finished = true
        }
    }
}

#Preview {
    QuizView().environmentObject(WordStore())
}
