//
//  File.swift
//  
//
//  Created by Brandon Stillitano on 27/9/21.
//

import CoreLocation
import Foundation

protocol GPXParsingProtocol: NSObjectProtocol {
    func parser(_ parser: GPXParser, didCompleteParsing locations: Queue<CLLocation>)
}

class GPXParser: NSObject, XMLParserDelegate {
    private var locations: Queue<CLLocation>
    weak var delegate: GPXParsingProtocol?
    private var parser: XMLParser?
    
    init(forResource file: String, ofType typeName: String) {
        self.locations = Queue<CLLocation>()
        super.init()
        if let content = try? String(contentsOfFile: Bundle.main.path(forResource: file, ofType: typeName)!) {
            let data = content.data(using: .utf8)
            parser = XMLParser.init(data: data!)
            parser?.delegate = self
        }
    }
    
    func parse() {
        self.parser?.parse()
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        switch elementName {
        case "trkpt":
            if let latString =  attributeDict["lat"],
                let lat = Double.init(latString),
                let lonString = attributeDict["lon"],
                let lon = Double.init(lonString) {
                locations.enqueue(CLLocation(latitude: lat, longitude: lon))
            }
        default: break
        }
    }
    
    func parserDidEndDocument(_ parser: XMLParser) {
        delegate?.parser(self, didCompleteParsing: locations)
    }
}
