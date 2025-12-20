//
//  FirstAppearModifier.swift
//  Meowth
//
//  Created by Brandon Stillitano on 3/3/2024.
//

import SwiftUI

extension View {
    func onFirstAppear(_ action: @escaping () async -> Void) -> some View {
        modifier(FirstAppearModifier(action: action))
    }
}

private struct FirstAppearModifier: ViewModifier {
    let action: () async -> Void
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content.task {
            guard !hasAppeared else { return }
            hasAppeared = true
            await action()
        }
    }
}
