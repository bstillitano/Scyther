//
//  ScytherHTTPModel.swift
//
//
//  Created by Brandon Stillitano on 24/12/20.
//

import Foundation

/// Comparison function that determines whether a value that conforms `Comparable` is less than another value that conforms to `Comparable`.
/// - Parameters:
///   - lhs: The value that will be used as the left hand side of the equation. That is to say that if this value is 1 and `rhs` is 2, this function will return true.
///   - rhs: The value that will be used as the right hand side of the equation. That is to say that if this value is 1 and `lhs` is 2, this function will return false.
/// - Returns: A `Bool` value indicating whether the comparison was true or false
fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
    switch (lhs, rhs) {
    case let (l?, r?):
        return l < r
    case (nil, _?):
        return true
    default:
        return false
    }
}

/// Object Model representing a HTTP request
@objc public class LoggerHTTPModel: NSObject {
    /// The remote URL that the response was sent to
    @objc public var requestURL: String?
    
    /// `URLComponents` objcet representing the different components of the `requestURL
    @objc public var requestURLComponents: URLComponents?
    
    /// Array of `URLQueryItem`'s appended onto the `requestURL`
    @objc public var requestURLQueryItems: [URLQueryItem]?
    
    /// HTTP method that the request used to connect to the remote
    @objc public var requestMethod: String?
    
    /// Cache policy used to fetch/store the request and its corresponding response
    @objc public var requestCachePolicy: String?
    
    /// The date that the request was executed
    @objc public var requestDate: Date?
    
    /// The time that the request was executed
    @objc public var requestTime: String?
    
    /// The timeout of the response
    @objc public var requestTimeout: String?
    
    /// The headers that were sent with the response
    @objc public var requestHeaders: [AnyHashable: Any]?
    
    /// The length of the body that was sent with the request
    public var requestBodyLength: Int?
    
    /// The type of the request that was made eg: `application/x-protobuf`
    @objc public var requestType: String?
    
    /// A `String` representation of this request formatted as a cURL request
    @objc public var requestCurl: String?

    /// The response code returned from the server for this request
    public var responseStatus: Int?
    
    /// The type of the response that was sent eg: `application/x-protobuf`
    @objc public var responseType: String?
    
    /// The date that the response was received
    @objc public var responseDate: Date?
    
    /// The time that the response was received
    @objc public var responseTime: String?
    
    /// The headers that were received with the response
    @objc public var responseHeaders: [AnyHashable: Any]?
    
    /// The length of the body that was sent with the request
    public var responseBodyLength: Int?

    /// The time that the request took to execute, from sending the payload/request to receiving a response
    public var requestDuration: Float?

    /// A random hash value representing the request
    @objc public var randomHash: NSString?

    /// The short type of the response represented as a string value
    @objc public var shortType: String = HTTPModelShortType.OTHER.rawValue

    /// A `Bool` value representing whether or not the request hung/finalised with no response
    @objc public var noResponse: Bool = true

    /// Setter method for this objects variables
    func saveRequest(_ request: URLRequest) {
        self.requestDate = Date()
        self.requestTime = getTimeFromDate(self.requestDate!)
        self.requestURL = request.urlString
        self.requestURLComponents = request.urlComponents
        self.requestURLQueryItems = request.urlComponents?.queryItems
        self.requestMethod = request.method
        self.requestCachePolicy = request.cachePolicyString
        self.requestTimeout = request.timeout
        self.requestHeaders = request.headers
        self.requestType = requestHeaders?["Content-Type"] as? String
        self.requestCurl = request.curlString
    }

    func saveRequestBody(_ request: URLRequest) {
        saveRequestBodyData(request.body)
    }

    func logRequest(_ request: URLRequest) {
        formattedRequestLogEntry().appendToFile(filePath: LoggerFilePath.SessionLog)
    }

    func saveErrorResponse() {
        self.responseDate = Date()
    }

    func saveResponse(_ response: URLResponse, data: Data) {
        self.noResponse = false

        self.responseDate = Date()
        self.responseTime = getTimeFromDate(self.responseDate!)
        self.responseStatus = response.statusCodeInt
        self.responseHeaders = response.headers

        let headers = response.headers

        if let contentType = headers["Content-Type"] as? String {
            self.responseType = contentType.components(separatedBy: ";")[0]
            self.shortType = getShortTypeFrom(self.responseType ?? "").rawValue
        }

        self.requestDuration = Float(self.responseDate!.timeIntervalSince(self.requestDate!))

        saveResponseBodyData(data)
        formattedResponseLogEntry().appendToFile(filePath: LoggerFilePath.SessionLog)
    }

    func saveRequestBodyData(_ data: Data?) {
        guard let data = data else {
            return
        }
        let tempBodyString = NSString.init(data: data, encoding: String.Encoding.utf8.rawValue)
        self.requestBodyLength = data.count
        if (tempBodyString != nil) {
            saveData(tempBodyString!, toFile: getRequestBodyFilepath())
        }
    }

    func saveResponseBodyData(_ data: Data) {
        var bodyString: NSString?

        if self.shortType as String == HTTPModelShortType.IMAGE.rawValue {
            bodyString = data.base64EncodedString(options: .endLineWithLineFeed) as NSString?

        } else {
            if let tempBodyString = NSString.init(data: data, encoding: String.Encoding.utf8.rawValue) {
                bodyString = tempBodyString
            }
        }

        if (bodyString != nil) {
            self.responseBodyLength = data.count
            saveData(bodyString!, toFile: getResponseBodyFilepath())
        }

    }

    fileprivate func prettyOutput(_ rawData: Data, contentType: String? = nil) -> NSString {
        if let contentType = contentType {
            let shortType = getShortTypeFrom(contentType)
            if let output = prettyPrint(rawData, type: shortType) {
                return output as NSString
            }
        }
        return NSString(data: rawData, encoding: String.Encoding.utf8.rawValue) ?? ""
    }

    @objc public func getRequestBody() -> NSString {
        guard let data = readRawData(getRequestBodyFilepath()) else {
            return ""
        }
        return prettyOutput(data, contentType: requestType)
    }

    @objc public func getResponseBody() -> NSString {
        guard let data = readRawData(getResponseBodyFilepath()) else {
            return ""
        }

        return prettyOutput(data, contentType: responseType)
    }
    
    @objc public func getResponseBodyDictionary() -> [String: [String: Any]] {
        guard let data = readRawData(getResponseBodyFilepath()) else {
            return [:]
        }

        return [
            "Network Response Body": [
                "JSON Response": prettyOutput(data, contentType: responseType)
            ]
        ]
    }

    @objc public func getRandomHash() -> NSString {
        if !(self.randomHash != nil) {
            self.randomHash = UUID().uuidString as NSString?
        }
        return self.randomHash!
    }

    @objc public func getRequestBodyFilepath() -> String {
        let dir = getDocumentsPath() as NSString
        return dir.appendingPathComponent(getRequestBodyFilename())
    }

    @objc public func getRequestBodyFilename() -> String {
        return String("logger_request_body_") + "\(self.requestTime!)_\(getRandomHash() as String)"
    }

    @objc public func getResponseBodyFilepath() -> String {
        let dir = getDocumentsPath() as NSString
        return dir.appendingPathComponent(getResponseBodyFilename())
    }

    @objc public func getResponseBodyFilename() -> String {
        return String("logger_response_body_") + "\(self.requestTime!)_\(getRandomHash() as String)"
    }

    @objc public func getDocumentsPath() -> String {
        return NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory, FileManager.SearchPathDomainMask.allDomainsMask, true).first!
    }

    @objc public func saveData(_ dataString: NSString, toFile: String) {
        do {
            try dataString.write(toFile: toFile, atomically: false, encoding: String.Encoding.utf8.rawValue)
        } catch {
            logMessage("catch !!!")
        }
    }

    @objc public func readRawData(_ fromFile: String) -> Data? {
        return (try? Data(contentsOf: URL(fileURLWithPath: fromFile)))
    }

    @objc public func getTimeFromDate(_ date: Date) -> String? {
        let calendar = Calendar.current
        let components = (calendar as NSCalendar).components([.hour, .minute], from: date)
        guard let hour = components.hour, let minutes = components.minute else {
            return nil
        }
        if minutes < 10 {
            return "\(hour):0\(minutes)"
        } else {
            return "\(hour):\(minutes)"
        }
    }

    public func getShortTypeFrom(_ contentType: String) -> HTTPModelShortType {
        if NSPredicate(format: "SELF MATCHES %@",
            "^application/(vnd\\.(.*)\\+)?json$").evaluate(with: contentType) {
            return .JSON
        }

        if (contentType == "application/xml") || (contentType == "text/xml") {
            return .XML
        }

        if contentType == "text/html" {
            return .HTML
        }

        if contentType.hasPrefix("image/") {
            return .IMAGE
        }

        return .OTHER
    }

    public func prettyPrint(_ rawData: Data, type: HTTPModelShortType) -> NSString? {
        switch type {
        case .JSON:
            do {
                let rawJsonData = try JSONSerialization.jsonObject(with: rawData, options: [])
                let prettyPrintedString = try JSONSerialization.data(withJSONObject: rawJsonData, options: [.prettyPrinted])
                return NSString(data: prettyPrintedString, encoding: String.Encoding.utf8.rawValue)
            } catch {
                return nil
            }
        default:
            return nil
        }
    }

    @objc public func formattedRequestLogEntry() -> String {
        var log = String()

        if let requestURL = self.requestURL {
            log.append("-------START REQUEST -  \(requestURL) -------\n")
        }

        if let requestMethod = self.requestMethod {
            log.append("[Request Method] \(requestMethod)\n")
        }

        if let requestDate = self.requestDate {
            log.append("[Request Date] \(requestDate)\n")
        }

        if let requestTime = self.requestTime {
            log.append("[Request Time] \(requestTime)\n")
        }

        if let requestType = self.requestType {
            log.append("[Request Type] \(requestType)\n")
        }

        if let requestTimeout = self.requestTimeout {
            log.append("[Request Timeout] \(requestTimeout)\n")
        }

        if let requestHeaders = self.requestHeaders {
            log.append("[Request Headers]\n\(requestHeaders)\n")
        }

        log.append("[Request Body]\n \(getRequestBody())\n")

        if let requestURL = self.requestURL {
            log.append("-------END REQUEST - \(requestURL) -------\n\n")
        }

        return log;
    }

    @objc public func formattedResponseLogEntry() -> String {
        var log = String()

        if let requestURL = self.requestURL {
            log.append("-------START RESPONSE -  \(requestURL) -------\n")
        }

        if let responseStatus = self.responseStatus {
            log.append("[Response Status] \(responseStatus)\n")
        }

        if let responseType = self.responseType {
            log.append("[Response Type] \(responseType)\n")
        }

        if let responseDate = self.responseDate {
            log.append("[Response Date] \(responseDate)\n")
        }

        if let responseTime = self.responseTime {
            log.append("[Response Time] \(responseTime)\n")
        }

        if let responseHeaders = self.responseHeaders {
            log.append("[Response Headers]\n\(responseHeaders)\n\n")
        }

        log.append("[Response Body]\n \(getResponseBody())\n")

        if let requestURL = self.requestURL {
            log.append("-------END RESPONSE - \(requestURL) -------\n\n")
        }

        return log
    }
}
