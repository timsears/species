{-# LANGUAGE NoImplicitPrelude
           , CPP
           , GeneralizedNewtypeDeriving
           , PatternGuards
  #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  Math.Combinatorics.Species.Labeled
-- Copyright   :  (c) Brent Yorgey 2010
-- License     :  BSD-style (see LICENSE)
-- Maintainer  :  byorgey@cis.upenn.edu
-- Stability   :  experimental
--
-- An interpretation of species as exponential generating functions,
-- which count labeled structures.
--
-----------------------------------------------------------------------------

module Math.Combinatorics.Species.Labeled
    ( labeled
    , labelled
    ) where

-- A previous version of this module used an EGF library which
-- explicitly computed with EGFs.  However, it turned out to be much
-- slower than just computing explicitly with normal power series and
-- zipping/unzipping with factorial denominators as necessary, which
-- is the current approach.

import Math.Combinatorics.Species.Types
import Math.Combinatorics.Species.Class

import Math.Combinatorics.Species.AST
import Math.Combinatorics.Species.AST.Instances
import Math.Combinatorics.Species.NewtonRaphson

import qualified MathObj.PowerSeries as PS
import qualified MathObj.FactoredRational as FQ

import NumericPrelude
#if MIN_VERSION_numeric_prelude(0,2,0)
#else
import PreludeBase hiding (cycle)
#endif

facts :: [Integer]
facts = 1 : zipWith (*) [1..] facts

instance Species EGF where
  singleton  = egfFromCoeffs [0,1]
  set        = egfFromCoeffs (map (1%) facts)
  cycle      = egfFromCoeffs (0 : map (1%) [1..])
  o          = liftEGF2 PS.compose
  (><)       = liftEGF2 . PS.lift2 $ \xs ys ->
                 zipWith3 mult xs ys (map fromIntegral facts)
                   where mult x y z = x * y * z
  (@@)       = liftEGF2 . PS.lift2 $ \fs gs ->
                 map (\(n,gn) -> let gn' = numerator $ gn
                                 in  (fs `safeIndex` gn') *
                                     toRational (FQ.factorial gn' / FQ.factorial n))
                     (zip [0..] $ zipWith (*) (map fromIntegral facts) gs)
    where safeIndex [] _     = 0
          safeIndex (x:_)  0 = x
          safeIndex (_:xs) n = safeIndex xs (n-1)

  ofSize s p        = (liftEGF . PS.lift1 $ filterCoeffs p) s
  ofSizeExactly s n = (liftEGF . PS.lift1 $ selectIndex n) s

  -- XXX Think about this more carefully -- is there a way to make this actually
  --   return a lazy, infinite list?
  rec f = case newtonRaphsonRec f 100 of
            Nothing -> error $ "Unable to express " ++ show f ++ " in the form T = TX*R(T)."
            Just ls -> ls

-- | Extract the coefficients of an exponential generating function as
--   a list of 'Integer's.  Since 'EGF' is an instance of 'Species', the
--   idea is that 'labeled' can be applied directly to an expression
--   of the species DSL.  In particular, @'labeled' s '!!'  n@ is the
--   number of labeled @s@-structures on an underlying set of size @n@
--   (note that @'labeled' s@ is guaranteed to be an infinite list).
--   For example:
--
-- > > take 10 $ labeled octopi
-- > [0,1,3,14,90,744,7560,91440,1285200,20603520]
--
--   gives the number of labeled octopi on 0, 1, 2, 3, ... 9 labels.

labeled :: EGF -> [Integer]
labeled (EGF f) = (++repeat 0)
                . map numerator
                . zipWith (*) (map fromInteger facts)
                $ PS.coeffs f

-- | A synonym for 'labeled', since both spellings are acceptable and
--   it's annoying to have to remember which is correct.
labelled :: EGF -> [Integer]
labelled = labeled

