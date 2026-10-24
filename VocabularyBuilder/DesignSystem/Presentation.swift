//
//  Presentation.swift
//  vocabulary_builder
//
//  Helpers that make a screen actually fill the device.
//
//  Three separate things get in the way of a full-screen screen on
//  iOS 15, and each one is handled here:
//
//  1. A `.sheet` presents as an inset card with rounded corners, not
//     edge to edge. Use `.fullScreenCover` for anything that is a
//     screen of its own.
//
//  2. A `NavigationView` inside a `.sheet` nests a second navigation
//     stack, which SwiftUI draws as a card inside the sheet's card.
//     A `NavigationView` as the *root* of a `.fullScreenCover` is
//     fine — there is only one stack.
//
//  3. A `fullScreenCover` presented from inside a tab does not hide
//     the tab bar. The cover is presented by the tab's hosting
//     controller, so the tab bar stays put. `.toolbar(.hidden, for:
//     .tabBar)` fixes it from iOS 16; on iOS 15 the tab bar has to be
//     hidden through UIKit.
//
//  See IOS_PORTING_GUIDE.md §3 (navigation) and §7.3 (OCR screen).
//

import SwiftUI
import UIKit

// MARK: - Tab bar

/// Hides the tab bar of the enclosing `TabView`.
///
/// Apply this to the content of a `fullScreenCover` that is presented
/// from inside a tab. Without it the cover is full height but the tab
/// bar is still drawn across the bottom, so the screen does not read as
/// full screen.
struct TabBarHider: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.toolbar(.hidden, for: .tabBar)
        } else {
            content.overlay(TabBarHidingView())
        }
    }
}

extension View {
    /// Hides the tab bar while this view is on screen.
    func hideTabBar() -> some View {
        modifier(TabBarHider())
    }
}

/// iOS 15 fallback for `TabBarHider`.
///
/// `.toolbar(.hidden, for: .tabBar)` does not exist before iOS 16, so
/// the tab bar is hidden through UIKit: the `UITabBarController` is
/// found by walking down from the window's root view controller, and
/// its tab bar is hidden until this view leaves the window.
private struct TabBarHidingView: UIViewRepresentable {
    func makeUIView(context: Context) -> Proxy {
        Proxy()
    }

    func updateUIView(_ uiView: Proxy, context: Context) {}

    final class Proxy: UIView {
        private weak var hiddenTabBar: UITabBar?

        override init(frame: CGRect) {
            super.init(frame: frame)
            // Invisible, and never in the way of a touch.
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window else {
                // The view was removed — put the tab bar back.
                hiddenTabBar?.isHidden = false
                hiddenTabBar = nil
                return
            }
            if let tabBar = Self.findTabBar(in: window.rootViewController) {
                hiddenTabBar = tabBar
                tabBar.isHidden = true
            }
        }

        /// Find the tab bar under a view controller, looking through the
        /// navigation controllers SwiftUI puts between the tabs.
        private static func findTabBar(in controller: UIViewController?) -> UITabBar? {
            guard let controller else { return nil }
            if let tab = controller as? UITabBarController {
                return tab.tabBar
            }
            if let nav = controller as? UINavigationController {
                if let bar = nav.viewControllers
                    .compactMap({ findTabBar(in: $0) })
                    .first {
                    return bar
                }
            }
            for child in controller.children {
                if let bar = findTabBar(in: child) { return bar }
            }
            return findTabBar(in: controller.presentedViewController)
        }
    }
}

// MARK: - Full-bleed forms

extension View {
    /// Makes a `Form` or `List` fill the screen edge to edge.
    ///
    /// The default form style is inset-grouped: the sections float in
    /// a rounded card on a grey background, which reads as "not full
    /// screen". The plain list style drops that card and lets the rows
    /// run to the edges, with the app's own page colour behind them.
    ///
    /// `.scrollContentBackground` would be the tidier fix, but it only
    /// exists from iOS 16 and the app supports iOS 15.
    func fullBleedForm() -> some View {
        listStyle(.plain)
            .background(Theme.pageBackground.ignoresSafeArea())
    }
}
