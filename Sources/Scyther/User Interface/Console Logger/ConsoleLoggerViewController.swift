//
//  File.swift
//  
//
//  Created by Brandon Stillitano on 18/1/21.
//

import UIKit

class ConsoleLoggerViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        print("CONSOLE LOGGER====================================================================================================")
        print(Scyther.consoleLogger.logContents)
        print("CONSOLE LOGGER====================================================================================================")
    }
}
