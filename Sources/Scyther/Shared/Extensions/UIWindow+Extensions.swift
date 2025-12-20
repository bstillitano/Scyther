//
//  File.swift
//  
//
//  Created by Brandon Stillitano on 22/12/20.
//

#if os(iOS)
import UIKit

public typealias UIEventSubtype = UIEvent.EventSubtype

extension UIWindow {
    override open func motionEnded(_ motion: UIEventSubtype, with event: UIEvent?) {
        if Scyther.invocationGesture == .shake {
            if (event!.type == .motion && event!.subtype == .motionShake) {
                Scyther.showMenu()
            }
        } else {
            super.motionEnded(motion, with: event)
        }
    }
}
#endif
