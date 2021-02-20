//
//  CookieDetailsViewController.swift
//  
//
//  Created by Brandon Stillitano on 20/2/21.
//

#if !os(macOS)
import UIKit

internal class CookieDetailsViewController: UIViewController {
    // MARK: - Data
    private let tableView = UITableView(frame: .zero, style: .insetGroupedSafe)
    private var viewModel: CookieDetailsViewModel = CookieDetailsViewModel()

    // MARK: - Init
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)

        setupUI()
        setupConstraints()
        setupData()
        
        /// Setup Close button
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(deleteCookie))
    }
    
    convenience init(cookie: HTTPCookie) {
        self.init(nibName: nil, bundle: nil)
        self.viewModel.cookie = cookie
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
        tableView.register(SubtitleCell.self, forCellReuseIdentifier: RowStyle.subtitle.rawValue)
        tableView.register(ButtonCell.self, forCellReuseIdentifier: RowStyle.button.rawValue)
        tableView.register(EmptyCell.self, forCellReuseIdentifier: RowStyle.emptyRow.rawValue)
    }

    private func setupConstraints() {
        tableView.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }
    }
    
    private func setupData() {
        self.viewModel.delegate = self

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

extension CookieDetailsViewController {
    @objc
    private func deleteCookie() {
        /// Check if cookie is available
        guard let cookie = viewModel.cookie else {
            return
        }
        
        /// Delete the cookie and then synchrnoize defaults to try triggering HTTPCookieStorage's refresh mechanism.
        HTTPCookieStorage.shared.deleteCookie(cookie)
        UserDefaults.standard.synchronize()
        self.navigationController?.popViewController(animated: true)
    }
}

extension CookieDetailsViewController: UITableViewDataSource {

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
        cell.accessoryType = row.accessoryType ?? .none
        cell.detailTextLabel?.adjustsFontSizeToFitWidth = false

        return cell
    }
}

extension CookieDetailsViewController: UITableViewDelegate {
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

extension CookieDetailsViewController: CookieDetailsViewModelProtocol {
    func viewModelShouldReloadData() {
        self.tableView.reloadData()
    }
    
    func viewModel(viewModel: CookieDetailsViewModel?, shouldShowViewController viewController: UIViewController?) {
        guard let viewController = viewController else {
            return
        }
        guard viewController.isKind(of: UIActivityViewController.self) else {
            self.navigationController?.pushViewController(viewController, animated: true)
            return
        }
        self.present(viewController, animated: true)
    }
}
#endif
