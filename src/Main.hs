module Main where


import Protolude

import Data.Task
import Data.Task.Equality

import System.IO.Unsafe

import Test.QuickCheck


main :: IO ()
main = do
  quickCheck prop_equal_val
  quickCheck prop_normalising_preserves_failing
  quickCheck prop_pair_left_identity
  quickCheck prop_pair_right_identity
  quickCheck prop_pair_associativity

  where

    prop_equal_val :: TaskIO Int -> Bool
    prop_equal_val t = unsafePerformIO $ do
      x <- value t
      y <- value t
      pure $ x == y

    prop_normalising_preserves_failing :: TaskIO Int -> Bool
    prop_normalising_preserves_failing t = unsafePerformIO $ do
      t' <- normalise t
      pure $ failing t == failing t'

    -- prop_norm_val :: Task Int -> Bool
    -- prop_norm_val t = unsafePerformIO $ do
    --   v <- value t
    --   t' <- normalise t
    --   v' <- value t'
    --   pure $ v == v'
