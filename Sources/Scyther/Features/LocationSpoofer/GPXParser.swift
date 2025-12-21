//
//  GPXParser.swift
//
//
//  Created by Brandon Stillitano on 27/9/21.
//

import CoreLocation
import Foundation

/// Protocol for receiving GPX parsing completion callbacks.
///
/// Implement this protocol to be notified when a GPX file has been fully parsed
/// and the location queue is ready for use.
@MainActor
internal protocol GPXParsingProtocol: NSObjectProtocol {
    /// Called when GPX parsing is complete.
    ///
    /// - Parameters:
    ///   - parser: The parser that completed parsing.
    ///   - locations: A queue containing all parsed locations in order.
    func parser(_ parser: GPXParser, didCompleteParsing locations: Queue<CLLocation>)
}

/// Parses GPX (GPS Exchange Format) files to extract location coordinates.
///
/// `GPXParser` uses `XMLParser` to read GPX files and extract track points (`<trkpt>`)
/// into a queue of `CLLocation` objects. This is used by the location spoofer to load
/// routes from GPX files.
///
/// ## Supported GPX Elements
/// - `<trkpt>`: Track points with `lat` and `lon` attributes
///
/// ## Usage
/// ```swift
/// class MyClass: GPXParsingProtocol {
///     func setupParser() {
///         let parser = GPXParser(forResource: "MyRoute", ofType: "gpx")
///         parser.delegate = self
///         parser.parse()
///     }
///
///     func parser(_ parser: GPXParser, didCompleteParsing locations: Queue<CLLocation>) {
///         // Use the parsed locations
///     }
/// }
/// ```
internal final class GPXParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    /// Queue of locations extracted from the GPX file.
    private var locations: Queue<CLLocation>

    /// Delegate that receives parsing completion notifications.
    weak var delegate: GPXParsingProtocol?

    /// The underlying XML parser.
    private var parser: XMLParser?

    /// Creates a parser for a GPX file in the app bundle.
    ///
    /// - Parameters:
    ///   - file: The name of the GPX file (without extension).
    ///   - typeName: The file extension (typically "gpx").
    init(forResource file: String, ofType typeName: String) {
        self.locations = Queue<CLLocation>()
        super.init()
        if let content = try? String(contentsOfFile: Bundle.module.path(forResource: file, ofType: typeName) ?? "") {
            let data = content.data(using: .utf8)
            parser = XMLParser.init(data: data ?? Data())
            parser?.delegate = self
        }
    }

    /// Creates a parser for a dynamically generated GPX string from a `Location`.
    ///
    /// - Parameter location: The location to convert to GPX format.
    init(forLocation location: Location) {
        self.locations = Queue<CLLocation>()
        super.init()
        if let content = location.gpxString {
            let data = content.data(using: .utf8)
            parser = XMLParser.init(data: data ?? Data())
            parser?.delegate = self
        }
    }

    /// Begins parsing the GPX file.
    ///
    /// Call this method after setting the delegate to start extracting locations.
    /// When complete, the delegate's `parser(_:didCompleteParsing:)` method is called.
    func parse() {
        self.parser?.parse()
    }

    /// XMLParserDelegate method called when an XML element is encountered.
    ///
    /// Extracts latitude and longitude from `<trkpt>` elements and creates `CLLocation` objects.
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "trkpt":
            if let latString = attributeDict["lat"],
                let lat = Double.init(latString),
                let lonString = attributeDict["lon"],
                let lon = Double.init(lonString) {
                locations.enqueue(CLLocation(latitude: lat, longitude: lon))
            }

        default:
            break
        }
    }

    /// XMLParserDelegate method called when parsing completes.
    ///
    /// Notifies the delegate that all locations have been parsed and are ready to use.
    func parserDidEndDocument(_ parser: XMLParser) {
        let parsedLocations = locations
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.parser(self, didCompleteParsing: parsedLocations)
        }
    }
}
