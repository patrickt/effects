{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE DataKinds, PolyKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE MultiParamTypeClasses, FlexibleInstances, FlexibleContexts #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TemplateHaskell #-}

-- Only for MemberU below, when emulating Monad Transformers
{-# LANGUAGE FunctionalDependencies, UndecidableInstances #-}

{-|
Module      : Data.Union
Description : Open unions (type-indexed co-products) for extensible effects.
Copyright   : Allele Dev 2015
License     : BSD-3
Maintainer  : allele.dev@gmail.com
Stability   : experimental
Portability : POSIX

All operations are constant-time, and there is no Typeable constraint

This is a variation of OpenUnion5.hs, which relies on overlapping
instances instead of closed type families. Closed type families
have their problems: overlapping instances can resolve even
for unground types, but closed type families are subject to a
strict apartness condition.

This implementation is very similar to OpenUnion1.hs, but without
the annoying Typeable constraint. We sort of emulate it:

Our list r of open union components is a small Universe.
Therefore, we can use the Typeable-like evidence in that
universe.

The data constructors of Union are not exported.
-}

module Data.Union (
  Union,
  decompose,
  weaken,
  inj,
  prj,
  type(:<),
  type(:<:),
  MemberU2,
  Apply0(..),
  Apply1(..)
) where

import Data.Functor.Classes (Eq1(..), Show1(..))
import Data.Maybe (fromMaybe)
import Data.Proxy
import Data.Union.Templates
import Unsafe.Coerce(unsafeCoerce)
import GHC.Exts (Constraint)

infixr 5 :<

-- Strong Sum (Existential with the evidence) is an open union
-- t is can be a GADT and hence not necessarily a Functor.
-- Int is the index of t in the list r; that is, the index of t in the
-- universe r.
data Union (r :: [ k -> * ]) (v :: k) where
  Union :: {-# UNPACK #-} !Int -> t v -> Union r v

{-# INLINE prj' #-}
{-# INLINE inj' #-}
inj' :: Int -> t v -> Union r v
inj' = Union

prj' :: Int -> Union r v -> Maybe (t v)
prj' n (Union n' x) | n == n'   = Just (unsafeCoerce x)
                    | otherwise = Nothing

newtype P t r = P { unP :: Int }

infixr 5 :<:
-- | Find a list of members 'm' in an open union 'r'.
type family m :<: r :: Constraint where
  (t ': c) :<: r = (t :< r, c :<: r)
  '[] :<: r = ()

{-
-- Optimized specialized instance
instance (t :< '[t]) where
  {-# INLINE inj #-}
  {-# INLINE prj #-}
  inj x           = Union 0 x
  prj (Union _ x) = Just (unsafeCoerce x)
-}

-- | Inject a functor into a type-aligned union.
inj :: forall e r v. e :< r => e v -> Union r v
inj = inj' (unP (elemNo :: P e r))
{-# INLINE inj #-}

-- | Maybe project a functor out of a type-aligned union.
prj :: forall e r v. e :< r => Union r v -> Maybe (e v)
prj = prj' (unP (elemNo :: P e r))
{-# INLINE prj #-}


decompose :: Union (t ': r) v -> Either (Union r v) (t v)
decompose (Union 0 v) = Right $ unsafeCoerce v
decompose (Union n v) = Left  $ Union (n-1) v
{-# INLINE [2] decompose #-}


-- | Specialized version of 'decompose'.
decompose0 :: Union '[t] v -> Either (Union '[] v) (t v)
decompose0 (Union _ v) = Right $ unsafeCoerce v
-- No other case is possible
{-# RULES "decompose/singleton"  decompose = decompose0 #-}
{-# INLINE decompose0 #-}

weaken :: Union r w -> Union (any ': r) w
weaken (Union n v) = Union (n+1) v

-- Find an index of an element in an `r'.
-- The element must exist, so this is essentially a compile-time computation.
class (t :: k -> *) :< (r :: [k -> *]) where
  elemNo :: P t r

instance {-# OVERLAPPING #-} t :< (t ': r) where
  elemNo = P 0

instance {-# OVERLAPPING #-} t :< r => t :< (t' ': r) where
  elemNo = P $ 1 + unP (elemNo :: P t r)


-- | Helper to apply a function to a functor of the nth type in a type list.
class Apply0 (c :: * -> Constraint) (fs :: [k -> *]) (a :: k) where
  apply0 :: proxy c -> (forall g . c (g a) => g a -> b) -> Union fs a -> b

  apply0_2 :: proxy c -> (forall g . c (g a) => g a -> g b -> d) -> Union fs a -> Union fs b -> Maybe d

mkApply0Instances [1..150]


class Apply1 (c :: (k -> *) -> Constraint) (fs :: [k -> *]) where
  apply1 :: proxy c -> (forall g . (c g, g :< fs) => g a -> b) -> Union fs a -> b

  apply1_2 :: proxy c -> (forall g . (c g, g :< fs) => g a -> g b -> d) -> Union fs a -> Union fs b -> Maybe d


mkApply1Instances [1..150]


type family EQU (a :: k) (b :: k) :: Bool where
  EQU a a = 'True
  EQU a b = 'False

-- This class is used for emulating monad transformers
class (t :< r) => MemberU2 (tag :: k -> * -> *) (t :: * -> *) r | tag r -> t
instance (t1 :< r, MemberU' (EQU t1 t2) tag t1 (t2 ': r)) => MemberU2 tag t1 (t2 ': r)

class (t :< r) =>
      MemberU' (f::Bool) (tag :: k -> * -> *) (t :: * -> *) r | tag r -> t

instance MemberU' 'True tag (tag e) (tag e ': r)
instance (t :< (t' ': r), MemberU2 tag t r) =>
           MemberU' 'False tag t (t' ': r)

instance Apply1 Foldable fs => Foldable (Union fs) where
  foldMap f u = apply1 (Proxy :: Proxy Foldable) (foldMap f) u

instance Apply1 Functor fs => Functor (Union fs) where
  fmap f u = apply1 (Proxy :: Proxy Functor) (inj . fmap f) u

instance (Apply1 Foldable fs, Apply1 Functor fs, Apply1 Traversable fs) => Traversable (Union fs) where
  traverse f u = apply1 (Proxy :: Proxy Traversable) (fmap inj . traverse f) u

instance Apply0 Eq fs a => Eq (Union fs a) where
  u1 == u2 = fromMaybe False (apply0_2 (Proxy :: Proxy Eq) (==) u1 u2)

instance Apply0 Show fs a => Show (Union fs a) where
  showsPrec d u = apply0 (Proxy :: Proxy Show) (showsPrec d) u

instance Apply1 Eq1 fs => Eq1 (Union fs) where
  liftEq eq u1 u2 = fromMaybe False (apply1_2 (Proxy :: Proxy Eq1) (liftEq eq) u1 u2)


instance Apply1 Show1 fs => Show1 (Union fs) where
  liftShowsPrec sp sl d u = apply1 (Proxy :: Proxy Show1) (liftShowsPrec sp sl d) u
