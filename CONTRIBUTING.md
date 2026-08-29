# Contributing to DSSS

Thank you for your interest in the Deterministic Sovereign Solving System.  DSSS
is a research-grade, patent-pending solver that spans Haskell/GHC TypeNats, Idris 2
QTT, Futhark GPU kernels, Scala parsing, Circom ZK circuits, and Python theory
solvers.  Contributions that advance any of these layers are welcome.

---

## Table of Contents

1. [Development Environment Setup](#1-development-environment-setup)
2. [Running the Test Suite](#2-running-the-test-suite)
3. [How to Submit a Pull Request](#3-how-to-submit-a-pull-request)
4. [Contributor License Agreement](#4-contributor-license-agreement)
5. [Code Style Guidelines](#5-code-style-guidelines)
6. [Where to Ask Questions](#6-where-to-ask-questions)
7. [What Kinds of Contributions Are Welcome](#7-what-kinds-of-contributions-are-welcome)

---

## 1. Development Environment Setup

### Prerequisites — install in this order

| Tool | Minimum version | Purpose |
|---|---|---|
| GHC | 9.4 | Haskell compiler (TypeNats, DataKinds, GADTs) |
| Cabal | 3.8 | Haskell build system |
| Idris 2 | 0.7.0 | QTT frontend (`src/Dsss/Frontend/`) |
| Futhark | 0.25.0 | GPU backend (`src/Dsss/Backend/`) |
| Scala / sbt | Scala 3.3, sbt 1.9 | SMT-LIB parser + TrigCAD compiler |
| Node.js | 18 LTS | Required by Circom toolchain |
| circom | 2.1.5 | ZK circuit compiler |
| snarkjs | 0.7 | Witness generation and proof |
| Python | 3.10+ | Trig/NRA theory solver |
| OpenSCAD | 2021.01+ | Visualising generated `.scad` output |

### Haskell / GHC + Cabal

The recommended route is [GHCup](https://www.haskell.org/ghcup/):

```bash
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh
ghcup install ghc 9.4.8
ghcup install cabal 3.10.2.0
ghcup set ghc 9.4.8
```

Build the Haskell components:

```bash
cd /path/to/dsss
cabal update
cabal build all
```

Install HLint for linting (required before submitting a PR):

```bash
cabal install hlint
```

### Idris 2

Install via the [official instructions](https://idris-lang.org/docs/tutorial/starting.html):

```bash
# macOS / Linux via pack (preferred)
curl https://www.idris-lang.org/install/pack.bash | bash
pack install idris2

# Or build from source
git clone https://github.com/idris-lang/Idris2
cd Idris2
make bootstrap PREFIX=$HOME/.idris2
make install PREFIX=$HOME/.idris2
```

Type-check the Idris 2 sources:

```bash
idris2 --check src/Dsss/Frontend/CADModel.idr
idris2 --check src/Dsss/Frontend/TypeNet.idr
```

### Futhark

```bash
# Requires LLVM 14+ on the PATH
curl https://futhark-lang.org/install.sh | sh
```

Compile the GPU kernel:

```bash
futhark opencl src/Dsss/Backend/kernel.fut   # OpenCL target
# or
futhark cuda src/Dsss/Backend/kernel.fut     # CUDA target
# or (CPU, no GPU required for development)
futhark c src/Dsss/Backend/kernel.fut
```

Run the Futhark test suite:

```bash
futhark test src/Dsss/Backend/kernel.fut
```

### Scala / sbt

```bash
# Install sbt (Scala Build Tool)
curl -s "https://get.sdkman.io" | bash
sdk install java 17.0.9-tem
sdk install sbt

# Compile
sbt compile
sbt test
```

### Circom + snarkjs

```bash
npm install -g circom snarkjs

# Verify the ZK circuit compiles
circom src/Dsss/Zk/ConstantProductSolver.circom \
  --r1cs --wasm --sym \
  --output build/zk/
```

### Python (Trig / NRA theory solver)

```bash
python3 -m venv .venv
source .venv/bin/activate     # Windows: .venv\Scripts\activate
pip install -r requirements.txt    # or: pip install pytest black
```

---

## 2. Running the Test Suite

### Haskell unit tests

```bash
cabal test
```

### Idris 2 type-checking (no separate test runner yet — TC is the test)

```bash
idris2 --check src/Dsss/Frontend/CADModel.idr
idris2 --check src/Dsss/Frontend/TypeNet.idr
```

### Futhark tests

```bash
futhark test src/Dsss/Backend/kernel.fut
```

### Scala tests

```bash
sbt test
```

### Python tests

```bash
pytest src/Dsss/Theory/
```

### End-to-end ZK pipeline demo

```bash
# Generate the Circom artifacts
circom src/Dsss/Zk/ConstantProductSolver.circom \
  --r1cs --wasm --sym --output build/zk/

# Compute the witness for k=600 (x=20, y=30)
node build/zk/ConstantProductSolver_js/generate_witness.js \
     build/zk/ConstantProductSolver_js/ConstantProductSolver.wasm \
     input.json \
     build/zk/witness.wtns

# The output geometry is in examples/demo_constraint_polyhedron.scad
# Open it with: openscad examples/demo_constraint_polyhedron.scad
```

---

## 3. How to Submit a Pull Request

### Branch naming

```
feat/<short-description>         New functionality
fix/<short-description>          Bug fix
theory/<name>                    New theory solver (e.g. theory/nra-groebner)
docs/<scope>                     Documentation only
test/<scope>                     Test additions or corrections
refactor/<scope>                 Internal cleanup with no behaviour change
```

### Commit style

Use the [Conventional Commits](https://www.conventionalcommits.org/) format:

```
<type>(<scope>): <short imperative description>

[optional body — why the change was made, not what]
[optional footer — issue references, breaking changes]
```

Examples:

```
feat(circuit): add WMul word operator to lowering pass
fix(zk): clamp witness coordinates to non-negative field elements
theory(nra): add Gröbner basis conflict explanation stub
docs(getting-started): add Windows build instructions
```

Breaking changes must include `BREAKING CHANGE:` in the footer.

### What to include in a PR

1. **All new source files** — no orphaned imports.
2. **Tests** — at minimum one Haskell property test, Scala unit test, or Python
   `pytest` function that exercises the new path.
3. **Type-checks clean** — `cabal build all` must succeed with no warnings unless
   you are adding an intentional stub (mark stubs with `error "stub: ..."` and
   add a `-- TODO` comment referencing the issue).
4. **HLint clean** — `hlint src/` must produce no suggestions.
5. **Black-formatted** — all Python files must pass `black --check src/`.
6. **One-line PR description** in the title; a paragraph describing motivation and
   any design decisions in the body.
7. Link the relevant GitHub Issue if one exists.

### PR review checklist (reviewers use this)

- [ ] Width indices are preserved end-to-end (invariant I1)
- [ ] No new `error "stub"` without a tracking issue
- [ ] SGMT stylesheet changes do not alter circuit semantics (invariant I4)
- [ ] ZK circuit changes preserve soundness obligations P1–P6
- [ ] New theory solver code follows the `TrigTheorySolver` interface pattern
- [ ] Futhark size parameters `[n]` are named after what they measure, not `a`, `b`

---

## 4. Contributor License Agreement

By submitting a pull request you agree that your contribution is made under, and
becomes part of, the codebase governed by the **BSL-1.1** license.  All rights in
contributed work are assigned to and vest in
**BEL ESPRIT D ACCORD TRUST HOLDINGS INC** upon merge.

This means:

- You retain the right to use the same code in other projects.
- You grant BEL ESPRIT D ACCORD TRUST HOLDINGS INC a perpetual, irrevocable,
  worldwide, royalty-free license to use, sublicense, modify, and distribute
  your contribution.
- Contributions may be included in a future commercial or patent-licensed product
  without additional notice or compensation.

If you are contributing on behalf of an employer, you represent that you have
authority to make this assignment.

---

## 5. Code Style Guidelines

### Haskell

- Lint with **HLint** before committing: `hlint src/`
- Use `{-# LANGUAGE ... #-}` pragmas at the top of each module; never in `cabal`
  `default-extensions` unless the extension is truly project-wide.
- Type-level programming (TypeNats, GADTs, type families) belongs in
  `Dsss/Circuit/TypeNat.hs` or a dedicated `Types` module — not inlined into
  implementation files.
- Width indices are `Nat` (from `GHC.TypeNats`); never use raw `Int` as a width
  at the type level.
- Keep `LowerM` actions short and focused; prefer `emitXxx` helpers to inline
  `State` manipulation.
- Export lists are mandatory for every module.

### Idris 2

- Use 2-space indentation throughout.
- Align record fields and constructor arguments vertically when there are three or
  more:
  ```idris
  record TypeNode where
      constructor MkTypeNode
      name       : String
      sizeParams : List (String, Nat)
  ```
- QTT multiplicity annotations `(0 x : T)` and `(1 x : T)` must appear on every
  erased or linear binding — never omit them and rely on inference alone.
- Prefer `Either Conflict Result` over partial functions; do not use `believe_me`.

### Futhark

- Size parameters must be named after what they represent: `[n]` for number of
  constraints, `[steps]` for angular resolution, `[w]` for bus width.  Never use
  single-letter size parameters `[a]` or `[b]`.
- Uniqueness type prefix `*` must appear on every mutable buffer parameter; the
  comment `-- unique, no alias` is encouraged above such parameters.
- Arithmetic helper functions (`det4x4`, `is_orthogonal`) must include a comment
  stating whether the current implementation is a stub or production code.
- Use `map2` and `reduce` over explicit loops.

### Python

- All Python files are formatted with **Black** (`black src/`).  CI will fail on
  unformatted files.
- Type annotations are required for all public functions and class methods.
- Stubs must raise `NotImplementedError("stub: <description>")` — do not return
  silent defaults from stubs that will be called by other code.
- Docstrings follow the Google style.

### Scala

- Use Scala 3 syntax (`enum`, `given`/`using`, extension methods) for new code.
- `fastparse` combinators: one parser combinator per `def`, with a name that
  mirrors the grammar non-terminal.
- No `null`; use `Option` or `Either`.

### SGMT stylesheets

- One `(match ...)` block per logical rule; do not concatenate unrelated rules.
- Comment every `(match ...)` block with the constraint class it targets.
- `(policy ...)` blocks must always set `:deterministic true` and `:seed 0`.

---

## 6. Where to Ask Questions

Open a [GitHub Issue](https://github.com/SNAPKITTYWEST/dsss/issues) with the
label `question`.  Please include:

- The relevant source file(s) and line numbers
- A minimal reproducer if the question is about unexpected behaviour
- Which layer of the stack (Frontend / Middleware / Solver Core / Backend / ZK
  Pipeline) the question concerns

There is no mailing list or chat channel at this time.

---

## 7. What Kinds of Contributions Are Welcome

### High priority

| Area | What is needed |
|---|---|
| **Theory solvers** | Complete NRA (Gröbner basis conflict explanation), Trig (full interval arithmetic replacing stubs), Geom (SO(3)/SE(3) propagation), TypeNet (full bipartite graph propagation) |
| **Circuit DSL extensions** | New `WordOp` constructors with corresponding lowering rules and proof obligations |
| **ZK pipeline** | Witness extraction for circuits beyond the constant-product template; PLONK/Groth16 proof integration |
| **Futhark kernel** | Production `det4x4` and `is_orthogonal` implementations; CUDA/OpenCL benchmark harness |
| **Test cases** | Regression tests for the lowering pass; property tests for width invariants; conformance tests against known SAT/UNSAT benchmarks |

### Also welcome

- Documentation improvements and worked examples
- SGMT stylesheet additions for new solver tactics
- Idris 2 QTT refinements to the Type Net bipartite graph
- Performance profiling and bottleneck reports (please open an Issue before
  submitting a large refactor)
- New OpenSCAD output templates for different geometric invariants

### Out of scope

- Changes to the `LICENSE` file
- Modifications to the patent-pending solver architecture or SGMT semantics
  without prior discussion in an Issue
- Dependency upgrades without a corresponding fix or feature rationale
