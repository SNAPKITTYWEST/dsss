-- DSSS Frontend: Idris 2 QTT Type Net
-- A Type Net is a bipartite constraint graph G = (T ∪ C, E) where:
--   T = type nodes with size parameters (e.g., Face[3], Edge[n])
--   C = constraint nodes (e.g., n = m + 1, det(R) = 1)
--   E = edges with QTT multiplicities:
--         0-edges: compile-time shape invariants (erased)
--         1-edges: linear resources (mutable constraint buffers)
--         ω-edges: unrestricted read-only references
module Dsss.Frontend.TypeNet

data Multiplicity = Zero | One | Many

record TypeNode where
    constructor MkTypeNode
    name       : String
    sizeParams : List (String, Nat)

record ConstraintNode where
    constructor MkConstraintNode
    expr : ConstraintExpr

record Edge where
    constructor MkEdge
    from : Either TypeNode ConstraintNode
    to   : Either TypeNode ConstraintNode
    mult : Multiplicity

record TypeNet where
    constructor MkTypeNet
    typeNodes       : List TypeNode
    constraintNodes : List ConstraintNode
    edges           : List Edge

-- Propagate size constraints through the graph
-- Only runtime-relevant edges (multiplicity ≠ 0) are traversed
propagate : TypeNet -> Either Conflict TypeNet
