//
//  AuthView.swift
//  vocabulary_builder
//
//  Sign-up / sign-in screen. Presented modally before the TabView when
//  there is no persisted user. Mirrors `AuthPage` in the web app. See
//  API.md §6 and IOS_PORTING_GUIDE.md §7.1.
//
//  Notes from the wire-format quirks:
//  * `GET /api/auth/session` always returns 401, so we never call it. We
//    just persist the user object from sign-up / sign-in.
//  * 409 on sign-up means the e-mail is taken — offer to switch to
//    sign-in instead of showing a dead end.
//

import SwiftUI

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var isWorking: Bool = false
    @Published var error: String?

    let api: APIClient
    let session: SessionStore

    init(api: APIClient, session: SessionStore) {
        self.api = api
        self.session = session
    }

    var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty && !isWorking
    }

    func signIn() async {
        await submit { try await session.signIn(api: api, email: email, password: password) }
    }

    func signUp() async {
        await submit { try await session.signUp(api: api, email: email, password: password) }
    }

    private func submit(_ work: () async throws -> AuthUser) async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            _ = try await work()
        } catch let api as APIError {
            error = api.errorDescription
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct AuthView: View {
    @StateObject private var vm: AuthViewModel
    @State private var mode: Mode = .signIn

    enum Mode { case signIn, signUp }

    init(api: APIClient, session: SessionStore) {
        _vm = StateObject(wrappedValue: AuthViewModel(api: api, session: session))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    form
                    if let err = vm.error {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(Theme.danger)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    PrimaryButton(
                        title: mode == .signIn ? "Sign in" : "Create account",
                        icon: mode == .signIn ? "arrow.right.circle.fill" : "person.crop.circle.badge.plus",
                        action: { Task { await mode == .signIn ? vm.signIn() : vm.signUp() } }
                    )
                    .disabled(!vm.canSubmit)
                    .opacity(vm.canSubmit ? 1 : 0.5)
                    .padding(.horizontal)

                    Button {
                        mode = (mode == .signIn) ? .signUp : .signIn
                        vm.error = nil
                    } label: {
                        Text(mode == .signIn
                             ? "No account yet? Create one"
                             : "Already have an account? Sign in")
                            .font(.footnote)
                    }

                    Text("Your account lives on the API at \(vm.api.baseURL.absoluteString)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }
                .padding(.top, 32)
            }
            .background(Theme.pageBackground.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.primary)
            Text("Vocabulary Learner")
                .font(.largeTitle.bold())
            Text("English ↔ Vietnamese flashcards, study, and quiz.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    private var form: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $vm.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            SecureField("Password", text: $vm.password)
                .textContentType(mode == .signIn ? .password : .newPassword)
                .padding(12)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal)
    }
}
