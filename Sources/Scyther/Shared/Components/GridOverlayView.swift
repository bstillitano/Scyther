//
//  GridOverlayView.swift
//
//
//  Created by Brandon Stillitano on 16/2/21.
//

#if !os(macOS)
import UIKit

/// Defines the available color schemes for the grid overlay.
///
/// The color scheme determines the visual appearance of the grid lines and labels,
/// allowing developers to choose a color that provides good contrast against their
/// app's content.
///
/// ## Available Schemes
///
/// Each color scheme provides:
/// - A primary color for grid lines and label backgrounds
/// - A secondary color for label text
///
/// ```swift
/// // Use the red color scheme
/// gridOverlay.colorScheme = .red
///
/// // Or choose blue for better contrast
/// gridOverlay.colorScheme = .blue
/// ```
public enum GridOverlayColorScheme: String, CaseIterable {
    /// Red color scheme with red grid lines and white labels.
    case red

    /// Green color scheme with green grid lines and white labels.
    case green

    /// Blue color scheme with blue grid lines and white labels.
    case blue

    /// The primary color used for grid lines and label backgrounds.
    ///
    /// This color is derived from system color palettes to ensure
    /// consistency with iOS design guidelines.
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

    /// The secondary color used for label text.
    ///
    /// Currently all schemes use white text for optimal readability
    /// against the colored label backgrounds.
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

/// A view that overlays a grid pattern on top of the screen to assist with UI layout and spacing verification.
///
/// `GridOverlayView` is a debugging tool that helps developers ensure consistent spacing and
/// alignment across their app's interface. It displays a grid of evenly-spaced lines with
/// labels showing the spacing measurements.
///
/// ## Features
///
/// - Configurable grid spacing
/// - Multiple color schemes for visibility
/// - Adjustable opacity
/// - Automatic screen size adaptation
/// - Measurement labels at grid center points
///
/// ## Usage Example
///
/// ```swift
/// let gridOverlay = GridOverlayView()
/// gridOverlay.gridSize = 8  // 8pt spacing
/// gridOverlay.colorScheme = .red
/// gridOverlay.opacity = 0.5
/// window.addSubview(gridOverlay)
/// ```
///
/// The grid automatically updates when the device rotates or when properties change.
///
/// - Note: This view is non-interactive and won't block touches to underlying views.
internal class GridOverlayView: TopLevelView {
    // MARK: - Static Data

    /// Minimum size in points for the horizontal center section to display its label.
    static var MinHorizontalMiddlePartSize: Int = 8

    /// Minimum size in points for the vertical center section to display its label.
    static var MinVerticalMiddlePartSize: Int = 8

    /// Font size for measurement labels.
    static var LabelFontSize: CGFloat = 9.0

    /// Vertical offset from the top of the screen for the horizontal measurement label.
    static var HorizontalLabelTopOffset: CGFloat = 72.0

    /// Horizontal offset from the right edge of the screen for the vertical measurement label.
    static var VerticalLabelRightOffset: CGFloat = 32.0

    /// Additional padding inside the vertical measurement label.
    static var VerticalLabelContentOffsets: CGFloat = 4.0

    // MARK: - UI Elements

    /// Label displaying the horizontal center spacing measurement.
    private var horizontalLabel: UILabel = UILabel()

    /// Label displaying the vertical center spacing measurement.
    private var verticalLabel: UILabel = UILabel()

    // MARK: - Data

    /// Distance in points between consecutive grid lines.
    ///
    /// Common values are 4, 8, or 16 points to align with common spacing increments.
    /// Changing this value automatically triggers a redraw of the grid.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Use 8pt grid for standard spacing
    /// gridOverlay.gridSize = 8
    ///
    /// // Use 4pt grid for fine-grained alignment
    /// gridOverlay.gridSize = 4
    /// ```
    public var gridSize: Int = 8 {
        didSet {
            setNeedsDisplay()
        }
    }

    /// Opacity of the grid overlay, from 0.0 (invisible) to 1.0 (fully opaque).
    ///
    /// Adjusting the opacity helps balance visibility of the grid against
    /// the underlying content. Lower values (e.g., 0.3-0.5) are often ideal
    /// for maintaining visibility of both grid and content.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Make grid semi-transparent
    /// gridOverlay.opacity = 0.4
    /// ```
    public var opacity: CGFloat = 1.0 {
        didSet {
            alpha = opacity
            setNeedsDisplay()
        }
    }

    /// Color scheme of the grid overlay.
    ///
    /// Choose a color that provides good contrast against your app's content.
    /// Red is often used as it stands out against most backgrounds, but blue
    /// or green may work better depending on your app's color palette.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Use blue grid for apps with red content
    /// gridOverlay.colorScheme = .blue
    /// ```
    public var colorScheme: GridOverlayColorScheme = .red {
        didSet {
            setupLabels()
            setNeedsDisplay()
        }
    }

    // MARK: - Init

    /// Initializes a new grid overlay view with the specified frame.
    ///
    /// The view is automatically configured to be non-interactive and sized
    /// to match the screen bounds.
    ///
    /// - Parameter frame: The frame rectangle for the view. This is typically
    ///   set to match the screen bounds but will be updated automatically.
    public override init(frame: CGRect) {
        super.init(frame: frame)

        //Setup Interface
        setupUI()
        setupLabels()
    }

    /// Required initializer for loading from a storyboard or nib.
    ///
    /// This initializer is not implemented as `GridOverlayView` is designed
    /// to be created programmatically.
    ///
    /// - Parameter coder: An unarchiver object
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Configures the basic UI properties of the view.
    ///
    /// Sets up the view to be non-interactive and transparent so it doesn't
    /// interfere with the underlying app interface.
    private func setupUI() {
        updateFrame()
        isUserInteractionEnabled = false
        isOpaque = false
    }

    /// Updates the view's frame to match the current screen bounds.
    ///
    /// This method is called when the device rotates or when the view is
    /// first initialized to ensure the grid covers the entire screen.
    internal override func updateFrame() {
        frame = UIScreen.main.bounds
        setNeedsDisplay()
    }

    /// Configures the measurement labels with the current color scheme.
    ///
    /// Creates and styles the horizontal and vertical labels that display
    /// the center spacing measurements. This method is called when the
    /// view is initialized and whenever the color scheme changes.
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

    /// Draws the grid lines and measurement labels.
    ///
    /// This method is called automatically by the system when the view needs
    /// to be rendered. It calculates the grid layout, draws vertical and
    /// horizontal lines at regular intervals, and positions the measurement labels.
    ///
    /// The grid is drawn symmetrically from the center outwards, with labels
    /// showing the spacing in the center sections when there's sufficient room.
    ///
    /// - Parameter rect: The portion of the view's bounds that needs to be updated
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
        if middlePartSize < GridOverlayView.MinHorizontalMiddlePartSize && showsLabel {
            linesPerHalf -= (GridOverlayView.MinHorizontalMiddlePartSize - middlePartSize + 2 * gridSize - 1) / (2 * gridSize)
            middlePartSize = screenSize - linesPerHalf * 2 * gridSize
        }

        //Setup Horizontal Label
        if showsLabel {
            horizontalLabel.text = String(format: "%d", middlePartSize)
            horizontalLabel.sizeToFit()

            let labelSize: CGSize = horizontalLabel.frame.size
            horizontalLabel.frame = CGRect(x: CGFloat(linesPerHalf * gridSize) - lineWidth,
                                           y: GridOverlayView.HorizontalLabelTopOffset,
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
        for lineIndex: Int in 0...linesPerHalf + 1 {
            context?.setStrokeColor(colorScheme.primaryColor.cgColor)
            context?.setLineWidth(lineWidth)
            context?.move(to: CGPoint(x: CGFloat(lineIndex * gridSize) - lineWidth + horizontalLabel.frame.origin.x + horizontalLabel.frame.size.width,
                                      y: 0))
            context?.addLine(to: CGPoint(x: CGFloat(lineIndex * gridSize) - lineWidth + horizontalLabel.frame.origin.x + horizontalLabel.frame.size.width,
                                         y: bounds.height))
            context?.strokePath()
        }

        //Recalculate Data
        linesPerHalf = Int(frame.size.height) / (2 * gridSize)
        screenSize = Int(frame.size.height)
        middlePartSize = screenSize - linesPerHalf * 2 * gridSize

        //Show/Hide Vertical Label
        showsLabel = middlePartSize > 0
        if middlePartSize < GridOverlayView.MinVerticalMiddlePartSize && showsLabel {
            linesPerHalf -= (GridOverlayView.MinVerticalMiddlePartSize - middlePartSize + 2 * gridSize - 1) / (2 * gridSize)
            middlePartSize = screenSize - linesPerHalf * 2 * gridSize
        }

        //Setup Vertical Label
        if showsLabel {
            verticalLabel.text = String(format: "%d", middlePartSize)
            verticalLabel.sizeToFit()

            let labelSize: CGSize = verticalLabel.frame.size
            let labelWidth: CGFloat = labelSize.width + GridOverlayView.VerticalLabelContentOffsets
            verticalLabel.frame = CGRect(x: frame.size.width - GridOverlayView.VerticalLabelRightOffset - labelWidth,
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
        for lineIndex: Int in 0...linesPerHalf + 1 {
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
#endif
