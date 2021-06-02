//
//  MenuViewController.swift
//  Scyther
//
//  Created by Brandon Stillitano on 10/12/20.
//

#if !os(macOS)
import UIKit

internal class MenuViewController: UIViewController {
    // MARK: - Data
    private let tableView = UITableView(frame: .zero, style: .insetGroupedSafe)
    private var viewModel: MenuViewModel?

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
        /// Setup Table View
        tableView.delegate = self
        tableView.dataSource = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        /// Register Table View Cells
        tableView.register(DefaultCell.self, forCellReuseIdentifier: RowStyle.default.rawValue)
        tableView.register(DeviceTableViewCell.self, forCellReuseIdentifier: RowStyle.deviceHeader.rawValue)
        tableView.register(EmptyCell.self, forCellReuseIdentifier: RowStyle.emptyRow.rawValue)
        tableView.register(SwitchCell.self, forCellReuseIdentifier: RowStyle.switchAccessory.rawValue)

        /// Setup Close button
        if #available(iOS 13.0, *) {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(dismissMenu))
        } else {
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissMenu))
        }
        
        /// Disable interactive dismissal
        if #available(iOS 13.0, *) {
            isModalInPresentation = true
        }
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            tableView.leftAnchor.constraint(equalTo: view.leftAnchor),
            tableView.rightAnchor.constraint(equalTo: view.rightAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Lifecycle
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        UIView.setAnimationsEnabled(false)
        UIDevice.current.setValue(UIDeviceOrientation.portrait.rawValue, forKey: "orientation")
        UIView.setAnimationsEnabled(true)
    }

    // MARK: - Configure
    internal func configure(with viewModel: MenuViewModel) {
        self.viewModel = viewModel
        self.viewModel?.delegate = self
        self.viewModel?.prepareObjects()

        title = viewModel.title
        navigationItem.title = viewModel.title
    }

    // MARK: - Actions
    @objc
    private func dismissMenu() {
        navigationController?.dismiss(animated: true, completion: nil)
        Scyther.instance.presented = false
    }
}

extension MenuViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return viewModel?.numberOfSections ?? 0
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return viewModel?.title(forSection: section) ?? nil
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel?.numberOfRows(inSection: section) ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        /// Check ViewModel for cell/row data
        guard let row = viewModel?.row(at: indexPath) else {
            return UITableViewCell()
        }

        /// Configure cell
        let cell = tableView.dequeueReusableCell(withIdentifier: row.style.rawValue, for: indexPath)
        cell.accessoryType = row.accessoryType ?? .none
        cell.accessoryView = row.accessoryView
        cell.textLabel?.text = viewModel?.title(for: row, indexPath: indexPath)
        cell.detailTextLabel?.text = row.detailText

        /// Set image
        if let url = row.imageURL {
            cell.imageView?.loadImage(fromURL: url) { _ in
                cell.setNeedsLayout()
            }
        } else if #available(iOS 13.0, *), let icon = row.image {
            cell.imageView?.image = icon
        }

        return cell
    }

}

extension MenuViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        /// Deselect Cell
        defer {
            tableView.deselectRow(at: indexPath, animated: true)
        }

        /// Perform Row Action
        guard let row = viewModel?.row(at: indexPath) else {
            return
        }
        viewModel?.performAction(for: row, indexPath: indexPath)
    }
}

extension MenuViewController: MenuViewModelProtocol {
    func viewModelShouldReloadData() {
        self.tableView.reloadData()
    }

    func viewModel(viewModel: MenuViewModel?, shouldShowViewController viewController: UIViewController?) {
        guard let viewController = viewController else {
            return
        }
        self.navigationController?.pushViewController(viewController, animated: true)
    }
}
#endif
