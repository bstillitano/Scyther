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
    fileprivate var models = [ScytherHTTPModel]()
    private let syncQueue = DispatchQueue(label: "LoggerSyncQueue")
    
    func add(_ obj: ScytherHTTPModel) {
        syncQueue.async {
            self.models.insert(obj, at: 0)
            NotificationCenter.default.post(name: NSNotification.Name.NFXAddedModel, object: obj)
        }
    }
    
    func clear() {
        syncQueue.async {
            self.models.removeAll()
            NotificationCenter.default.post(name: NSNotification.Name.NFXClearedModels, object: nil)
        }
    }
    
    func getModels() -> [ScytherHTTPModel] {
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
        
        return array as? [ScytherHTTPModel] ?? []
    }
}
