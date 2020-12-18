//
//  UserDefaultsViewController.swift
//  
//
//  Created by Brandon Stillitano on 18/12/20.
//

#if !os(macOS)
import UIKit

internal class UserDefaultsViewController: UIViewController {
    // MARK: - Data
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var viewModel: UserDefaultsViewModel = UserDefaultsViewModel()

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
        tableView.delegate = self
        tableView.dataSource = self
        view.addSubview(tableView)

        //Register Table View Cells
        tableView.register(DefaultCell.self, forCellReuseIdentifier: RowStyle.default.rawValue)
        tableView.register(CheckmarkCell.self, forCellReuseIdentifier: RowStyle.checkmarkAccessory.rawValue)
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

extension UserDefaultsViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return viewModel.numberOfSections
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return viewModel.title(forSection: section)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.numbeOfRows(inSection: section)
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

extension UserDefaultsViewController: UITableViewDelegate {
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

extension UserDefaultsViewController: UserDefaultsViewModelProtocol {
    func viewModelShouldReloadData() {
        self.tableView.reloadData()
    }
}
#endif
