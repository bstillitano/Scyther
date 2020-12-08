//
//  DeviceTableViewCell.swift
//  DebugMenu
//
//  Created by Jack Perry on 31/12/19.
//  Copyright © 2019 Jack Perry. All rights reserved.
//

#if !os(macOS)
import UIKit

final internal class DeviceTableViewCell: UITableViewCell {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)

//        guard let deviceImageUrl = MobileDevices.current?.iconURL else { return }
//        imageView?.downloadImageFrom(deviceImageUrl, contentMode: .scaleAspectFit)

        self.imageView?.contentMode = .scaleAspectFit
        self.accessoryType = .disclosureIndicator
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }


    override func layoutSubviews() {
        super.layoutSubviews()

        imageView?.frame = CGRect(x: 0, y: 7.5, width: 60, height: bounds.height - 15)

        guard let imageView = imageView else { return }
        if let textLabel = textLabel {
            self.textLabel?.frame = CGRect(x: imageView.frame.origin.x + imageView.frame.size.width, y: textLabel.frame.origin.y,
                                           width: bounds.size.width, height: textLabel.frame.size.height)
        }

        if let detailTextLabel = detailTextLabel {
            self.detailTextLabel?.frame = CGRect(x: imageView.frame.origin.x + imageView.frame.size.width, y: detailTextLabel.frame.origin.y,
                                           width: bounds.size.width, height: detailTextLabel.frame.size.height)
        }

    }

}

extension UIImageView {

    func downloadImageFrom(_ url: URL, contentMode: UIView.ContentMode, _ completion: (() -> Void)? = nil) {

        // Check for cached device image
        let cachePath = FileManager.default.temporaryDirectory.appendingPathComponent("internalmenu.device.cache.png")
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
#endif
