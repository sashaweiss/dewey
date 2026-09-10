//
//  FuzzyMatch.swift
//  dewey
//

import Foundation

enum FuzzyMatch {
    /// Scores `candidate` against `query`. Returns nil if the query is not a
    /// (case- and diacritic-insensitive) subsequence of the candidate. Higher
    /// scores are better: whole-string prefix > word prefix > subsequence,
    /// with bonuses for consecutive and word-initial matches.
    static func score(query: String, candidate: String) -> Int? {
        let query = query.searchFolded
        let candidate = candidate.searchFolded
        guard !query.isEmpty else { return 0 }

        if candidate.hasPrefix(query) {
            return 10_000 - candidate.count
        }

        let words = candidate.split { !$0.isLetter && !$0.isNumber }
        for (wordIndex, word) in words.enumerated() {
            if word.hasPrefix(query) {
                return 5_000 - (wordIndex * 100) - candidate.count
            }
        }

        var score = 0
        var searchStartIndex = candidate.startIndex
        var previousMatchIndex: String.Index?
        for character in query {
            guard
                let matchIndex = candidate[searchStartIndex...].firstIndex(of: character)
            else {
                return nil
            }

            if matchIndex == candidate.startIndex {
                score += 15
            } else if
                let previousMatchIndex,
                candidate.index(after: previousMatchIndex) == matchIndex
            {
                score += 10
            } else {
                let precedingCharacter = candidate[candidate.index(before: matchIndex)]
                if !precedingCharacter.isLetter && !precedingCharacter.isNumber {
                    score += 8
                } else {
                    score += 1
                }
            }

            previousMatchIndex = matchIndex
            searchStartIndex = candidate.index(after: matchIndex)
        }

        return score
    }
}

// MARK: -

private extension String {
    var searchFolded: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
