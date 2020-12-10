//
//  UIImageView+Extensions.swift
//  Scyther
//
//  Created by Brandon Stillitano on 10/12/20.
//

import UIKit

extension UIImageView {

    func downloadImageFrom(_ url: URL, contentMode: UIView.ContentMode, _ completion: (() -> Void)? = nil) {

        // Check for cached device image
        let cachePath = FileManager.default.temporaryDirectory.appendingPathComponent("scyther.device.cache.png")
        if FileManager.default.fileExists(atPath: cachePath.path) {
            self.image = UIImage(contentsOfFile: cachePath.path)
            completion?()
            return
        }

        URLSession.shared.dataTask( with: url, completionHandler: { [weak self] (data, response, error) -> Void in
            DispatchQueue.main.async {
                self?.contentMode =  contentMode
                if let data = data { self?.image = UIImage(data: data) }

                // Attempt to cache device image to disk
                try? data?.write(to: cachePath)

                self?.layoutSubviews()
                completion?()
            }
        }).resume()
    }
}
