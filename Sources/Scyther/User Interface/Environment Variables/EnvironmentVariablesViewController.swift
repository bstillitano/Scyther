//
//  File.swift
//  
//
//  Created by Brandon Stillitano on 14/4/2022.
//

#if !os(macOS)
import UIKit

internal class EnvironmentVariablesViewController: UIViewController {
    // MARK: - Data
    private let tableView = UITableView(frame: .zero, style: .insetGroupedSafe)
    private var viewModel: EnvironmentVariablesViewModel = EnvironmentVariablesViewModel()
    
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
        tableView.register(EmptyCell.self, forCellReuseIdentifier: RowStyle.emptyRow.rawValue)
        tableView.register(ButtonCell.self, forCellReuseIdentifier: RowStyle.button.rawValue)
        tableView.register(SubtitleCell.self, forCellReuseIdentifier: RowStyle.subtitle.rawValue)
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

extension EnvironmentVariablesViewController: UITableViewDataSource {

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
        cell.detailTextLabel?.numberOfLines = 0
        if #available(iOS 15.0, *) {
            cell.detailTextLabel?.textColor = .tintColor
        } else {
            cell.detailTextLabel?.textColor = .systemFill
        }
        cell.accessoryView = row.accessoryView

        // Setup Accessory
        switch row.style {
        case .checkmarkAccessory:
            guard let checkRow: CheckmarkRow = row as? CheckmarkRow else {
                break
            }
            cell.accessoryType = checkRow.checked ? .checkmark : .none
        default:
            break
        }

        return cell
    }

}

extension EnvironmentVariablesViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // Deselect Cell
        defer { tableView.deselectRow(at: indexPath, animated: true) }

        // Check for Cell
        guard let row = viewModel.row(at: indexPath) else {
            return
        }
        row.actionBlock?()
    }
    
    func tableView(_ tableView: UITableView, shouldShowMenuForRowAt indexPath: IndexPath) -> Bool {
        guard let row = viewModel.row(at: indexPath) else { return false }
        return row.style != .button
    }

    func tableView(_ tableView: UITableView, canPerformAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) -> Bool {
        return (action == #selector(copy(_:)))
    }

    func tableView(_ tableView: UITableView, performAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) {
        if action == #selector(copy(_:)) {
            guard let cell = tableView.cellForRow(at: indexPath), let key = cell.textLabel?.text else { return }
            UIPasteboard.general.string = "\(key): \(cell.detailTextLabel?.text ?? "")"
        }
    }
}

extension EnvironmentVariablesViewController: EnvironmentVariablesViewModelProtocol {
    func viewModelShouldReloadData() {
        self.tableView.reloadData()
    }
}
#endif
