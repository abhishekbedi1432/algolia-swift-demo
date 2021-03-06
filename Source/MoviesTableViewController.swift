//
//  Copyright (c) 2015 Algolia
//  http://www.algolia.com/
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import AlgoliaSearch
import InstantSearchCore
import AFNetworking
import UIKit


class MoviesTableViewController: UITableViewController, UISearchBarDelegate, UISearchResultsUpdating, SearchProgressDelegate {

    var searchController: UISearchController!
    var searchProgressController: SearchProgressController!

    var movieSearcher: Searcher!
    var movieHits: [JSONObject] = []
    var originIsLocal: Bool = false

    let placeholder = UIImage(named: "white")

    override func viewDidLoad() {
        super.viewDidLoad()

        // Algolia Search
        movieSearcher = Searcher(index: AlgoliaManager.sharedInstance.moviesIndex, resultHandler: self.handleSearchResults)
        movieSearcher.params.hitsPerPage = 15
        movieSearcher.params.attributesToRetrieve = ["title", "image", "rating", "year"]
        movieSearcher.params.attributesToHighlight = ["title"]

        // Search controller
        searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.dimsBackgroundDuringPresentation = false
        searchController.searchBar.delegate = self
        searchController.searchBar.placeholder = NSLocalizedString("search_bar_placeholder", comment: "")

        // Add the search bar
        tableView.tableHeaderView = self.searchController!.searchBar
        definesPresentationContext = true
        searchController!.searchBar.sizeToFit()

        // Configure search progress monitoring.
        searchProgressController = SearchProgressController(searcher: movieSearcher)
        searchProgressController.delegate = self

        // First load
        updateSearchResults(for: searchController)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    // MARK: - Actions

    @IBAction func configTapped(_ sender: AnyObject) {
        let vc = ConfigViewController(nibName: "ConfigViewController", bundle: nil)
        self.present(vc, animated: true, completion: nil)
    }

    // MARK: - Search completion handlers

    private func handleSearchResults(results: SearchResults?, error: Error?) {
        guard let results = results else { return }
        if results.page == 0 {
            movieHits = results.hits
        } else {
            movieHits.append(contentsOf: results.hits)
        }
        originIsLocal = results.content["origin"] as? String == "local"
        self.tableView.reloadData()
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection: Int) -> Int {
        return movieHits.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "movieCell", for: indexPath)

        // Load more?
        if indexPath.row + 5 >= movieHits.count {
            movieSearcher.loadMore()
        }

        // Configure the cell...
        let movie = MovieRecord(json: movieHits[indexPath.row])
        cell.textLabel?.highlightedText = movie.title_highlighted

        cell.detailTextLabel?.text = movie.year != nil ? "\(movie.year!)" : nil
        cell.imageView?.cancelImageDownloadTask()
        if let url = movie.imageUrl {
            cell.imageView?.setImageWith(url, placeholderImage: placeholder)
        }
        else {
            cell.imageView?.image = nil
        }
        cell.backgroundColor = originIsLocal ? AppDelegate.colorForLocalOrigin : UIColor.white

        return cell
    }

    // MARK: - Search

    func updateSearchResults(for searchController: UISearchController) {
        movieSearcher.params.query = searchController.searchBar.text
        movieSearcher.search()
    }

    // MARK: - KVO

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    }

    // MARK: - Activity indicator

    // MARK: - SearchProgressDelegate
    
    func searchDidStart(_ searchProgressController: SearchProgressController) {
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
    }
    
    func searchDidStop(_ searchProgressController: SearchProgressController) {
        UIApplication.shared.isNetworkActivityIndicatorVisible = false
    }
}
