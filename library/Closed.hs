{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# OPTIONS_GHC -fno-warn-unticked-promoted-constructors #-}

module Closed
  ( Endpoint(..)
  , Closed
  , Range
  , Single
  , packClosed
  , closed
  , getClosed
  , lowerBound
  , upperBound
  , equals
  , cmp
  , natToClosed
  , weakenUpper
  , weakenLower
  , strengthenUpper
  , strengthenLower
  , add
  , sub
  , multiply
  , isValidClosed
  ) where

import Data.Aeson
import qualified Data.Csv as CSV
import Data.Hashable
import Data.Maybe
import Data.Proxy
import Data.Ratio
import GHC.TypeLits
import Closed.Internal (Closed(..))
import Control.DeepSeq

-- | Describe whether the endpoint of a 'Range' includes
-- or excludes its argument
data Endpoint
  -- | Endpoint includes its argument
  = Includes Nat
  -- | Endpoint excludes its argument
  | Excludes Nat

-- | Syntactic sugar to express open and half-open intervals using
-- the 'Closed' type
type family Range (lhs :: Endpoint) (rhs :: Endpoint) :: * where
  Range (Includes n) (Includes m) = Closed  n       m
  Range (Includes n) (Excludes m) = Closed  n      (m - 1)
  Range (Excludes n) (Includes m) = Closed (n + 1)  m
  Range (Excludes n) (Excludes m) = Closed (n + 1) (m - 1)

-- | Syntatic sugar to express a value that has only one non-bottom
-- inhabitant using the 'Closed' type
type Single (n :: Nat) = Range ('Includes n) ('Includes n)

-- | Proxy for the lower bound of a 'Closed' value
lowerBound :: Closed n m -> Proxy n
lowerBound _ = Proxy

-- | Proxy for the upper bound of a 'Closed' value
upperBound :: Closed n m -> Proxy m
upperBound _ = Proxy

-- | Safely create a 'Closed' value using the specified argument
packClosed :: (n <= m, KnownNat n, KnownNat m) => Integer -> Maybe (Closed n m)
packClosed x = result
 where
  extracted = fromJust result
  result =
    if x >= natVal (lowerBound extracted) && x <= natVal (upperBound extracted)
      then return $ Closed x
      else Nothing

-- | Create a 'Closed' value throwing an error if the argument is not in range
closed :: (n <= m, KnownNat n, KnownNat m) => Integer -> Closed n m
closed x = result
 where
  result =
    if x >= natVal (lowerBound result) && x <= natVal (upperBound result)
      then Closed x
      else error $ unrepresentable x result "closed"

-- | Test equality on 'Closed' values in the same range
instance Eq (Closed n m) where
  Closed x == Closed y = x == y

-- | Compare 'Closed' values in the same range
instance Ord (Closed n m) where
  Closed x `compare` Closed y = x `compare` y

-- | Generate the lowest and highest inhabitant of a given 'Closed' type
instance (n <= m, KnownNat n, KnownNat m) => Bounded (Closed n m) where
  maxBound = result
   where
    result = Closed (natVal (upperBound result))

  minBound = result
   where
    result = Closed (natVal (lowerBound result))

-- | Enumerate values in the range of a given 'Closed' type
instance (n <= m, KnownNat n, KnownNat m) => Enum (Closed n m) where
  fromEnum = fromEnum . getClosed
  toEnum = closed . toEnum
  enumFrom x = enumFromTo x maxBound
  enumFromThen x y = enumFromThenTo x y (if x >= y then minBound else maxBound)

instance Show (Closed n m) where
  showsPrec d (Closed x) = showParen (d > 9) $ showString "closed " . showsPrec 10 x

-- | Bounded arithmetic, e.g. maxBound + 1 == maxBound
instance (n <= m, KnownNat n, KnownNat m) => Num (Closed n m) where
  Closed x + Closed y = Closed $ min (x + y) (fromIntegral (maxBound :: Closed n m))
  Closed x - Closed y = Closed $ max (x - y) (fromIntegral (minBound :: Closed n m))
  Closed x * Closed y = Closed $ min (x * y) (fromIntegral (maxBound :: Closed n m))
  abs = id
  signum = const 1
  fromInteger x = result
   where
    result =
      if x >= natVal (lowerBound result) && x <= natVal (upperBound result)
        then Closed x
        else error $ unrepresentable x result "fromInteger"

instance (n <= m, KnownNat n, KnownNat m) => Real (Closed n m) where
  toRational (Closed x) = x % 1

instance (n <= m, KnownNat n, KnownNat m) => Integral (Closed n m) where
  quotRem (Closed x) (Closed y) = (Closed $ x `quot` y, Closed $ x `rem` y)
  toInteger (Closed x) = x

instance NFData (Closed n m)

instance Hashable (Closed n m)

instance ToJSON (Closed n m) where
  toEncoding = toEncoding . getClosed

instance (n <= m, KnownNat n, KnownNat m) => FromJSON (Closed n m) where
  parseJSON v = do
    x <- parseJSON v
    case packClosed x of
      Just cx -> pure cx
      n -> fail $ unrepresentable x (fromJust n) "parseJSON"

instance CSV.ToField (Closed n m) where
  toField = CSV.toField . getClosed

instance (n <= m, KnownNat n, KnownNat m) => CSV.FromField (Closed n m) where
  parseField s = do
    x <- CSV.parseField s
    case packClosed x of
      Just cx -> pure cx
      n -> fail $ unrepresentable x (fromJust n) "parseField"

unrepresentable :: (KnownNat n, KnownNat m) => Integer -> Closed n m -> String -> String
unrepresentable x cx prefix =
  prefix ++ ": Integer " ++ show x ++
  " is not representable in Closed " ++ show (natVal $ lowerBound cx) ++
  " " ++ show (natVal $ upperBound cx)

-- | Convert a type-level literal into a 'Closed' value
natToClosed :: (n <= x, x <= m, KnownNat x, KnownNat n, KnownNat m) => proxy x -> Closed n m
natToClosed p = Closed $ natVal p

-- | Add one inhabitant at the end
weakenUpper :: Closed n m -> Closed n (m + 1)
weakenUpper (Closed x) = Closed x

-- | Add one inhabitant at the beginning
weakenLower :: Closed (n + 1) m -> Closed n m
weakenLower (Closed x) = Closed x

-- | Remove one inhabitant from the end. Returns 'Nothing' if the input was removed
strengthenUpper :: (KnownNat n, KnownNat m) => Closed n (m + 1) -> Maybe (Closed n m)
strengthenUpper (Closed x) = result
 where
  result =
    if x <= natVal (upperBound $ fromJust result)
      then Just $ Closed x
      else Nothing

-- | Remove one inhabitant from the beginning. Returns 'Nothing' if the input was removed
strengthenLower :: (KnownNat (n + 1), KnownNat m) => Closed n m -> Maybe (Closed (n + 1) m)
strengthenLower (Closed x) = result
 where
  result =
    if x >= natVal (lowerBound $ fromJust result)
      then Just $ Closed x
      else Nothing

-- | Test two different types of 'Closed' values for equality.
equals :: Closed n m -> Closed o p -> Bool
equals (Closed x) (Closed y) = x == y
infix 4 `equals`

-- | Compare two different types of 'Closed' values
cmp :: Closed n m -> Closed o p -> Ordering
cmp (Closed x) (Closed y) = x `compare` y

-- | Add two different types of 'Closed' values
add :: Closed n m -> Closed o p -> Closed (n + o) (m + p)
add (Closed x) (Closed y) = Closed $ x + y

-- | Subtract two different types of 'Closed' values
-- Returns 'Left' for negative results, and 'Right' for positive results.
sub :: Closed n m -> Closed o p -> Either (Closed (o - n) (p - m)) (Closed (n - o) (m - p))
sub (Closed x) (Closed y)
  | x >= y = Right $ Closed $ x - y
  | otherwise = Left $ Closed $ y - x

-- | Multiply two different types of 'Closed' values
multiply :: Closed n m -> Closed o p -> Closed (n * m) (o * p)
multiply (Closed x) (Closed y) = Closed $ x * y

-- | Verifies that a given 'Closed' value is valid.
-- Should always return 'True' unles you bring the @Closed.Internal.Closed@ constructor into scope,
-- or use 'Unsafe.Coerce.unsafeCoerce' or other nasty hacks
isValidClosed :: (KnownNat n, KnownNat m) => Closed n m -> Bool
isValidClosed cx@(Closed x) =
  natVal (lowerBound cx) <= x && x <= natVal (upperBound cx)
