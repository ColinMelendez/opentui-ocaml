# Major feature records

This directory contains the design and implementation records for features
that cross several modules or packages. A feature record gives contributors
one stable place to find its active contract, reference correspondence,
ownership rules, acceptance criteria, and important supporting material.

## Directory layout

```text
docs/major-features/
├── in-progress/<feature>/
│   ├── feature.md
│   └── context/
└── implemented/<feature>/
    ├── feature.md
    └── context/
```

`in-progress` contains feature records whose implementation or acceptance
work is incomplete. `implemented` contains feature records whose acceptance
criteria are satisfied by the repository.

Each feature directory contains:

- `feature.md`, the active declarative contract and implementation guide;
- `context/`, non-normative reference material such as design discussions,
  discarded alternatives, and older document versions.

The active contract is the source of truth. Context files explain the origin
of a decision but do not define the API, ownership, or observable behavior.
They retain their original wording when that wording is important evidence.

Feature names use lowercase hyphen-separated directory names. A feature record
links to the relevant reference paths, package modules, tests, benchmarks, and
source-map entries. A feature record moves from `in-progress` to `implemented`
when its acceptance criteria are satisfied; its links and context remain
unchanged.

Repository architecture documents define cross-feature package and effect
boundaries. Feature records define the contracts of individual cross-cutting
features.
