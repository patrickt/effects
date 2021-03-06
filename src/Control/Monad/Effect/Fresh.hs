{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}

{-|
Module      : Control.Monad.Effect.Fresh
Description : Generation of fresh integers as an effect.
Copyright   : Allele Dev 2015
License     : BSD-3
Maintainer  : allele.dev@gmail.com
Stability   : broken
Portability : POSIX

Composable handler for Fresh effects. This is likely to be of use when
implementing De Bruijn naming/scopes.

Using <http://okmij.org/ftp/Haskell/extensible/Eff1.hs> as a
starting point.

-}
module Control.Monad.Effect.Fresh (
  Fresh,
  fresh,
  runFresh'
) where

import Control.Monad.Effect.Internal

--------------------------------------------------------------------------------
                             -- Fresh --
--------------------------------------------------------------------------------
-- | Fresh effect model
data Fresh v where
  Fresh :: Fresh Int

-- | Request a fresh effect
fresh :: (Fresh :< r) => Eff r Int
fresh = send Fresh

-- | Handler for Fresh effects, with an Int for a starting value
runFresh' :: Eff (Fresh ': r) w -> Int -> Eff r w
runFresh' m s =
  relayState s (\_s x -> pure x)
               (\s' Fresh k -> (k $! s'+1) s')
               m
