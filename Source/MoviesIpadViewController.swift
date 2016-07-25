//
//  Copyright (c) 2016 Algolia
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
import InstantSearch
import TTRangeSlider
import UIKit

class MoviesIpadViewController: UIViewController, UICollectionViewDataSource, TTRangeSliderDelegate, UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate {
    @IBOutlet weak var searchBar: UISearchBar!
    @IBOutlet weak var genreTableView: UITableView!
    @IBOutlet weak var yearRangeSlider: TTRangeSlider!
    @IBOutlet weak var ratingSelectorView: RatingSelectorView!
    @IBOutlet weak var moviesCollectionView: UICollectionView!
    @IBOutlet weak var actorsTableView: UITableView!
    @IBOutlet weak var movieCountLabel: UILabel!
    @IBOutlet weak var searchTimeLabel: UILabel!
    @IBOutlet weak var genreTableViewFooter: UILabel!
    @IBOutlet weak var genreFilteringModeSwitch: UISwitch!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!

    var actorSearcher: Searcher!
    var movieSearcher: Searcher!
    
    var genreFacets: [FacetValue] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.movieCountLabel.text = NSLocalizedString("movie_count_placeholder", comment: "")
        self.searchTimeLabel.text = nil
        
        // Customize year range slider.
        yearRangeSlider.numberFormatterOverride = NSNumberFormatter()
        let tintColor = self.view.tintColor
        yearRangeSlider.tintColorBetweenHandles = tintColor
        yearRangeSlider.handleColor = tintColor
        yearRangeSlider.lineHeight = 3
        yearRangeSlider.minLabelFont = UIFont.systemFontOfSize(12)
        yearRangeSlider.maxLabelFont = yearRangeSlider.minLabelFont
        
        ratingSelectorView.addObserver(self, forKeyPath: "rating", options: .New, context: nil)
        
        // Customize genre table view.
        genreTableView.tableFooterView = genreTableViewFooter
        genreTableViewFooter.hidden = true
        
        // Configure actor search.
        actorSearcher = Searcher(index: AlgoliaManager.sharedInstance.actorsIndex, resultHandler: self.handleActorSearchResults)
        actorSearcher.query.hitsPerPage = 10
        actorSearcher.query.attributesToHighlight = ["name"]

        // Configure movie search.
        movieSearcher = Searcher(index: AlgoliaManager.sharedInstance.moviesIndex, resultHandler: self.handleMovieSearchResults)
        movieSearcher.query.facets = ["genre"]
        movieSearcher.query.attributesToHighlight = ["title"]
        movieSearcher.query.hitsPerPage = 30
        
        movieSearcher.addObserver(self, forKeyPath: "pendingRequests", options: [.New], context: nil)

        search()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    // MARK: - Actions
    
    private func search() {
        actorSearcher.search()
        movieSearcher.disjunctiveFacets = genreFilteringModeSwitch.on ? ["genre"] : []
        movieSearcher.query.numericFilters = [
            "year >= \(Int(yearRangeSlider.selectedMinimum))",
            "year <= \(Int(yearRangeSlider.selectedMaximum))",
            "rating >= \(ratingSelectorView.rating)"
        ]
        movieSearcher.search()
    }
    
    @IBAction func genreFilteringModeDidChange(sender: AnyObject) {
        // Convert conjunctive refinements into disjunctive and vice versa.
        let queryHelper = QueryHelper(query: movieSearcher.query)
        let refinements = queryHelper.getFacetRefinements() { $0.name == "genre" }
        for refinement in refinements {
            queryHelper.removeFacetRefinement(refinement)
        }
        let disjunctive = genreFilteringModeSwitch.on
        for refinement in refinements {
            if disjunctive {
                queryHelper.addDisjunctiveFacetRefinement(refinement)
            } else {
                queryHelper.addConjunctiveFacetRefinement(refinement)
            }
        }
        search()
    }
    
    // MARK: - UISearchBarDelegate
    
    func searchBar(searchBar: UISearchBar, textDidChange searchText: String) {
        actorSearcher.query.query = searchText
        movieSearcher.query.query = searchText
        search()
    }
    
    // MARK: - Search completion handlers

    private func handleActorSearchResults(results: SearchResults?, error: NSError?) {
        guard let results = results else { return }
        
        self.actorsTableView.reloadData()
        
        // Scroll to top.
        if results.lastQuery.page == 0 {
            self.moviesCollectionView.contentOffset = CGPointZero
        }
    }

    private func handleMovieSearchResults(results: SearchResults?, error: NSError?) {
        guard let results = results else {
            self.searchTimeLabel.text = NSLocalizedString("error_search", comment: "")
            return
        }
        // Sort facets: first selected facets, then by decreasing count, then by name.
        let receivedQueryHelper = QueryHelper(query: results.lastQuery)
        genreFacets = results.facets("genre")?.sort({ (lhs, rhs) in
            // When using cunjunctive faceting ("AND"), all refined facet values are displayed first.
            // But when using disjunctive faceting ("OR"), refined facet values are left where they are.
            let disjunctiveFaceting = results.disjunctiveFacets.contains("genre") ?? false
            let lhsChecked = receivedQueryHelper.hasFacetRefinement(FacetRefinement(name: "genre", value: lhs.value))
            let rhsChecked = receivedQueryHelper.hasFacetRefinement(FacetRefinement(name: "genre", value: rhs.value))
            if !disjunctiveFaceting && lhsChecked != rhsChecked {
                return lhsChecked
            } else if lhs.count != rhs.count {
                return lhs.count > rhs.count
            } else {
                return lhs.value < rhs.value
            }
        }) ?? []
        let exhaustiveFacetsCount = results.exhaustiveFacetsCount == true
        genreTableViewFooter.hidden = exhaustiveFacetsCount

        if let nbHits = results.nbHits {
            let formatter = NSNumberFormatter()
            formatter.locale = NSLocale.currentLocale()
            formatter.numberStyle = .DecimalStyle
            formatter.usesGroupingSeparator = true
            formatter.groupingSize = 3
            self.movieCountLabel.text = "\(formatter.stringFromNumber(nbHits)!) MOVIES"
        } else {
            self.movieCountLabel.text = "MOVIES"
        }
        if let processingTimeMS = results.processingTimeMS {
            self.searchTimeLabel.text = "Found in \(processingTimeMS) ms"
        }

        self.genreTableView.reloadData()
        self.moviesCollectionView.reloadData()
        
        // Scroll to top.
        if results.lastQuery.page == 0 {
            self.moviesCollectionView.contentOffset = CGPointZero
        }
    }
    
    // MARK: - UICollectionViewDataSource
    
    func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return movieSearcher.results?.hits.count ?? 0
    }
    
    func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCellWithReuseIdentifier("movieCell", forIndexPath: indexPath) as! MovieCell
        cell.movie = MovieRecord(json: movieSearcher.results!.hits[indexPath.item])
        if indexPath.item + 5 >= movieSearcher.results?.hits.count {
            movieSearcher.loadMore()
        }
        return cell
    }
    
    // MARK: - UITableViewDataSource
    
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch tableView {
            case actorsTableView: return actorSearcher.results?.hits.count ?? 0
            case genreTableView: return genreFacets.count
            default: assert(false); return 0
        }
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        switch tableView {
            case actorsTableView:
                let cell = tableView.dequeueReusableCellWithIdentifier("actorCell", forIndexPath: indexPath) as! ActorCell
                cell.actor = Actor(json: actorSearcher.results!.hits[indexPath.item])
                if indexPath.item + 5 >= actorSearcher.results!.hits.count {
                    actorSearcher.loadMore()
                }
                return cell
            case genreTableView:
                let cell = tableView.dequeueReusableCellWithIdentifier("genreCell", forIndexPath: indexPath) as! GenreCell
                cell.value = genreFacets[indexPath.item]
                cell.checked = QueryHelper(query: movieSearcher.results!.lastQuery).hasFacetRefinement(FacetRefinement(name: "genre", value: genreFacets[indexPath.item].value))
                return cell
            default: assert(false); return UITableViewCell()
        }
    }
    
    // MARK: - UITableViewDelegate
    
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        switch tableView {
            case genreTableView:
                movieSearcher.toggleFacetRefinement(FacetRefinement(name: "genre", value: genreFacets[indexPath.item].value))
                movieSearcher.search()
                break
            default: return
        }
    }
    
    // MARK: - TTRangeSliderDelegate
    
    func rangeSlider(sender: TTRangeSlider!, didChangeSelectedMinimumValue selectedMinimum: Float, andMaximumValue selectedMaximum: Float) {
        search()
    }
    
    // MARK: - KVO
    
    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        guard let object = object as? NSObject else { return }
        if object == ratingSelectorView {
            if keyPath == "rating" {
                search()
            }
        } else if object == movieSearcher {
            if keyPath == "pendingRequests" {
                // Stop the slow request indicator only when there are no pending requests.
                if movieSearcher.pendingRequests.isEmpty {
                    activityIndicator.stopAnimating()
                }
            }
        }
    }
}
