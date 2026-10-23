// End-to-end check against the live server using the REAL APIClient and
// the REAL LibraryStore — the exact code path the OCR import uses.
import Foundation

@MainActor
func run() async {
    let base = URL(string: "http://bao-thinkcentre-m93p.tail2c53fc.ts.net:2001")!
    let api = APIClient(baseURL: base)
    let store = LibraryStore()
    let email = "livecheck.\(Int(Date().timeIntervalSince1970))@example.com"

    do {
        // 1. Sign up (this is the step that used to report
        //    "resource exceeds maximum size").
        let user = try await api.signUp(email: email, password: "Passw0rd!23")
        print("1. sign-up            -> OK, userId=\(user.id)")

        // 2. Load the library, exactly as the Library tab does.
        await store.reloadWords(api: api)
        print("2. GET /api/words     -> OK, \(store.words.count) words")

        // 3. Import a word, exactly as the OCR flow does.
        let write = VocabularyWrite(
            word: "ephemeral", definition: "Lasting for a very short time.",
            translation: "thoáng qua", partOfSpeech: "adjective",
            exampleSentence: "Fame can be ephemeral.", category: "OCR",
            source: "ocr", imageId: nil, audioId: nil,
            difficultyLevel: "B1", ipa: nil, aiFieldsJson: nil
        )
        let created = try await store.createWord(api: api, write)
        print("3. POST /api/words    -> OK, id=\(created.id)")

        // 4. THE BUG: is the imported word in the local list right now?
        let inStore = store.words.contains { $0.id == created.id }
        print("4. in local store?    -> \(inStore ? "YES" : "NO  <-- BUG")")

        // 5. And after a fresh read-back from the server?
        await store.reloadWords(api: api)
        let afterReload = store.words.first { $0.id == created.id }
        print("5. after re-fetch     -> \(afterReload != nil ? "YES (\(afterReload!.word))" : "NO  <-- BUG")")
        print("   total words now    -> \(store.words.count)")
        print("   OCR words now      -> \(store.words.filter { $0.category == "OCR" }.count)")

        // 6. Clean up so the server is not polluted.
        try? await api.deleteWord(id: created.id)
        print("6. cleanup            -> done")
    } catch {
        print("FAILED: \(error)")
        exit(1)
    }
}

await run()
