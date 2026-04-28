# TODO

## Kata progression branches

- [ ] **Cut `kata-5-done`.** Today's Kata 5 solution (Domain Events on Order) needs to land on a new branch as a cumulative descendant of `kata-4-done`. Tip should be a single "Kata 5 done: …" commit.
- [ ] **Decide the `solutions` vs `kata-N-done` relationship.** `solutions` currently lags `kata-4-done` by a README revision. Either it should always be a fast-forward of the highest cumulative `kata-N-done`, or it serves a different purpose (working trunk for in-progress solutions?). Pick one and document it.

> Earlier note on this list claimed the `kata-N-done` branches weren't cumulative. That was wrong — `git log kata-N-done --oneline` shows each one already stacks on the prior. Leaving this paragraph as a breadcrumb for the next person who second-guesses the layout.

## Tooling / docs

- [ ] **Write LLM-runnable instructions for cutting future `kata-N-done` branches.** Goal: a future agent (or future-me running an agent) can produce the next branch correctly without reverse-engineering the convention each time. Apply the technical-writing skill — keep it clear, step-wise, and verifiable. The instructions should cover at least:
  - Branch naming convention (`kata-N-done`, N = kata number).
  - Cumulativity contract (each branch is a fast-forward / clean rebase of `kata-(N-1)-done`).
  - Commit shape (single tip commit, "Kata N done: <one-liner>").
  - Source of truth (where the worked solution comes from — `solutions` branch, current working tree, etc.).
  - Skeleton invariant for `master` (never commit a worked solution onto master; master stays the learner skeleton).
  - Verification (`gleam test` passes on the branch tip; later kata files may still be skeletons with `todo`).
  - Push policy (do not push without explicit user approval).
