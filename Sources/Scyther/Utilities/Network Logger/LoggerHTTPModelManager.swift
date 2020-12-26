//
//  LoggerHTTPModelManager.swift
//  
//
//  Created by Brandon Stillitano on 24/12/20.
//

import Foundation

private let _sharedInstance = LoggerHTTPModelManager()

final class LoggerHTTPModelManager: NSObject {
    static let sharedInstance = LoggerHTTPModelManager()
    fileprivate var models = [LoggerHTTPModel]()
    private let syncQueue = DispatchQueue(label: "LoggerSyncQueue")
    
    func add(_ obj: LoggerHTTPModel) {
        syncQueue.async {
            self.models.insert(obj, at: 0)
            NotificationCenter.default.post(name: NSNotification.Name.LoggerAddedModel, object: obj)
        }
    }
    
    func clear() {
        syncQueue.async {
            self.models.removeAll()
            NotificationCenter.default.post(name: NSNotification.Name.LoggerClearedModels, object: nil)
        }
    }
    
    func getModels() -> [LoggerHTTPModel] {
        var predicates = [NSPredicate]()
        
        let filterValues = Logger.instance.cachedFilters
        let filterNames = HTTPModelShortType.allCases
        
        var index = 0
        for filterValue in filterValues {
            if filterValue {
                let filterName = filterNames[index].rawValue
                let predicate = NSPredicate(format: "shortType == '\(filterName)'")
                predicates.append(predicate)

            }
            index += 1
        }

        let searchPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        
        let array = (self.models as NSArray).filtered(using: searchPredicate)
        
        return array as? [LoggerHTTPModel] ?? []
    }
}
