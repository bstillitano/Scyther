//
//  NotificationTesterViewController.swift
//  
//
//  Created by Brandon Stillitano on 15/2/21.
//

#if !os(macOS)
import UIKit

internal class NotificationTesterViewController: UIViewController {
    // MARK: - Data
    private let tableView = UITableView(frame: .zero, style: .insetGroupedSafe)
    private var viewModel: NotitifcationTesterViewModel = NotitifcationTesterViewModel()
    
    // MARK: - Constraints
    var tableViewConstraints: [NSLayoutConstraint] = []

    // MARK: - Init
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)

        setupUI()
        setupConstraints()
        setupData()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup
    private func setupUI() {
        //Setup Table View
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        view.addSubview(tableView)

        //Register Table View Cells
        tableView.register(DefaultCell.self, forCellReuseIdentifier: RowStyle.default.rawValue)
        tableView.register(SwitchCell.self, forCellReuseIdentifier: RowStyle.switchAccessory.rawValue)
        tableView.register(ButtonCell.self, forCellReuseIdentifier: RowStyle.button.rawValue)
    }

    private func setupConstraints() {
        // Clear Existing Constraints
        NSLayoutConstraint.deactivate(tableViewConstraints)
        tableViewConstraints.removeAll()

        // Setup Table View Constraints
        tableViewConstraints.append(tableView
            .topAnchor
            .constraint(equalTo: view.topAnchor))
        tableViewConstraints.append(tableView
            .leadingAnchor
            .constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor))
        tableViewConstraints.append(tableView
            .bottomAnchor
            .constraint(equalTo: view.bottomAnchor))
        tableViewConstraints.append(tableView
            .trailingAnchor
            .constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor))

        // Activate Constraints
        NSLayoutConstraint.activate(tableViewConstraints)
    }
    
    private func setupData() {
        self.viewModel.delegate = self
        self.viewModel.prepareObjects()

        title = viewModel.title
        navigationItem.title = viewModel.title
    }

    // MARK: - Lifecycle
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
}

extension NotificationTesterViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return viewModel.numberOfSections
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return viewModel.title(forSection: section)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.numberOfRows(inSection: section)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // Check for Cell
        guard let row = viewModel.row(at: indexPath) else {
            return UITableViewCell()
        }

        // Setup Cell
        let cell = tableView.dequeueReusableCell(withIdentifier: row.cellReuseIdentifier,
                                                 for: indexPath)
        cell.textLabel?.text = viewModel.title(for: row, indexPath: indexPath)
        cell.detailTextLabel?.text = row.detailText
        cell.accessoryView = row.accessoryView
        cell.accessoryType = row.accessoryType ?? .none

        return cell
    }

}

extension NotificationTesterViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // Deselect Cell
        defer { tableView.deselectRow(at: indexPath, animated: true) }

        // Check for Cell
        guard let row = viewModel.row(at: indexPath) else {
            return
        }
        row.actionBlock?()
    }
}

extension NotificationTesterViewController: NotitificationTesterProtocol {
    func viewModelShouldReloadData() {
        Task { @MainActor in
            UIView.transition(with: self.tableView,
                              duration: 0.35,
                              options: .transitionCrossDissolve,
                              animations: {
                                    self.tableView.reloadData()
            })
        }
    }
}
#endif
