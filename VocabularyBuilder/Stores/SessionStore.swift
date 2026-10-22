//
//  SessionStore.swift
//  vocabulary_builder
//
//  The API has no real authentication — sign-up returns a user, no token.
//  The session is a client-side concern: store the user object in
//  UserDefaults and use its `id` as the `userId` path segment on the
//  settings endpoints. See API.md §6 and IOS_PORTING_GUIDE.md §7.1.
//

import Foundation
import Combine

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var user: AuthUser?

    private static let key = "vocabulary.session.user"

    init() {
        restore()
    }

    var isAuthenticated: Bool { user != nil }

    func signIn(api: APIClient, email: String, password: String) async throws -> AuthUser {
        let user = try await api.signIn(email: email, password: password)
        self.user = user
        persist()
        return user
    }

    func signUp(api: APIClient, email: String, password: String) async throws -> AuthUser {
        let user = try await api.signUp(email: email, password: password)
        self.user = user
        persist()
        return user
    }

    func signOut() {
        user = nil
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    // MARK: - Persistence

    private func persist() {
        guard let user else { return }
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let user = try? JSONDecoder().decode(AuthUser.self, from: data) else {
            return
        }
        self.user = user
    }
}
