//
//  File.swift
//  
//
//  Created by Stefan Haider on 01.06.21.
//

import UIKit

extension UIImageView {
    
    func loadImage(fromURL url: URL?, defaultImage: UIImage? = nil) {
        if let url = url {
            let cache =  URLCache.shared
            let request = URLRequest(url: url)
            DispatchQueue.global(qos: .userInitiated).async {
                if let data = cache.cachedResponse(for: request)?.data, let image = UIImage(data: data, scale: UIScreen.main.scale) {
                    self.image = image
                } else {
                    URLSession.shared.dataTask(with: request, completionHandler: { [weak self] (data, response, _) in
                        if let data = data, let response = response, ((response as? HTTPURLResponse)?.statusCode ?? 500) < 300, let image = UIImage(data: data, scale: UIScreen.main.scale) {
                            let cachedData = CachedURLResponse(response: response, data: data)
                            cache.storeCachedResponse(cachedData, for: request)
                            self?.image = image
                        } else if let image = defaultImage {
                            self?.image = image
                        }
                    }).resume()
                }
            }
        } else {
            self.image = defaultImage
        }
    }
}
