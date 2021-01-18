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
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        print("CONSOLE LOGGER====================================================================================================")
        print(Scyther.consoleLogger.logContents)
        print("CONSOLE LOGGER====================================================================================================")
    }
}
