//
//  ViewController.swift
//  Scyther Playground
//
//  Created by Brandon Stillitano on 12/2/21.
//

import Scyther
import UIKit

class ViewController: UIViewController {
    // MARK: - UI Elements
    var tableView: UITableView = UITableView()

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.

        //Setup Interface
        setupUI()
        setupConstraints()

        //Setup Data
        setupData()
    }

    func setupUI() {
        //Setup TableView
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = UITableView.automaticDimension
        self.view.addSubview(tableView)
    }

    func setupConstraints() {
        //Setup Table View Constraints
        tableView.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }
    }
}

extension ViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer {
            tableView.deselectRow(at: indexPath, animated: true)
        }
        Scyther.presentMenu()
    }
}

extension ViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        //Init Cell
        let cellIdentifier: String = String("cellIdentifier")
        var cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier)

        //Adjust Cell
        cell = UITableViewCell(style: .default, reuseIdentifier: cellIdentifier)
        cell?.accessoryType = .none
        cell?.selectionStyle = .none
        
        cell?.textLabel?.text = "Open Scyther"
        
        return cell ?? UITableViewCell()
    }
}

extension ViewController {
    func setupData() {
        setupFlags()
        setupEnvironments()
        setupDeveloperTools()
    }

    func setupFlags() {
        var flags: [String: Bool] = [:]
        flags["logging"] = true
        flags["analytics"] = false
        flags["voip-calling"] = true
        flags["live-chat"] = true
        flags["force-update"] = false
        flags["advertising"] = true
        flags["offline-cache"] = true
        flags["push-notifications"] = true
        flags["backend-sync"] = false
        flags["rtl-layout"] = true
        flags["google-news-bypass"] = false
        flags["development-environment"] = false
        for key: String in flags.keys {
            Scyther.toggler.configureToggle(withName: key,
                                            remoteValue: flags[key] ?? false)
        }
    }

    func setupEnvironments() {
        for environment in Environments.allCases {
            Scyther.configSwitcher.configureEnvironment(withIdentifier: environment.rawValue,
                                                        variables: environment.environmentVariables)
        }
    }

    func setupDeveloperTools() {
        //Setup Red View Controller
        var redOption: DeveloperOption = DeveloperOption()
        redOption.name = "Red View Controller"
        redOption.icon = UIImage(systemImage: "megaphone")
        redOption.viewController = RedViewController()
        Scyther.instance.developerOptions.append(redOption)

        //Setup Blue View Controller
        var blueOption: DeveloperOption = DeveloperOption()
        blueOption.name = "Blue View Controller"
        blueOption.icon = UIImage(systemImage: "location.circle")
        blueOption.viewController = BlueViewController()
        Scyther.instance.developerOptions.append(blueOption)
    }
}
