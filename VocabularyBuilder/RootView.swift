//
//  RootView.swift
//  vocabulary_builder
//
//  Switches between the AuthView and the main TabView based on the
//  persisted session. Mirrors `useAuth.tsx`'s gating behaviour. See
//  IOS_PORTING_GUIDE.md §7.1.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var api: APIClient

    var body: some View {
        Group {
            if session.isAuthenticated {
                ContentView()
                    .task { await library.reload(api: api) }
            } else {
                AuthView(api: api, session: session)
            }
        }
        .animation(.default, value: session.isAuthenticated)
    }
}
