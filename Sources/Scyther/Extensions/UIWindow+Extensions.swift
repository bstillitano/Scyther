//
//  File.swift
//  
//
//  Created by Brandon Stillitano on 22/12/20.
//

#if os(iOS)

import UIKit

#if swift(>=4.2)
public typealias UIEventSubtype = UIEvent.EventSubtype
#endif

extension UIWindow {
    override open func motionEnded(_ motion: UIEventSubtype, with event: UIEvent?) {
        if Scyther.instance.selectedGesture == .shake {
            if (event!.type == .motion && event!.subtype == .motionShake) {
                Scyther.presentMenu()
            }
        } else {
            super.motionEnded(motion, with: event)
        }
    }
}
#endif
