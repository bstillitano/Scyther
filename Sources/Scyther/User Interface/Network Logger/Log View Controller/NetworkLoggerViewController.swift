//
//  NetworkLoggerViewController.swift
//
//
//  Created by Brandon Stillitano on 24/12/20.
//

#if !os(macOS)
import UIKit

internal class NetworkLoggerViewController: UIViewController {
    // MARK: - UI Elements
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var searchController: UISearchController?
    
    // MARK: - Data
    private var viewModel: NetworkLoggerViewModel = NetworkLoggerViewModel()

    // MARK: - Init
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)

        /// Setup Interface
        setupUI()
        setupConstraints()
        setupData()
        
        /// Start listening to notifications
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(prepareObjects),
                                               name: NSNotification.Name.LoggerReloadData,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(prepareObjects),
                                               name: NSNotification.Name.LoggerClearedModels,
                                               object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup
    private func setupUI() {
        /// Setup Table View
        tableView.delegate = self
        tableView.dataSource = self
        tableView.tableFooterView = UIView()
        view.addSubview(tableView)

        /// Register Table View Cells
        tableView.register(NetworkLogCell.self, forCellReuseIdentifier: RowStyle.networkLog.rawValue)
        
        /// Setup SearchController
        searchController = UISearchController(searchResultsController: nil)
        searchController?.searchResultsUpdater = self
        searchController?.delegate = self
        searchController?.dimsBackgroundDuringPresentation = false
        searchController?.searchBar.autoresizingMask = [.flexibleWidth]
        searchController?.searchBar.searchBarStyle = .minimal
        searchController?.searchBar.placeholder = "Search by url or status code"
        self.navigationItem.searchController = self.searchController
        self.definesPresentationContext = true
        
        /// Setup Close button
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(clearLogs))
    }

    private func setupConstraints() {
        tableView.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }
    }

    private func setupData() {
        viewModel.delegate = self
        prepareObjects()

        title = viewModel.title
        navigationItem.title = viewModel.title
    }
    
    @objc
    private func prepareObjects() {
        DispatchQueue.main.async {
            let searchText = self.searchController?.searchBar.text
            self.viewModel.prepareObjects(filteredOn: searchText)
        }
    }

    // MARK: - Lifecycle
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        UIView.setAnimationsEnabled(false)
        UIDevice.current.setValue(UIDeviceOrientation.portrait.rawValue, forKey: "orientation")
        UIView.setAnimationsEnabled(true)
    }
}

extension NetworkLoggerViewController {
    @objc private func clearLogs() {
        LoggerHTTPModelManager.sharedInstance.clear()
    }
}

extension NetworkLoggerViewController: UITableViewDataSource {
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
        /// Check for Cell
        guard let row = viewModel.row(at: indexPath) else {
            return UITableViewCell()
        }

        /// Setup Cell
        let cell = tableView.dequeueReusableCell(withIdentifier: row.cellReuseIdentifier,
            for: indexPath)
        cell.textLabel?.text = viewModel.title(for: row, indexPath: indexPath)
        cell.detailTextLabel?.text = row.detailText
        cell.accessoryType = row.accessoryType ?? .none
        cell.accessoryView = row.accessoryView

        /// Setup Accessory
        switch row.style {
        case .networkLog:
            /// Check if we can cast our objects to the right class. Configure network cell.
            guard let networkRow: NetworkLogRow = row as? NetworkLogRow else {
                break
            }
            guard let networkCell: NetworkLogCell = cell as? NetworkLogCell else {
                break
            }

            /// Configure cell
            networkCell.textLabel?.text = nil
            networkCell.detailTextLabel?.text = nil
            networkCell.configureWithRow(networkRow)
            return networkCell
        default:
            break
        }

        return cell
    }

}

extension NetworkLoggerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        /// Deselect Cell
        defer { tableView.deselectRow(at: indexPath, animated: true) }

        /// Check for Cell
        guard let row = viewModel.row(at: indexPath) else {
            return
        }
        row.actionBlock?()
    }
}

extension NetworkLoggerViewController: NetworkLoggerViewModelProtocol {
    func viewModelShouldReloadData() {
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }
    
    func viewModel(viewModel: NetworkLoggerViewModel?, shouldShowViewController viewController: UIViewController?) {
        guard let viewController = viewController else {
            return
        }
        self.navigationController?.pushViewController(viewController, animated: true)
    }
}

extension NetworkLoggerViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        prepareObjects()
    }
}

extension NetworkLoggerViewController: UISearchControllerDelegate { }
#endif
