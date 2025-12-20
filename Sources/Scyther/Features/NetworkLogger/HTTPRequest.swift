//
//  HTTPResponse.swift
//
//
//  Created by Brandon Stillitano on 24/12/20.
//

import Foundation

/// Comparison function that determines whether a value conforming to `Comparable` is less than another value conforming to `Comparable`.
/// - Parameters:
///   - lhs: The left-hand side value of the comparison.
///   - rhs: The right-hand side value of the comparison.
/// - Returns: A `Bool` indicating whether `lhs` is less than `rhs`.
@inline(__always)
private func < <T: Comparable>(lhs: T?, rhs: T?) -> Bool {
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
final class HTTPRequest: Sendable, Identifiable {
    /// The cache policy used to fetch/store the request and its corresponding response
    var requestCachePolicy: String?

    /// The date that the request was executed
    var requestDate: Date?

    /// The headers that were sent with the request
    var requestHeaders: [AnyHashable: Any]?

    /// The HTTP method that the request used to connect to the remote
    var requestMethod: String?

    /// The timeout of the response
    var requestTimeout: String?

    /// The length of the body that was sent with the request
    private var requestBodyLength: Int?

    /// The type of the request that was made eg: `application/x-protobuf`
    var requestType: String?

    /// The remote URL that the response was sent to
    var requestURL: String?

    /// `URLComponents` object representing the different components of the `requestURL`
    var requestURLComponents: URLComponents?

    /// Array of `URLQueryItem`s appended onto the `requestURL`
    var requestURLQueryItems: [URLQueryItem]?

    /// A `String` representation of this request formatted as a cURL request
    var requestCurl: String?

    /// The time that the request was executed
    var requestTime: String?

    /// The response code returned from the server for this request
    var responseCode: Int?

    /// The date that the response was received
    var responseDate: Date?

    /// The headers that were received with the response
    var responseHeaders: [AnyHashable: Any]?

    /// The length of the body that was sent with the request
    var responseBodyLength: Int?

    /// The time that the response was received
    var responseTime: String?

    /// The type of the response that was sent eg: `application/x-protobuf`
    var responseType: String?

    /// The time that the request took to execute, from sending the payload/request to receiving a response
    var requestDuration: Float?

    /// A random hash value representing the request
    private var randomHash: NSString?

    /// The short type of the response represented as a string value
    var shortType: String = HTTPModelShortType.OTHER.rawValue

    /// A `Bool` value representing whether or not the request hung/finalised with no response
    var noResponse: Bool = true

    // MARK: - Methods

    /// Saves the details of the given URL request to the model.
    /// - Parameter request: The `URLRequest` object to be saved.
    func saveRequest(_ request: URLRequest) {
        requestDate = Date()
        requestTime = getTimeFromDate(requestDate)
        requestURL = request.urlString
        requestURLComponents = request.urlComponents
        requestURLQueryItems = request.urlComponents?.queryItems
        requestMethod = request.method
        requestCachePolicy = request.cachePolicyString
        requestTimeout = request.timeout
        requestHeaders = request.headers
        requestType = requestHeaders?["Content-Type"] as? String
        requestCurl = request.curlString
    }

    /// Saves the HTTP body of the given URL request to disk.
    /// - Parameter request: The `URLRequest` whose body will be saved.
    func saveRequestBody(_ request: URLRequest) {
        saveRequestBodyData(request.body)
    }

    /// Logs the formatted request entry to the session log file.
    /// - Parameter request: The `URLRequest` to log.
    func logRequest(_ request: URLRequest) {
        formattedRequestLogEntry().appendToFile(filePath: LoggerFilePath.SessionLog)
    }

    /// Saves the current date as the response date to indicate an error response.
    func saveErrorResponse() {
        responseDate = Date()
    }

    /// Saves the details of the given HTTP response and its body data to the model and logs the response.
    /// - Parameters:
    ///   - response: The `URLResponse` object to be saved.
    ///   - data: The response body `Data` to be saved.
    func saveResponse(_ response: URLResponse, data: Data) {
        noResponse = false

        responseDate = Date()
        responseTime = getTimeFromDate(responseDate)
        responseCode = response.statusCodeInt
        responseHeaders = response.headers

        if let contentType = response.headers["Content-Type"] as? String {
            responseType = contentType.components(separatedBy: ";")[0]
            shortType = getShortTypeFrom(responseType ?? "").rawValue
        }

        if let responseDate = responseDate, let requestDate = requestDate {
            requestDuration = Float(responseDate.timeIntervalSince(requestDate) * 1000)
        }

        saveResponseBodyData(data)
        formattedResponseLogEntry().appendToFile(filePath: LoggerFilePath.SessionLog)
    }

    /// Retrieves the request body as a formatted string.
    /// - Returns: The request body as a string, or an empty string if unavailable.
    func getRequestBody() -> String {
        guard let data = readRawData(getRequestBodyFilepath()) else {
            return ""
        }
        return prettyOutput(data, contentType: requestType)
    }

    /// Retrieves the response body as a formatted string.
    /// - Returns: The response body as a string, or an empty string if unavailable.
    func getResponseBody() -> String {
        guard let data = readRawData(getResponseBodyFilepath()) else {
            return ""
        }
        return prettyOutput(data, contentType: responseType)
    }

    /// Retrieves the response body as a dictionary representation suitable for the data browser.
    /// - Returns: A dictionary containing the JSON response body, or an empty dictionary if unavailable or not JSON.
    func getResponseBodyDictionary() -> [String: [String: Any]] {
        guard let data = readRawData(getResponseBodyFilepath()) else { return [:] }
        let jsonString = prettyOutput(data, contentType: responseType)

        // Try parsing as JSON (handles both arrays and dictionaries)
        guard let json = jsonString.jsonRepresentation else { return [:] }

        if let dictionary = json as? [String: Any] {
            // JSON is a dictionary - wrap it
            return ["JSON Body": dictionary]
        } else if let array = json as? [Any] {
            // JSON is an array - convert to indexed dictionary for browsing
            var indexedDict: [String: Any] = [:]
            for (index, element) in array.enumerated() {
                indexedDict["[\(index)]"] = element
            }
            return ["JSON Array (\(array.count) items)": indexedDict]
        }

        return [:]
    }

    /// Returns a random hash string for uniquely identifying this request/response.
    /// - Returns: An `NSString` containing a random hash.
    func getRandomHash() -> NSString {
        if randomHash == nil {
            randomHash = UUID().uuidString as NSString
        }
        return randomHash!
    }

    /// Returns the file path for storing the request body.
    /// - Returns: The full file path for the request body.
    func getRequestBodyFilepath() -> String {
        let dir = getDocumentsPath() as NSString
        return dir.appendingPathComponent(getRequestBodyFilename())
    }

    /// Returns the filename for storing the request body.
    /// - Returns: The filename for the request body.
    func getRequestBodyFilename() -> String {
        guard let requestTime = requestTime else {
            return "logger_request_body_unknown_\(getRandomHash() as String)"
        }
        return "logger_request_body_\(requestTime)_\(getRandomHash() as String)"
    }

    /// Returns the file path for storing the response body.
    /// - Returns: The full file path for the response body.
    func getResponseBodyFilepath() -> String {
        let dir = getDocumentsPath() as NSString
        return dir.appendingPathComponent(getResponseBodyFilename())
    }

    /// Returns the filename for storing the response body.
    /// - Returns: The filename for the response body.
    func getResponseBodyFilename() -> String {
        guard let requestTime = requestTime else {
            return "logger_response_body_unknown_\(getRandomHash() as String)"
        }
        return "logger_response_body_\(requestTime)_\(getRandomHash() as String)"
    }

    /// Returns the path to the application's documents directory.
    /// - Returns: The documents directory path as a string.
    func getDocumentsPath() -> String {
        return NSSearchPathForDirectoriesInDomains(.documentDirectory, .allDomainsMask, true).first!
    }

    /// Saves the provided string data to the specified file.
    /// - Parameters:
    ///   - dataString: The string data to save.
    ///   - toFile: The file path where the data should be saved.
    func saveData(_ dataString: NSString, toFile: String) {
        do {
            try dataString.write(toFile: toFile, atomically: false, encoding: String.Encoding.utf8.rawValue)
        } catch {
            logMessage("catch !!!")
        }
    }

    /// Reads raw data from the specified file path.
    /// - Parameter fromFile: The file path to read data from.
    /// - Returns: The data read from the file, or `nil` if reading fails.
    func readRawData(_ fromFile: String) -> Data? {
        return try? Data(contentsOf: URL(fileURLWithPath: fromFile))
    }

    /// Formats the given date as a time string in "hour:minute" format.
    /// - Parameter date: The `Date` to format.
    /// - Returns: The formatted time string, or `nil` if the date is invalid.
    func getTimeFromDate(_ date: Date?) -> String? {
        guard let date = date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    /// Determines the short type for a given content type string.
    /// - Parameter contentType: The MIME type string to evaluate.
    /// - Returns: The corresponding `HTTPModelShortType`.
    func getShortTypeFrom(_ contentType: String) -> HTTPModelShortType {
        if NSPredicate(format: "SELF MATCHES %@",
                       "^application/(vnd\\.(.*)\\+)?json$").evaluate(with: contentType)
        {
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

    /// Attempts to pretty-print the given raw data based on its type.
    /// - Parameters:
    ///   - rawData: The data to pretty-print.
    ///   - type: The `HTTPModelShortType` representing the data type.
    /// - Returns: A pretty-printed string if possible, or `nil`.
    func prettyPrint(_ rawData: Data, type: HTTPModelShortType) -> String? {
        switch type {
        case .JSON:
            do {
                let json = try JSONSerialization.jsonObject(with: rawData, options: [.mutableContainers])
                let jsonData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
                return String(decoding: jsonData, as: UTF8.self)
            } catch {
                return nil
            }
        default:
            return nil
        }
    }

    /// Returns a formatted log entry string for the current request.
    /// - Returns: The formatted request log entry.
    func formattedRequestLogEntry() -> String {
        var log = String()

        if let requestURL = requestURL {
            log.append("-------START REQUEST -  \(requestURL) -------\n")
        }

        if let requestMethod = requestMethod {
            log.append("[Request Method] \(requestMethod)\n")
        }

        if let requestDate = requestDate {
            log.append("[Request Date] \(requestDate)\n")
        }

        if let requestTime = requestTime {
            log.append("[Request Time] \(requestTime)\n")
        }

        if let requestType = requestType {
            log.append("[Request Type] \(requestType)\n")
        }

        if let requestTimeout = requestTimeout {
            log.append("[Request Timeout] \(requestTimeout)\n")
        }

        if let requestHeaders = requestHeaders {
            log.append("[Request Headers]\n\(requestHeaders)\n")
        }

        log.append("[Request Body]\n \(getRequestBody())\n")

        if let requestURL = requestURL {
            log.append("-------END REQUEST - \(requestURL) -------\n\n")
        }

        return log
    }

    /// Returns a formatted log entry string for the current response.
    /// - Returns: The formatted response log entry.
    func formattedResponseLogEntry() -> String {
        var log = String()

        if let requestURL = requestURL {
            log.append("-------START RESPONSE -  \(requestURL) -------\n")
        }

        if let responseStatus = responseCode {
            log.append("[Response Status] \(responseStatus)\n")
        }

        if let responseType = responseType {
            log.append("[Response Type] \(responseType)\n")
        }

        if let responseDate = responseDate {
            log.append("[Response Date] \(responseDate)\n")
        }

        if let responseTime = responseTime {
            log.append("[Response Time] \(responseTime)\n")
        }

        if let responseHeaders = responseHeaders {
            log.append("[Response Headers]\n\(responseHeaders)\n\n")
        }

        log.append("[Response Body]\n \(getResponseBody())\n")

        if let requestURL = requestURL {
            log.append("-------END RESPONSE - \(requestURL) -------\n\n")
        }

        return log
    }

    // MARK: - Private Methods

    private func saveRequestBodyData(_ data: Data?) {
        guard let data = data else {
            return
        }
        let tempBodyString = NSString(data: data, encoding: String.Encoding.utf8.rawValue)
        requestBodyLength = data.count
        if let tempBodyString = tempBodyString {
            saveData(tempBodyString, toFile: getRequestBodyFilepath())
        }
    }

    private func saveResponseBodyData(_ data: Data) {
        var bodyString: NSString?

        if shortType == HTTPModelShortType.IMAGE.rawValue {
            bodyString = data.base64EncodedString(options: .endLineWithLineFeed) as NSString?
        } else {
            if let tempBodyString = NSString(data: data, encoding: String.Encoding.utf8.rawValue) {
                bodyString = tempBodyString
            }
        }

        if let bodyString = bodyString {
            responseBodyLength = data.count
            saveData(bodyString, toFile: getResponseBodyFilepath())
        }
    }

    private func prettyOutput(_ rawData: Data, contentType: String? = nil) -> String {
        if let contentType = contentType {
            let shortType = getShortTypeFrom(contentType)
            if let output = prettyPrint(rawData, type: shortType) {
                return output
            }
        }
        return String(decoding: rawData, as: UTF8.self)
    }
}
