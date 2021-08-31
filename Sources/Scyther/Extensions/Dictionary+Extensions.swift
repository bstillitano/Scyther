//
//  File.swift
//  
//
//  Created by Brandon Stillitano on 31/8/21.
//

import Foundation

extension Dictionary {
    public var jsonString: String? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: self, options: []) else {
            return nil
        }
        return String(data: jsonData, encoding: String.Encoding.ascii)
        
    }
}

