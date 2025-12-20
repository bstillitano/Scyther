//
//  SubsequentAppearModifier.swift
//  Meowth
//
//  Created by Brandon Stillitano on 3/3/2024.
//

import SwiftUI

extension View {
    func onSubsequentAppear(_ action: @escaping () async -> Void) -> some View {
        modifier(SubsequentAppearModifier(action: action))
    }
}

private struct SubsequentAppearModifier: ViewModifier {
    let action: () async -> Void
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content.task {
            guard hasAppeared else {
                hasAppeared = true
                return
            }
            await action()
        }
    }
}
