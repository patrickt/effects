module Main where

import Control.Monad.Effect
import Data.Functor.Classes (Eq1(..))
import Data.Monoid (Sum(..))

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck

import Tests.Coroutine
import Tests.Exception
import Tests.Fresh
import Tests.NonDet
import Tests.Reader
import Tests.State
import Tests.StateRW
import Tests.Union

import qualified Data.List

--------------------------------------------------------------------------------
                           -- Pure Tests --
--------------------------------------------------------------------------------
addInEff :: Int -> Int -> Int
addInEff x y = run ((+) <$> pure x <*> pure y)

pureTests :: TestTree
pureTests = testGroup "Pure Eff tests"
  [ testProperty "Pure run just works: (+)"
      (\x y -> addInEff x y == x + y)
  ]

--------------------------------------------------------------------------------
                        -- Coroutine Tests --
--------------------------------------------------------------------------------

-- | Counts number of consecutive pairs of odd elements at beginning of a list.
countOddDuoPrefix :: [Int] -> Int
countOddDuoPrefix list = count list 0
  where
    count (i1:i2:is) n = if even i1 && even i2 then n else count is (n+1)
    count _ n = n

coroutineTests :: TestTree
coroutineTests = testGroup "Coroutine Eff tests"
  [ testProperty "Counting consecutive pairs of odds"
      (\list -> runTestCoroutine list == countOddDuoPrefix list)
  ]

--------------------------------------------------------------------------------
                        -- Exception Tests --
--------------------------------------------------------------------------------
exceptionTests :: TestTree
exceptionTests = testGroup "Exception Eff tests"
  [ testProperty "Exc takes precedence" (\x y -> testExceptionTakesPriority x y == Left y)
  , testCase "uncaught: runState (runError t)" $
      ter1 @?= (Left "exc", 2)
  , testCase "uncaught: runError (runState t)" $
      ter2 @?= Left "exc"
  , testCase "caught: runState (runError t)" $
      ter3 @?= (Right "exc", 2)
  , testCase "caught: runError (runState t)" $
      ter4 @?= Right ("exc", 2)
  , testCase "success: runReader (runErrBig t)" (ex2rr @?= Right 5)
  , testCase "uncaught: runReader (runErrBig t)" $
      ex2rr1 @?= Left (TooBig 7)
  , testCase "uncaught: runErrBig (runReader t)" $
      ex2rr2 @?= Left (TooBig 7)
  ]

--------------------------------------------------------------------------------
                       -- Fresh Effect Tests --
--------------------------------------------------------------------------------
freshTests :: TestTree
freshTests = testGroup "Fresh tests"
  [ testCase "Start at 0, refresh twice, yields 1" (testFresh 10 @?= 9)
  , testProperty "Freshening n times yields (n-1)" (\n -> n > 0 ==> testFresh n == (n-1))
  ]

--------------------------------------------------------------------------------
                 -- Nondeterministic Effect Tests --
--------------------------------------------------------------------------------
-- https://wiki.haskell.org/Prime_numbers
primesTo :: Int -> [Int]
primesTo m = sieve [2..m]       {- (\\) is set-difference for unordered lists -}
  where
    sieve (x:xs) = x : sieve (xs Data.List.\\ [x,x+x..m])
    sieve [] = []

nonDetTests :: TestTree
nonDetTests = testGroup "NonDet tests"
  [ testProperty "Primes in 2..n generated by ifte"
      (\n' -> let n = abs n' in testIfte [2..n] == primesTo n)
  ]

--------------------------------------------------------------------------------
                      -- Reader Effect Tests --
--------------------------------------------------------------------------------
readerTests :: TestTree
readerTests = testGroup "Reader tests"
  [ testProperty "Reader passes along environment: n + x"
    (\n x -> testReader n x == n + x)
  , testProperty "Multiple readers work"
    (\f n -> testMultiReader f n == ((f + 2.0) + fromIntegral (n + 1)))
  , testProperty "Local injects into env"
    (\env inc -> testLocal env inc == 2*(env+1) + inc)
  ]

--------------------------------------------------------------------------------
                     -- State[RW] Effect Tests --
--------------------------------------------------------------------------------
stateTests :: TestTree
stateTests = testGroup "State tests"
  [ testProperty "get after put n yields (n,n)" (\n -> testPutGet n 0 == (n,n))
  , testProperty "Final put determines stored state" $
    \p1 p2 start -> testPutGetPutGetPlus p1 p2 start == (p1+p2, p2)
  , testProperty "If only getting, start state determines outcome" $
    \start -> testGetStart start == (start,start)
  , testProperty "testPutGet: State == StateRW" $
    \n -> testPutGet n 0 == testPutGetRW n 0
  , testProperty "testPutGetPutGetPlus: State == StateRW" $
    \p1 p2 start -> testPutGetPutGetPlus p1 p2 start == testPutGetPutGetPlusRW p1 p2 start
  , testProperty "testGetStart: State == StateRW" $
    \n -> testGetStart n == testGetStartRW n
  ]

--------------------------------------------------------------------------------
                     -- Union instance Tests --
--------------------------------------------------------------------------------
unionTests :: TestTree
unionTests = testGroup "Union tests"
  [ testProperty "unary fmap equivalence" (\ n -> fmap succ (testUnaryUnion n) == testUnaryUnion (succ n))
  , testProperty "binary fmap equivalence 0" (\ n -> fmap succ (testBinaryUnion0 n) == testBinaryUnion0 (succ n))
  , testProperty "binary fmap equivalence 1" (\ s -> fmap succ (testBinaryUnion1 s) == testBinaryUnion1 s)
  , testProperty "unary traverse equivalence" (\ n -> traverse Just (testUnaryUnion n) == Just (testUnaryUnion n))
  , testProperty "binary traverse equivalence 0" (\ n -> traverse Just (testBinaryUnion0 n) == Just (testBinaryUnion0 n))
  , testProperty "binary traverse equivalence 1" (\ s -> traverse Just (testBinaryUnion1 s) == Just (testBinaryUnion1 s))
  , testProperty "unary foldMap equivalence" (\ n -> foldMap Sum (testUnaryUnion n) == Sum n)
  , testProperty "binary foldMap equivalence 0" (\ n -> foldMap Sum (testBinaryUnion0 n) == Sum n)
  , testProperty "binary foldMap equivalence 1" (\ s -> foldMap Sum (testBinaryUnion1 s) == mempty)
  , testProperty "unary lifted equality" (\ n -> liftEq (==) (testUnaryUnion n) (testUnaryUnion n))
  , testProperty "binary lifted equality 0" (\ n -> liftEq (==) (testBinaryUnion0 n) (testBinaryUnion0 n))
  , testProperty "binary lifted equality 1" (\ s -> liftEq (==) (testBinaryUnion1 s) (testBinaryUnion1 s))
  , testProperty "binary lifted inequality 0" (\ n s -> not (liftEq (==) (testBinaryUnion0 n) (testBinaryUnion1 s)))
  , testProperty "binary lifted inequality 1" (\ s n -> not (liftEq (==) (testBinaryUnion1 s) (testBinaryUnion0 n)))
  ]

--------------------------------------------------------------------------------
                             -- Runner --
--------------------------------------------------------------------------------
main :: IO ()
main = defaultMain $ testGroup "Tests"
  [ pureTests
  , coroutineTests
  , exceptionTests
  , freshTests
  , nonDetTests
  , readerTests
  , stateTests
  , unionTests
  ]
