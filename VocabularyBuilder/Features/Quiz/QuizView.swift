//
//  QuizView.swift
//  vocabulary_builder
//
//  Three-mode multiple-choice quiz. Mirrors `QuizPage` in the web app.
//  See API.md §12 and IOS_PORTING_GUIDE.md §7.6.
//
//  Wire-format notes:
//  * `wordToDef` on the wire means *definition shown, word chosen*.
//    `defToWord` is the reverse. The names read backwards from their
//    meaning. QuizPage maps `mode == "def-to-word" ? quiz.defToWord :
//    quiz.wordToDef`; we mirror that.
//  * Options are always exactly four. Compare case-insensitively.
//  * At most 30 words are processed per request; extras are dropped.
//    Send `candidateWords` / `candidateDefinitions` so the offline
//    fallback produces real distractors instead of "Alternative 3".
//

import SwiftUI

enum QuizMode: String, CaseIterable, Identifiable {
    case wordToDef = "Word → Definition"
    case defToWord = "Definition → Word"
    case fillInGap = "Fill in the gap"

    var id: String { rawValue }

    var helpText: String {
        switch self {
        case .wordToDef: return "See the Vietnamese definition, pick the English word."
        case .defToWord: return "See the English word, pick the definition."
        case .fillInGap: return "Complete the example sentence with the right word."
        }
    }
}

struct QuizView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var session: SessionStore

    @State private var mode: QuizMode = .wordToDef
    @State private var quizSize: Int = 10
    @State private var strongThreshold: Int = 3
    @State private var settings: UserSettings?
    @State private var items: [QuizItem] = []
    @State private var model: String = ""
    @State private var index: Int = 0
    @State private var correctCount: Int = 0
    @State private var selected: String? = nil
    @State private var finished: Bool = false
    @State private var isLoading: Bool = false
    @State private var error: String?

    private var currentItem: QuizItem? {
        guard index < items.count else { return nil }
        return items[index]
    }

    var body: some View {
        // The navigation stack lives in `ContentView`, one per tab.
        VStack(spacing: 0) {
            if let err = error {
                ErrorBanner(message: err) {
                    Task { await start() }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            if finished {
                scoreCard
            } else if isLoading {
                // A plain inline loader. The old material card was
                // drawn over the quiz and read as a separate screen
                // sliding in, instead of a wait on this one.
                BookLoader(message: "Generating your quiz…")
            } else if items.isEmpty {
                startView
            } else if let item = currentItem {
                questionView(item)
            }
        }
        .background(Theme.pageBackground.ignoresSafeArea())
        .navigationTitle("Quiz")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(QuizMode.allCases) { m in
                        Button {
                            mode = m
                        } label: {
                            if mode == m {
                                Label(m.rawValue, systemImage: "checkmark")
                            } else {
                                Text(m.rawValue)
                            }
                        }
                    }
                } label: {
                    Label(mode.rawValue, systemImage: "slider.horizontal.3")
                }
            }
        }
        .task { await loadSettings() }
    }

    private func loadSettings() async {
        guard settings == nil, let user = session.user else { return }
        if let s = try? await api.getSettings(userId: user.id) {
            settings = s
            quizSize = s.quizSize
            strongThreshold = s.strongThreshold
        }
    }

    private func start() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        let eligible = library.words.filter { !library.isMastered($0, strongThreshold: strongThreshold) }
        let pool = Array(eligible.shuffled().prefix(quizSize))
        guard !pool.isEmpty else {
            error = "No eligible words. Add more in the Library tab."
            return
        }
        let others = library.words.filter { w in !pool.contains(where: { $0.id == w.id }) }
        let candWords = Array(others.map(\.word).shuffled().prefix(12))
        let candDefs = Array(others.map(\.definition).shuffled().prefix(12))
        let requestWords = pool.map { v in
            QuizWordRequest(
                id: v.id.uuidString.lowercased(),
                word: v.word,
                definition: v.definition,
                category: v.category.isEmpty ? nil : v.category,
                partOfSpeech: v.partOfSpeech.isEmpty ? nil : v.partOfSpeech,
                exampleSentence: v.exampleSentence.isEmpty ? nil : v.exampleSentence,
                difficulty: v.difficultyLevel,
                candidateWords: candWords,
                candidateDefinitions: candDefs
            )
        }
        do {
            let response = try await api.ensureQuiz(words: requestWords)
            self.items = response.quizzes
            self.model = response.model
            self.index = 0
            self.correctCount = 0
            self.selected = nil
            self.finished = false
        } catch let api as APIError {
            error = api.errorDescription
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func choose(_ choice: String) {
        guard selected == nil, let item = currentItem else { return }
        selected = choice
        let expected: String = {
            switch mode {
            case .wordToDef: return item.wordToDef.correctAnswer
            case .defToWord: return item.defToWord.correctAnswer
            case .fillInGap: return item.fillInGap.correctAnswer
            }
        }()
        let isCorrect = choice.localizedCaseInsensitiveCompare(expected) == .orderedSame
        if isCorrect { correctCount += 1 }
        if let word = library.words.first(where: { $0.id == item.wordId }) {
            Task {
                await library.recordQuizAnswer(
                    api: api,
                    for: word,
                    correct: isCorrect,
                    strongThreshold: strongThreshold
                )
            }
        }
    }

    private func advance() {
        selected = nil
        if index + 1 < items.count {
            index += 1
        } else {
            finished = true
        }
    }

    // MARK: - Subviews

    private var startView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "questionmark.circle")
                .font(.system(size: 56))
                .foregroundStyle(Theme.primary)
            Text("Ready to quiz?").font(.title2.bold())
            Text("You'll see \(quizSize) questions in \(mode.rawValue.lowercased()) mode. \(mode.helpText)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Stepper("Questions: \(quizSize)", value: $quizSize, in: 1...30)
                .padding(.horizontal, 40)
            PrimaryButton(title: "Start", icon: "play.fill") {
                Task { await start() }
            }
            .padding(.horizontal, 40)
            Spacer()
        }
    }

    private var scoreCard: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: correctCount >= (quizSize * 7 / 10) ? "trophy.fill" : "hand.thumbsup.fill")
                .font(.system(size: 64))
                .foregroundStyle(correctCount >= (quizSize * 7 / 10) ? .yellow : Theme.primary)
            Text("\(correctCount) / \(quizSize)")
                .font(.system(size: 56, weight: .bold))
            Text(correctCount >= (quizSize * 7 / 10) ? "Great job!" : "Keep practicing!")
                .font(.title3)
                .foregroundStyle(.secondary)
            if !model.isEmpty {
                Text("Model: \(model)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            PrimaryButton(title: "Try again", icon: "arrow.clockwise") {
                Task { await start() }
            }
            .padding(.horizontal, 40)
            Spacer()
        }
    }

    @ViewBuilder
    private func questionView(_ item: QuizItem) -> some View {
        let question: QuizChoice = {
            switch mode {
            case .wordToDef: return item.wordToDef
            case .defToWord: return item.defToWord
            case .fillInGap: return QuizChoice(
                options: item.fillInGap.options,
                correctAnswer: item.fillInGap.correctAnswer
            )
            }
        }()
        let prompt: String = {
            switch mode {
            case .wordToDef: return item.defToWord.correctAnswer
            case .defToWord: return item.wordToDef.correctAnswer
            case .fillInGap: return item.fillInGap.prompt
            }
        }()
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Question \(index + 1) of \(quizSize)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Score: \(correctCount)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text(prompt).font(.title2.bold())
                    if let word = library.words.first(where: { $0.id == item.wordId }),
                       let ipa = word.ipa, !ipa.isEmpty {
                        Text(ipa).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            VStack(spacing: 10) {
                ForEach(question.options, id: \.self) { choice in
                    choiceButton(choice, correct: question.correctAnswer)
                }
            }
            Spacer()
            if selected != nil {
                Button {
                    withAnimation { advance() }
                } label: {
                    Text(index + 1 == quizSize ? "See result" : "Next")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
    }

    @ViewBuilder
    private func choiceButton(_ choice: String, correct: String) -> some View {
        let isSelected = selected == choice
        let isCorrect = choice.localizedCaseInsensitiveCompare(correct) == .orderedSame
        let bg: Color = {
            if selected == nil { return Color(.systemGray6) }
            if isCorrect        { return Theme.primary.opacity(0.2) }
            if isSelected       { return Theme.danger.opacity(0.2) }
            return Color(.systemGray6)
        }()
        let fg: Color = {
            if selected == nil { return .primary }
            if isCorrect        { return Theme.primary }
            if isSelected       { return Theme.danger }
            return .primary
        }()
        Button {
            choose(choice)
        } label: {
            HStack {
                Text(choice).multilineTextAlignment(.leading)
                Spacer()
                if selected != nil {
                    if isCorrect { Image(systemName: "checkmark.circle.fill") }
                    if isSelected && !isCorrect { Image(systemName: "xmark.circle.fill") }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(bg)
            .foregroundStyle(fg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(selected != nil)
        .accessibilityLabel(choice)
    }
}
