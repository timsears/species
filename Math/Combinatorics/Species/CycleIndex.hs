{-# LANGUAGE NoImplicitPrelude
           , CPP
           , FlexibleInstances
  #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  Math.Combinatorics.Species.CycleIndex
-- Copyright   :  (c) Brent Yorgey 2010
-- License     :  BSD-style (see LICENSE)
-- Maintainer  :  byorgey@cis.upenn.edu
-- Stability   :  experimental
--
-- An interpretation of species expressions as cycle index series.
-- For details on cycle index series, see \"Combinatorial Species and
-- Tree-Like Structures\", chapter 1.
--
-----------------------------------------------------------------------------

module Math.Combinatorics.Species.CycleIndex
    ( zToEGF
    , zToGF

    , zCoeff
    , zFix

      -- * Miscellaneous
    , aut
    , intPartitions
    , cyclePower
    ) where

import Math.Combinatorics.Species.Types
import Math.Combinatorics.Species.Class
import Math.Combinatorics.Species.Labeled

import Math.Combinatorics.Species.NewtonRaphson

import qualified MathObj.PowerSeries as PowerSeries
import qualified MathObj.MultiVarPolynomial as MVP
import qualified MathObj.Monomial as Monomial
import qualified MathObj.FactoredRational as FQ

import qualified Algebra.Ring as Ring
import qualified Algebra.ZeroTestable as ZeroTestable

import qualified Data.Map as M
import Data.List ( genericReplicate, genericDrop, groupBy, sort, intercalate, scanl
                 , genericIndex)
import Data.Function (on)
import Control.Arrow ((&&&), first, second)

import NumericPrelude
#if MIN_VERSION_numeric_prelude(0,2,0)
#else
import PreludeBase hiding (cycle)
#endif

-- | An interpretation of species expressions as cycle index series.
-- For the definition of the 'CycleIndex' type, see
-- "Math.Combinatorics.Species.Types".
instance Species CycleIndex where
  singleton  = CI $ MVP.x 1
  set        = ciFromMonomials . map partToMonomial . concatMap intPartitions $ [0..]

  cycle      = ciFromMonomials . concatMap cycleMonomials $ [1..]

  o          = liftCI2 MVP.compose

  (><)       = liftCI2 . MVP.lift2 $ hadamard

  (@@)       = zFComp

  ofSize s p = (liftCI . MVP.lift1 $ filter (p . Monomial.pDegree)) s
  ofSizeExactly s n
             = (liftCI . MVP.lift1 $
                 ( takeWhile ((==n) . Monomial.pDegree)
                 . dropWhile ((<n) . Monomial.pDegree))) s

  rec f      = case newtonRaphsonRec f 10 of
                 Nothing -> error $
                   "Unable to express " ++ show f ++ " in the form T = TX*R(T)."
                 Just ls -> ls

-- | Convert an integer partition to the corresponding monomial in the
--   cycle index series for the species of sets: 1/aut(js) * prod_i xi^ji.
partToMonomial :: CycleType -> Monomial.T Rational
partToMonomial js = Monomial.Cons (ezCoeff js) (M.fromList js)

-- | @'ezCoeff' js@ is the coefficient of the corresponding monomial in
--   the cycle index series for the species of sets.
ezCoeff :: CycleType -> Rational
ezCoeff js = toRational . recip $ aut js

-- | @aut js@ is is the number of automorphisms of a permutation with
--   cycle type @js@ (i.e. a permutation which has @n@ cycles of size
--   @i@ for each @(i,n)@ in @js@).  Another way to look at it is that
--   there are @n!/aut js@ permutations on n elements with cycle type
--   @js@.  The result type is a @'FactoredRational.T'@.
aut :: CycleType -> FQ.T
aut = product . map (\(b,e) -> FQ.factorial e * (fromInteger b)^e)

-- | Enumerate all partitions of an integer.  In particular, if @p@ is
--   an element of the list output by @intPartitions n@, then @sum
--   . map (uncurry (*)) $ p == n@.  The result type is @[CycleType]@
--   since each integer partition of @n@ corresponds to the cycle type
--   of a permutation on @n@ elements.
--
--   The partitions are generated in an order corresponding to
--   the Ord instance for 'Monomial'.
intPartitions :: Integer -> [CycleType]
intPartitions n = intPartitions' n n
  where intPartitions' :: Integer -> Integer -> [[(Integer,Integer)]]
        intPartitions' 0 _ = [[]]
        intPartitions' n 0 = []
        intPartitions' n k =
          [ if (j == 0) then js else (k,j):js
            | j <- reverse [0..n `div` k]
            , js <- intPartitions' (n - j*k) (min (k-1) (n - j*k)) ]

-- | @cycleMonomials d@ generates all monomials of partition degree
--   @d@ in the cycle index series for the species C of cycles.
cycleMonomials :: Integer -> [Monomial.T Rational]
cycleMonomials n = map cycleMonomial ds
  where n' = fromIntegral n
        ds = sort . FQ.divisors $ n'
        cycleMonomial d = Monomial.Cons (FQ.eulerPhi (n' / d) % n)
                                        (M.singleton (n `div` (toInteger d)) (toInteger d))

-- | Convert a cycle index series to an exponential generating
--   function:  F(x) = Z_F(x,0,0,0,...).
zToEGF :: CycleIndex -> EGF
zToEGF (CI (MVP.Cons xs))
  = EGF . PowerSeries.fromCoeffs
  . insertZeros
  . concatMap (\(c,as) -> case as of { [] -> [(0,c)] ; [(1,p)] -> [(p,c)] ; _ -> [] })
  . map (Monomial.coeff &&& (M.assocs . Monomial.powers))
  $ xs

-- | Convert a cycle index series to an ordinary generating function:
--   F~(x) = Z_F(x,x^2,x^3,...).
zToGF :: CycleIndex -> GF
zToGF (CI (MVP.Cons xs))
  = GF . PowerSeries.fromCoeffs . map numerator
  . insertZeros
  . map ((fst . head) &&& (sum . map snd))
  . groupBy ((==) `on` fst)
  . map ((sum . map (uncurry (*)) . M.assocs . Monomial.powers) &&& Monomial.coeff)
  $ xs

-- | Since cycle index series use a sparse representation, not every
--   power of x may be present after converting to an ordinary or
--   exponential generating function; 'insertZeros' inserts
--   coefficients of zero where necessary.
insertZeros :: Ring.C a => [(Integer, a)] -> [a]
insertZeros = insertZeros' [0..]
  where
    insertZeros' _ [] = []
    insertZeros' (n:ns) ((pow,c):pcs)
      | n < pow   = genericReplicate (pow - n) zero
                    ++ insertZeros' (genericDrop (pow - n) (n:ns)) ((pow,c):pcs)
      | otherwise = c : insertZeros' ns pcs

-- | Hadamard product.
hadamard :: (Ring.C a, ZeroTestable.C a) => [Monomial.T a] -> [Monomial.T a] -> [Monomial.T a]
hadamard = MVP.merge False zap
  where zap m1 m2 = Monomial.Cons (Monomial.coeff m1 * Monomial.coeff m2 *
                                    (fromInteger . toInteger . aut . M.assocs . Monomial.powers $ m1))
                                  (Monomial.powers m1)

-- | @cyclePower s n@ computes the cycle type of sigma^n, where sigma
--   is any permutation of cycle type s.
--
--   In particular, if s = (s_1, s_2, s_3, ...)  (i.e. sigma has s_1
--   fixed points, s_2 2-cycles, ... s_k k-cycles), then
--
--     sigma^n_j = sum_{j*gcd(n,k) = k} gcd(n,k)*s_k
cyclePower :: CycleType -> Integer -> CycleType
cyclePower [] _ = []
cyclePower s  n = concatMap jCycles [1..maximum (map fst s)]
  where jCycles j = let snj = sum . map (\(k,sk) -> if j*gcd n k == k then gcd n k * sk else 0) $ s
                    in  [ (j, snj) | snj > 0 ]

-- | Extract a particular coefficient from a cycle index series.
zCoeff :: CycleIndex -> CycleType -> Rational
zCoeff (CI (MVP.Cons z)) ix = c
  where ixm  = Monomial.mkMonomial 1 ix
        z'   = dropWhile (<ixm) z
        c    = case z' of
                 [] -> 0
                 (m:_) -> if (Monomial.powers m == Monomial.powers ixm)
                            then Monomial.coeff m
                            else 0

-- | Compute @fix F[n]@, i.e. the number of F-structures fixed by a
--   permutation with cycle type n, given the cycle index series Z_F.
--
--   In particular, @fix F[n] = aut(n) * zCoeff Z_F n@.
zFix :: CycleIndex -> CycleType -> Integer
zFix z n = numerator $ toRational (aut n) * zCoeff z n

-- | Functor composition for cycle index series.  See BLL pp. 72--73.
--
--   We have
--
--     Z_F \@ Z_G = sum_{n>=0}
--                    sum_{nn \in Par(n)}
--                      1/aut(nn) * fix F[(G[nn])_1, (G[nn])_2, ...]
--                      * x_1^nn_1 x_2^nn_2 ...
--
--   where
--
--     (G[nn])_k = 1/k sum_{d|k} \mu(k/d) fix G[nn^d]
--
--   and we use (G[nn])_k to denote (G[sigma])_k, the number of
--   k-cycles in the image of sigma under G, where sigma has cycle
--   type nn.  In fact, this only depends on the cycle type nn and not
--   on sigma, so the notation is well-defined.
--
--   How to know how far to compute G[nn]?  We know that nn is a
--   permutation of n labels, so we can compute G(n) (by converting to
--   an egf) and keep computing elements of G[nn] until the partition
--   degree equals G(n).
zFComp :: CycleIndex -> CycleIndex -> CycleIndex
zFComp f g = ciFromMonomials $
             concat $ for [0..] $ \n ->
               for (intPartitions n) $ \nn ->
                 Monomial.mkMonomial
                   (toRational (recip (aut nn)) * (zFix f (gnn nn n) % 1))
                   nn

  where for     = flip map

        -- Convert g to an EGF for later reference.
        gEGF    = labeled $ zToEGF g

        -- Given a cycle type @nn@ (corresponding to a permutation
        -- sigma on @n@ elements), compute the cycle type of G[sigma],
        -- which we abbreviate G[nn] since it is determined by the
        -- cycle type.
        --
        -- We first use gnn' to compute an infinite list of (cycle
        -- size, count) pairs, then truncate it to the right length:
        -- we know how many G-structures there are on a set of size n,
        -- so we know we are looking for a permutation on that many
        -- elements.
        gnn :: CycleType -> Integer -> CycleType
        gnn [] _  = []
        gnn  nn n = (gnn' nn) `truncToPartitionOf` (gEGF `genericIndex` n)

        -- Compute the image of a cycle type under G.
        gnn' :: CycleType -> CycleType
        gnn' nn = concat $ for [1..] $ \k -> let xk = gnnk nn k
                                             in [ (k,xk) | xk > 0 ]

        -- Compute (G[nn])_k for a particular k, that is, the number
        -- of cycles of size k in the image under G of any permutation
        -- with cycle type nn.
        gnnk :: CycleType -> Integer -> Integer
        gnnk nn k = (`div` k) . sum $
                      for (FQ.divisors k') $ \d ->
                        FQ.mu (k'/d) * zFix g (cyclePower nn (toInteger d))
          where k' = fromIntegral k

        truncToPartitionOf :: CycleType -> Integer -> CycleType
        truncToPartitionOf _ 0 = []
        truncToPartitionOf p n = map snd $ takeUntil ((>=n) . fst) partials
          where partials = zip (tail $ scanl (\soFar cyc -> soFar + uncurry (*) cyc) 0 p) p
                takeUntil p [] = []
                takeUntil p (x:xs) | p x = [x]
                                   | otherwise = x : takeUntil p xs