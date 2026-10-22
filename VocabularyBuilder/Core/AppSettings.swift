//
//  AppSettings.swift
//  vocabulary_builder
//
//  User-tweakable settings. Persisted to UserDefaults so the app survives
//  relaunch. The base URL is the single source of truth for where every API
//  call goes — the Tailscale MagicDNS hostname is the recommended default
//  because iOS App Transport Security can grant a hostname exception but
//  not a raw-IP one.
//

import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    static let defaultBaseURL = URL(string: "http://bao-thinkcentre-m93p.tail2c53fc.ts.net:2001")!

    @Published var baseURL: URL {
        didSet { UserDefaults.standard.set(baseURL.absoluteString, forKey: Self.baseURLKey) }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Self.onboardingKey) }
    }

    private static let baseURLKey = "vocabulary.baseURL"
    private static let onboardingKey = "vocabulary.hasCompletedOnboarding"

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.baseURLKey),
           let url = URL(string: raw), !raw.isEmpty {
            self.baseURL = url
        } else {
            self.baseURL = Self.defaultBaseURL
        }
        self.hasCompletedOnboarding =
            UserDefaults.standard.bool(forKey: Self.onboardingKey)
    }
}
