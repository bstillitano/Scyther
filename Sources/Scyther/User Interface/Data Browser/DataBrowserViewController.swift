//
//  File.swift
//  
//
//  Created by Brandon Stillitano on 19/9/21.
//

#if !os(macOS)
import UIKit

internal class DataBrowserViewController: UIViewController {
    // MARK: - Data
    private let tableView = UITableView(frame: .zero, style: .insetGroupedSafe)
    private var viewModel: DataBrowserViewModel = DataBrowserViewModel()
    
    // MARK: - Constraints
    var tableViewConstraints: [NSLayoutConstraint] = []

    // MARK: - Init
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)

        setupUI()
        setupConstraints()
        setupData()
    }
    
    convenience init(data: [String: [String: Any]]) {
        self.init(nibName: nil, bundle: nil)
        self.viewModel.data = data
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
        tableView.register(SubtitleCell.self, forCellReuseIdentifier: RowStyle.subtitle.rawValue)
        tableView.register(ButtonCell.self, forCellReuseIdentifier: RowStyle.button.rawValue)
        tableView.register(EmptyCell.self, forCellReuseIdentifier: RowStyle.emptyRow.rawValue)
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
    
    @objc
    private func setupData() {
        self.viewModel.delegate = self
        self.viewModel.prepareObjects()

        title = viewModel.title
        navigationItem.title = viewModel.title
    }

    // MARK: - Lifecycle
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        UIView.setAnimationsEnabled(false)
        UIDevice.current.setValue(UIDeviceOrientation.portrait.rawValue, forKey: "orientation")
        UIView.setAnimationsEnabled(true)
    }
}

extension DataBrowserViewController: UITableViewDataSource {

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
        cell.detailTextLabel?.adjustsFontSizeToFitWidth = false

        return cell
    }

}

extension DataBrowserViewController: UITableViewDelegate {
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
        return row.style != .button || row.style != .emptyRow
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

extension DataBrowserViewController: DataBrowserViewModelProtocol {
    func viewModelShouldReloadData() {
        self.tableView.reloadData()
    }
    
    func viewModel(viewModel: DataBrowserViewModel?, shouldShowViewController viewController: UIViewController?) {
        guard let viewController = viewController else {
            return
        }
        self.navigationController?.pushViewController(viewController, animated: true)
    }
}
#endif
