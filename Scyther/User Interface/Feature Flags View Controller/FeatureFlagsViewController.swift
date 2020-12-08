//
//  FeatureFlagsViewController.swift
//  Scyther
//
//  Created by Brandon Stillitano on 8/12/20.
//

import DTTableViewManager
import UIKit

class FeatureFlagsViewController: UIViewController, DTTableViewManageable {
    // MARK: UI Elements
    internal var tableView: UITableView!

    // MARK: Data
    var model: FeatureFlagsViewModel = FeatureFlagsViewModel()

    deinit {
        tableView.delegate = nil
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        //Setup Interfcae
        self.view.backgroundColor = .systemBackground
        self.title = "Feature Flags"
        setupUI()

        //Setup Data
        model.delegate = self
        setupManager()
        loadData()
    }

    private func setupUI() {
        //Setup TableView
        tableView = UITableView()
        tableView.backgroundColor = .clear
        tableView.rowHeight = UITableView.automaticDimension
        tableView.separatorStyle = .none
        self.view.addSubview(tableView)

        //Setup TableView Constraints
        tableView.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }
    }

    private func setupManager() {
        //Start Manager (Required here as we are programatically instantiating the UITableView)
        manager.startManaging(withDelegate: self)

        //Register Cells
        manager.register(SectionHeaderCell.self)
    }

    private func loadData() {
        //Update Cells
        manager.memoryStorage.updateWithoutAnimations {
            manager.memoryStorage.removeAllItems()
            manager.memoryStorage.addItems(model.objects)
        }

        //Update UI
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }
}

extension FeatureFlagsViewController: FeatureFlagsViewModelProtocol {
    func viewModelShouldRefreshView(viewModel: FeatureFlagsViewModel?) {
        self.loadData()
    }
}
