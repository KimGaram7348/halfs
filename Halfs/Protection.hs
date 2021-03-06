{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Halfs.Protection(
         UserID (..)
       , GroupID(..)
       , rootUser
       , rootGroup
       )
  where

import Data.Serialize
import Data.Word

newtype UserID = UID Word64
  deriving (Show, Eq, Real, Enum, Integral, Num, Ord)

instance Serialize UserID where
  put (UID x) = putWord64be x
  get         = UID `fmap` getWord64be

rootUser :: UserID
rootUser = UID 0

--

newtype GroupID = GID Word64
  deriving (Show, Eq, Real, Enum, Integral, Num, Ord)

instance Serialize GroupID where
  put (GID x) = putWord64be x
  get         = GID `fmap` getWord64be

rootGroup :: GroupID
rootGroup = GID 0
