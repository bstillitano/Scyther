//
//  UIImageView+Extensions.swift
// 
//
//  Created by Stefan Haider on 01.06.21.
//

#if !os(macOS)
import UIKit

extension UIImageView {
    
    /**
     Tries to load an Image from an URL and sets it as image
     
     - Parameters:
        - url: The URL of the image to fetch
        - completion: called with true if ether the loaded or the defaultImage is set, false if no image is set.
     */
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
