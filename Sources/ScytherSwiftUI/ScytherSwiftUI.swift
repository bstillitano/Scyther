//
//  File.swift
//  Scyther
//
//  Created by Brandon Stillitano on 18/7/2024.
//

import Scyther
import SwiftUI
import UIKit

// The notification we'll send when a shake gesture happens.
extension UIDevice {
    static let deviceDidShakeNotification = Notification.Name(rawValue: "deviceDidShakeNotification")
}

//  Override the default behavior of shake gestures to send our notification instead.
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake {
            NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
        }
    }
}

// A view modifier that detects shaking and calls a function of our choosing.
struct DeviceShakeViewModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear()
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) { _ in
            action()
        }
    }
}

// A View extension to make the modifier easier to use.
extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        self.modifier(DeviceShakeViewModifier(action: action))
    }
}

// A ViewModifier to show/hide Scyther
struct ScytherViewModifier: ViewModifier {
    @State private var isShowingMenu: Bool = false

    func body(content: Content) -> some View {
        content
            .onShake {
            isShowingMenu = true
        }.sheet(isPresented: $isShowingMenu) {
            MenuView()
        }
    }
}

// A View extension to show/hide Scyther.
public extension View {
    func shakeInvokesScyther() -> some View {
        self.modifier(ScytherViewModifier())
    }
}
