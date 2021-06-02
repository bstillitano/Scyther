//
//  UIImageView+Extension.swift
// 
//
//  Created by Stefan Haider on 01.06.21.
//

#if !os(macOS)
import UIKit

extension UIImageView {
    
    /**
     Trys to load an Image from an URL and sets it as image, if this fails there is a defaultImage you can set.
     
     - Parameters:
        - url: The URL of the image to fetch
        - defaultImage: The image wich gets set if loading the image from the URL fails.
        - completion: called with true if ether the loaded or the defaultImage is set, false if no image is set.
     */
    func loadImage(fromURL url: URL, defaultImage: UIImage? = nil, completion: ((Bool) -> Void)? = nil) {
        DispatchQueue.global().async { [weak self] in
            if let data = try? Data(contentsOf: url), let image =  UIImage(data: data) {
                DispatchQueue.main.async {
                    self?.image = image
                    completion?(true)
                }
            } else if let defaultImage = defaultImage {
                self?.image = defaultImage
                completion?(true)
            } else {
                completion?(false)
            }
        }
    }
}
#endif
