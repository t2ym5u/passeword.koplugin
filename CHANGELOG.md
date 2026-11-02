# Changelog

## [1.0.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

## [1.0.0] - 2026-10-30

### Added
- First release: a word-guessing party game for four players (two teams of
  two), inspired by the classic TV word-guessing game format.
- Qualification: 4 rounds of 30 s per team, 5 words per round, clue-giver and
  guesser swapping roles every round; Found / Pass (back to the end of the
  list) / Forbidden! (word lost) / Undo. Hand-over screen before every turn.
- Tie-break on equal scores: one word for both teams, clue-givers alternating
  every 10 s (whose turn it is shown in a black banner), a forbidden clue
  eliminates.
- Final: 5-level prize pyramid (1 000 · 2 500 · 5 000 · 10 000 · 20 000, fake
  euros or points), 5 words in 1:30 out of 10, 9, 8, 7, 6, at most 3 clues per
  word, Pass = lost; stop and keep or continue after each level; safety level
  2; a one-time joker previewing the next level's first 5 words.
- Optional partner swap in rounds 3–4 with an individual ranking.
- Rules in English and French with the list of forbidden and allowed clues.
- 1687 French and 1687 English words, written natively, tagged by difficulty
  1–5, with famous people, places and characters from level 2 up; one file
  per language, loaded only when played.
- Save/restore: an interrupted turn resumes on its hand-over screen.
