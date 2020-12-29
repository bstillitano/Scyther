//
//  NetworkLogRow.swift
//  
//
//  Created by Brandon Stillitano on 25/12/20.
//

#if !os(macOS)
import UIKit

class NetworkLogRow: Row {
    public init() {}
    
    var style: RowStyle = .networkLog
    var actionBlock: ActionBlock?
    var isHidden: Bool = false
    var text: String?
    var detailText: String?
    var accessoryView: UIView?
    var image: UIImage?
    var imageURL: URL?
    var accessoryType: UITableViewCell.AccessoryType? = .disclosureIndicator
    
    /// Color representing the response code of the network request
    var httpStatusColor: UIColor = .systemGray
    
    /// String representing representing the HTTP Method used to make the request: E.g: `GET`, `POST`, `PUT`.
    var httpMethod: String?
    
    /// Int value representing the response from the remote server. E.g: `200`, `304`, `404`.
    var httpStatusCode: Int?
    
    /// String value representing the time either elapsed (if request is still in progress) OR the time the request took to complete (if request is finished).
    var httpRequestTime: String?
    
    /// String value representing the url that the request was sent to
    var httpRequestURL: String?
    
    /// The `HTTPModel` that represents this request
    var httpModel: LoggerHTTPModel?
}
#endif
