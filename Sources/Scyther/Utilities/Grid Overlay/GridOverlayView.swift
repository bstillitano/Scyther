//
//  GridOverlayView.swift
//
//
//  Created by Brandon Stillitano on 16/2/21.
//

import UIKit

public enum GridOverlayColorScheme {
    case red
    case green
    case blue

    var primaryColor: UIColor {
        switch self {
        case .red:
            return .systemRed
        case .green:
            return .systemGreen
        case .blue:
            return .systemBlue
        }
    }

    var secondaryColor: UIColor {
        switch self {
        case .red:
            return .white
        case .green:
            return .white
        case .blue:
            return .white
        }
    }
}

public class GridOverlayView: UIView {
    // MARK: - Static Data
    static var DBGridOverlayViewMinHorizontalMiddlePartSize: Int = 8
    static var DBGridOverlayViewMinVerticalMiddlePartSize: Int = 8
    static var DBGridOverlayViewLabelFontSize: CGFloat = 9.0
    static var DBGridOverlayViewHorizontalLabelTopOffset: CGFloat = 72.0
    static var DBGridOverlayViewVerticalLabelRightOffset: CGFloat = 32.0
    static var DBGridOverlayViewVerticalLabelContentOffsets: CGFloat = 4.0

    // MARK: - UI Elements
    private var horizontalLabel: UILabel = UILabel()
    private var verticalLabel: UILabel = UILabel()

    // MARK: - Data
    /// Distance in points between consecutive lines of the grid.
    public var gridSize: Int = 8 {
        didSet {
            setNeedsDisplay()
        }
    }

    ///Opacity of the grid overlay
    public var opacity: CGFloat = 1.0 {
        didSet {
            setNeedsDisplay()
        }
    }

    ///Color scheme of the grid overlay
    public var colorScheme: GridOverlayColorScheme = .red {
        didSet {
            setupLabels()
            setNeedsDisplay()
        }
    }

    // MARK: - Init
    public override init(frame: CGRect) {
        super.init(frame: frame)

        //Setup Interface
        setupUI()
        setupLabels()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        updateFrame()
        isUserInteractionEnabled = false
        isOpaque = false
    }

    private func updateFrame() {
        frame = UIScreen.main.bounds
        setNeedsDisplay()
    }

    private func setupLabels() {
        //Setup Vertical Label
        verticalLabel.font = .systemFont(ofSize: 9.0)
        verticalLabel.textColor = colorScheme.secondaryColor
        verticalLabel.backgroundColor = colorScheme.primaryColor
        verticalLabel.textAlignment = .center
        addSubview(verticalLabel)

        //Setup Horizontal Label
        horizontalLabel.font = .systemFont(ofSize: 9.0)
        horizontalLabel.textColor = colorScheme.secondaryColor
        horizontalLabel.backgroundColor = colorScheme.primaryColor
        horizontalLabel.textAlignment = .center
        addSubview(horizontalLabel)
    }

    // MARK: - Drawing
    public override func draw(_ rect: CGRect) {
        super.draw(rect)

        //Calculate Grid Size
        let context = UIGraphicsGetCurrentContext()
        let lineWidth = 1.0 / UIScreen.main.scale
        var linesPerHalf = Int(frame.size.width) / (2 * gridSize)
        var screenSize = Int(frame.size.width)
        var middlePartSize = screenSize - linesPerHalf * 2 * gridSize

        //Show/Hide Horizontal Label
        var showsLabel = middlePartSize > 0
        if middlePartSize < GridOverlayView.DBGridOverlayViewMinHorizontalMiddlePartSize && showsLabel {
            linesPerHalf -= (GridOverlayView.DBGridOverlayViewMinHorizontalMiddlePartSize - middlePartSize + 2 * gridSize - 1) / (2 * gridSize)
            middlePartSize = screenSize - linesPerHalf * 2 * gridSize
        }

        //Setup Horizontal Label
        if showsLabel {
            horizontalLabel.text = String(format: "%d", middlePartSize)
            horizontalLabel.sizeToFit()

            let labelSize: CGSize = horizontalLabel.frame.size
            horizontalLabel.frame = CGRect(x: CGFloat(linesPerHalf * gridSize) - lineWidth,
                                           y: GridOverlayView.DBGridOverlayViewHorizontalLabelTopOffset,
                                           width: CGFloat(middlePartSize) + 2 * lineWidth,
                                           height: labelSize.height)
        } else {
            horizontalLabel.frame = .zero
        }

        //Add Horizontal Lines
        for lineIndex: Int in 1...linesPerHalf {
            context?.setStrokeColor(colorScheme.primaryColor.cgColor)
            context?.setLineWidth(lineWidth)
            context?.move(to: CGPoint(x: CGFloat(lineIndex * gridSize) - lineWidth,
                                      y: 0))
            context?.addLine(to: CGPoint(x: CGFloat(lineIndex * gridSize) - lineWidth,
                                         y: bounds.height))
            context?.strokePath()
        }

        //Recalculate Data
        linesPerHalf = Int(frame.size.height) / (2 * gridSize)
        screenSize = Int(frame.size.height)
        middlePartSize = screenSize - linesPerHalf * 2 * gridSize

        //Show/Hide Vertical Label
        showsLabel = middlePartSize > 0
        if middlePartSize < GridOverlayView.DBGridOverlayViewMinVerticalMiddlePartSize && showsLabel {
            linesPerHalf -= (GridOverlayView.DBGridOverlayViewMinVerticalMiddlePartSize - middlePartSize + 2 * gridSize - 1) / (2 * gridSize)
            middlePartSize = screenSize - linesPerHalf * 2 * gridSize
        }

        //Setup Vertical Label
        if showsLabel {
            verticalLabel.text = String(format: "%d", middlePartSize)
            verticalLabel.sizeToFit()

            let labelSize: CGSize = verticalLabel.frame.size
            let labelWidth: CGFloat = labelSize.width + GridOverlayView.DBGridOverlayViewVerticalLabelContentOffsets
            verticalLabel.frame = CGRect(x: frame.size.width - GridOverlayView.DBGridOverlayViewVerticalLabelRightOffset - labelWidth,
                                         y: CGFloat(linesPerHalf * gridSize) - lineWidth,
                                         width: labelWidth,
                                         height: CGFloat(middlePartSize) + 2 * lineWidth)
        } else {
            verticalLabel.frame = .zero
        }

        //Add Vertical Lines
        for lineIndex: Int in 1...linesPerHalf {
            context?.setStrokeColor(colorScheme.primaryColor.cgColor)
            context?.setLineWidth(lineWidth)
            context?.move(to: CGPoint(x: 0,
                                      y: CGFloat(lineIndex * gridSize) - lineWidth))
            context?.addLine(to: CGPoint(x: bounds.width,
                                         y: CGFloat(lineIndex * gridSize) - lineWidth))
            context?.strokePath()
        }
        for lineIndex: Int in 1...linesPerHalf {
            context?.setStrokeColor(colorScheme.primaryColor.cgColor)
            context?.setLineWidth(lineWidth)
            context?.move(to: CGPoint(x: 0,
                                      y: CGFloat(lineIndex * gridSize) - lineWidth + verticalLabel.frame.origin.y + verticalLabel.frame.size.height))
            context?.addLine(to: CGPoint(x: bounds.width,
                                         y: CGFloat(lineIndex * gridSize) - lineWidth + verticalLabel.frame.origin.y + verticalLabel.frame.size.height))
            context?.strokePath()
        }
    }
}
