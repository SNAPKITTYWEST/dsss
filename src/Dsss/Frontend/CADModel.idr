-- DSSS Frontend: Idris 2 QTT Recursive CAD Model
-- QTT quantities: 0 = erased (compile-time only), 1 = linear, ω = unrestricted
module Dsss.Frontend.CADModel

-- Futhark-invariant replacement for GADT vectors
-- * prefix = uniqueness type (no aliases → in-place update safe)
record GeomArray : (n : Nat) -> (a : Type) -> Type where
    constructor MkGeomArray
    data  : *([n]a)       -- unique, size-parameterized array
    inv   : (0 _ : n > 0) -- compile-time proof of non-emptiness

-- Recursive CAD model indexed by unfolding depth
-- QTT multiplicities:
--   (0 d : Nat)  = depth is compile-time only (erased at runtime)
--   (1 m : CADModel d) = model is linear (consumed exactly once per Transform)
--   (0 R : SO3)  = rotation is erased (used only in constraint generation)
data CADModel : (depth : Nat) -> Type where
    Primitive : (0 d : Nat) -> Mesh -> CADModel d
    Transform : (1 m : CADModel d) -> (0 R : SO3) -> (0 t : R3) -> CADModel d
    Union     : (1 a : CADModel d) -> (1 b : CADModel d) -> CADModel d
    Recurse   : (0 d : Nat) -> (1 f : CADModel d -> CADModel (S d)) -> CADModel (S d)

-- Unfolding generates a constraint set up to bounded depth
-- (0 maxDepth : Nat) = depth bound is compile-time only
-- (1 model : CADModel d) = model is consumed (linear)
unfold : (0 maxDepth : Nat) -> (1 model : CADModel d) -> ConstraintSet
unfold Z     (Primitive _ mesh)   = mesh_constraints mesh
unfold Z     _                    = empty  -- depth limit reached
unfold (S k) (Transform m R t)   =
    let cs = unfold k m
    in  add_rigid_transform cs R t
unfold (S k) (Union a b)         =
    let ca = unfold k a
        cb = unfold k b
    in  merge_disjoint ca cb
unfold (S k) (Recurse d f)       =
    unfold k (f (Primitive d base_mesh))
