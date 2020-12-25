//
//  NetworkLoggerViewController.swift
//
//
//  Created by Brandon Stillitano on 24/12/20.
//

#if !os(macOS)
import UIKit

internal class NetworkLoggerViewController: UIViewController {
    // MARK: - Data
    private let tableView = UITableView(frame: .zero, style: .plain)
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
                                               name: NSNotification.Name.NFXReloadData,
                                               object: nil)
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
        tableView.register(NetworkLogCell.self, forCellReuseIdentifier: RowStyle.networkLog.rawValue)
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
        viewModel.delegate = self
        viewModel.prepareObjects()

        title = viewModel.title
        navigationItem.title = viewModel.title
    }
    
    @objc
    private func prepareObjects() {
        viewModel.prepareObjects()
    }

    // MARK: - Lifecycle
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        UIView.setAnimationsEnabled(false)
        UIDevice.current.setValue(UIDeviceOrientation.portrait.rawValue, forKey: "orientation")
        UIView.setAnimationsEnabled(true)
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
        return viewModel.numbeOfRows(inSection: section)
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
            networkCell.configure(with: networkRow)
            return networkCell
        default:
            break
        }

        return cell
    }

}

extension NetworkLoggerViewController: UITableViewDelegate {
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

extension NetworkLoggerViewController: NetworkLoggerViewModelProtocol {
    func viewModelShouldReloadData() {
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }
}
#endif
