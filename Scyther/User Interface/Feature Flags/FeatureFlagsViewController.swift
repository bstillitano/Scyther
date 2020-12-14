//
//  FeatureFlagsViewController.swift
//  Scyther
//
//  Created by Brandon Stillitano on 8/12/20.
//

import UIKit

internal class FeatureFlagsViewController: UIViewController {
    // MARK: - Data
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var viewModel: FeatureFlagsViewModel?

    // MARK: - Init
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)

        setupUI()
        setupConstraints()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup
    private func setupUI() {
        //Setup Table View
        tableView.delegate = self
        tableView.dataSource = self

        //Register Table View Cells
        tableView.register(SwitchCell.self, forCellReuseIdentifier: RowStyle.switchAccessory.rawValue)
        tableView.register(ButtonCell.self, forCellReuseIdentifier: RowStyle.button.rawValue)

        //Add Table View
        view.addSubview(tableView)
    }

    private func setupConstraints() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-0-[subview]-0-|",
                                                           options: .directionLeadingToTrailing,
                                                           metrics: nil,
                                                           views: ["subview": tableView]))
        view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-0-[subview]-0-|",
                                                           options: .directionLeadingToTrailing,
                                                           metrics: nil,
                                                           views: ["subview": tableView]))
    }

    // MARK: - Lifecycle
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        UIView.setAnimationsEnabled(false)
        UIDevice.current.setValue(UIDeviceOrientation.portrait.rawValue, forKey: "orientation")
        UIView.setAnimationsEnabled(true)
    }

    // MARK: - Configure
    internal func configure(with viewModel: FeatureFlagsViewModel) {
        self.viewModel = viewModel
        self.viewModel?.delegate = self
        self.viewModel?.prepareObjects()

        title = viewModel.title
        navigationItem.title = viewModel.title

        tableView.reloadData()
    }
}

extension FeatureFlagsViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return viewModel?.numberOfSections ?? 0
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return viewModel?.title(forSection: section) ?? nil
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel?.numbeOfRows(inSection: section) ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // Check for Cell
        guard let row = viewModel?.row(at: indexPath) else {
            return UITableViewCell()
        }

        // Setup Cell
        let cell = tableView.dequeueReusableCell(withIdentifier: row.cellReuseIdentifier,
                                                 for: indexPath)
        cell.textLabel?.text = viewModel?.title(for: row, indexPath: indexPath)
        cell.detailTextLabel?.text = row.detailText
        cell.accessoryView = row.accessoryView
        
        return cell
    }

}

extension FeatureFlagsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // Deselect Cell
        defer { tableView.deselectRow(at: indexPath, animated: true) }

        // Check for Cell
        guard let row = viewModel?.row(at: indexPath) else {
            return
        }
        row.actionBlock?()
    }
}

extension FeatureFlagsViewController: FeatureFlagsViewModelProtocol {
    func viewModelShouldReloadData() {
        self.tableView.reloadData()
    }
}
