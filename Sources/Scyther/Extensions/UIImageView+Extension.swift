//
//  UIImageView+Extension.swift
// 
//
//  Created by Stefan Haider on 01.06.21.
//

#if !os(macOS)
import UIKit

extension UIImageView {
    
    func loadImage(fromURL url: URL, completion: ((Bool) -> Void)? = nil) {
        DispatchQueue.global().async { [weak self] in
            if let data = try? Data(contentsOf: url), let image =  UIImage(data: data) {
                DispatchQueue.main.async {
                    self?.image = image
                    completion?(true)
                }
            } else {
                completion?(false)
            }
        }
    }
}
#endif
