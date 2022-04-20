//
//  SliderCell.swift
//
//
//  Created by Brandon Stillitano on 18/2/21.
//

import UIKit

protocol SliderCellDelegate: AnyObject {
    func sliderValueChanged(slider: UISlider?, label: UILabel)
}

class SliderCell: UITableViewCell {
    // MARK: - UI Elements
    var slider: UISlider = UISlider()
    var sliderValueLabel: UILabel = UILabel()

    // MARK: - Delegate
    weak var delegate: SliderCellDelegate?

    // MARK: - Constraints
    var textlabelConstraints: [NSLayoutConstraint] = []
    var sliderLabelConstraints: [NSLayoutConstraint] = []
    var sliderConstraints: [NSLayoutConstraint] = []

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .value1, reuseIdentifier: reuseIdentifier)

        /// Setup UI
        textLabel?.adjustsFontSizeToFitWidth = false
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupConstraints() {
        // Set Translations
        textLabel?.translatesAutoresizingMaskIntoConstraints = false
        sliderValueLabel.translatesAutoresizingMaskIntoConstraints = false
        slider.translatesAutoresizingMaskIntoConstraints = false

        // Remove Default Constraints
        NSLayoutConstraint.deactivate(imageView?.constraints ?? [])
        NSLayoutConstraint.deactivate(textLabel?.constraints ?? [])
        NSLayoutConstraint.deactivate(detailTextLabel?.constraints ?? [])

        // Clear Existing Constraints
        NSLayoutConstraint.deactivate(textlabelConstraints)
        NSLayoutConstraint.deactivate(sliderLabelConstraints)
        NSLayoutConstraint.deactivate(sliderConstraints)
        textlabelConstraints.removeAll()
        sliderLabelConstraints.removeAll()
        sliderConstraints.removeAll()

        // Setup Text Label Constraints
        textlabelConstraints.append(textLabel?
            .topAnchor
            .constraint(equalTo: contentView.topAnchor,
                        constant: 16) ?? NSLayoutConstraint())
        textlabelConstraints.append(textLabel?
            .leadingAnchor
            .constraint(equalTo: contentView.leadingAnchor,
                        constant: 16) ?? NSLayoutConstraint())

        // Setup Slider Label Constraints
        sliderLabelConstraints.append(sliderValueLabel
            .trailingAnchor
            .constraint(equalTo: contentView.trailingAnchor,
                        constant: -16))
        sliderLabelConstraints.append(sliderValueLabel
            .centerYAnchor
            .constraint(equalTo: textLabel?.centerYAnchor ?? centerYAnchor))

        // Setup Slider Constraints
        sliderConstraints.append(slider
            .leadingAnchor
            .constraint(equalTo: contentView.leadingAnchor,
                        constant: 16))
        sliderConstraints.append(slider
            .trailingAnchor
            .constraint(equalTo: contentView.trailingAnchor,
                        constant: -16))
        sliderConstraints.append(slider
            .topAnchor
            .constraint(equalTo: textLabel?.bottomAnchor ?? topAnchor,
                        constant: 8))
        sliderConstraints.append(slider
            .bottomAnchor
            .constraint(equalTo: contentView.bottomAnchor,
                        constant: -16))
        
        // Activate Constraints
        NSLayoutConstraint.activate(textlabelConstraints)
        NSLayoutConstraint.activate(sliderLabelConstraints)
        NSLayoutConstraint.activate(sliderConstraints)
    }

    func configureWithRow(_ row: SliderRow) {
        /// Remove existing slider
        slider.removeFromSuperview()
        sliderValueLabel.removeFromSuperview()

        /// Set Delegate
        delegate = row.sliderCellDelegate

        /// Setup Slider
        slider = row.slider
        slider.removeTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        sliderValueLabel = row.sliderValueLabel
        contentView.addSubview(slider)
        contentView.addSubview(sliderValueLabel)

        /// Set text
        textLabel?.text = row.text
        sliderValueLabel.text = "\(Int(row.slider.value))"
        sliderValueLabel.font = detailTextLabel?.font ?? .systemFont(ofSize: 16.0)
        sliderValueLabel.textColor = .systemGray

        /// Relayout Constraints
        setupConstraints()
    }

    @objc
    func sliderValueChanged(_ sender: UISlider?) {
        delegate?.sliderValueChanged(slider: sender, label: sliderValueLabel)
    }
}
