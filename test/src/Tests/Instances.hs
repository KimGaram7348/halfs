{-# OPTIONS_GHC -fno-warn-orphans #-}

module Tests.Instances
where

import Control.Applicative       ((<$>), (<*>))
import Control.Exception         (assert)
import Control.Monad             (foldM, replicateM)
import Data.Bits                 (shiftL)
import Data.ByteString           (ByteString)
import qualified Data.ByteString as BS
import Data.List (nub)
import Data.Word
import System.Random
import Test.QuickCheck
import Test.QuickCheck.Monadic hiding (assert)

import Halfs.BlockMap (Extent(..))

data BDGeom = BDGeom
  { bdgSecCnt :: Word64       -- ^ number of sectors
  , bdgSecSz  :: Word64       -- ^ sector size, in bytes
  } deriving Show

--------------------------------------------------------------------------------
-- Generators and helpers

-- | Generate an arbitrary geometry (modified by function given by the
-- first parameter) and employ the given geometry-requiring generator to
-- supply data to the given property.
forAllBlocksM :: Monad m =>
                 (BDGeom -> BDGeom)
              -- ^ geometry transformer
              -> (BDGeom -> Gen [(Word64, ByteString)])
              -- ^ data generator
              -> ([(Word64, ByteString)] -> BDGeom -> PropertyM m b)
              -- ^ property constructor   
              -> PropertyM m b
forAllBlocksM f gen prop =
  forAllM arbBDGeom $ \g -> let g' = f g in forAllM (gen g') (flip prop g')

-- | Generate a power of 2 given an exponent range in [0, 63]
powTwo :: Int -> Int -> Gen Word64
powTwo l h = assert (l >= 0 && h <= 63) $ shiftL 1 <$> choose (l, h)

arbBDGeom :: Gen BDGeom
arbBDGeom = arbitrary

-- | Given an extent, generates subextents that cover it; useful for creating
-- allocation sequences.  To keep the number of subextents relatively small, the
-- first two subextents generated cover ~75% of the input extent.  In order to
-- avoid generating identical base addresses due to integer division, the input
-- extent must be at least size 4.
arbExtents :: Extent -> Gen [Extent]
arbExtents (Extent _ ub) | ub < 4 =
  fail "Tests.Instances.arbExtents: Input extent size is too small (< 4)"
arbExtents (Extent b ub) = do
  filledQuarter <- fill (Extent (b + soFar) (ub - soFar))
  let r = Extent b halfCnt : (Extent (b + halfCnt) quarterCnt : filledQuarter)
  -- distinct base addrs
  assert (let bs = map extBase r in
          length bs == length (nub bs)) $ do
  -- exactly covers input extent and contains and no 0-size extents
  assert (ub == foldr (\e -> assert (extSz e > 0) (extSz e +)) 0 r) $ do
  return r
  where
    halfCnt    = ub `div` 2
    quarterCnt = ub `div` 4
    soFar      = halfCnt + quarterCnt
    --
    fill :: Extent -> Gen [Extent]
    fill (Extent _ 0)    = return []
    fill (Extent b' ub') = do
      sz   <- choose (1, ub')
      rest <- fill $ Extent (b' + sz) (ub' - sz)
      return (Extent b' sz : rest)

-- | Creates arbitrary "filesystem data" : just block addresses and
-- block data, constrained by the given device geometry
arbFSData :: BDGeom -> Gen [(Word64, ByteString)]
arbFSData g = listOf1 $ (,) <$> arbBlockAddr g <*> arbBlockData g

-- | Creates arbitrary contiguous "filesystem data" : consecutive runs
-- of block addresses and accompanying block data, constrained by the
-- given device geometry
arbContiguousData :: BDGeom -> Gen [(Word64, ByteString)]
arbContiguousData g = do
  let numBlks = fromIntegral $ bdgSecCnt g
      limit   = 64 -- artificial limit on number of contiguous blocks
                   -- generated; keeps generated data on the small side
  numContig <- if numBlks > 1 -- maybe we can't create continguous blocks
               then choose (2 :: Integer, max 2 (min limit (numBlks `div` 2)))
               else return 1
  baseAddrs <- (\x -> map fromIntegral [x .. x + numContig])
               `fmap` choose (0 :: Integer, numBlks - numContig)
  zip baseAddrs `fmap` vectorOf (fromIntegral numContig) (arbBlockData g)

arbBlockAddr :: BDGeom -> Gen Word64
arbBlockAddr (BDGeom cnt _sz) =
  fromIntegral `fmap` choose (0 :: Integer, ub)
    where ub = fromIntegral $ cnt - 1

arbBlockData :: BDGeom -> Gen ByteString
arbBlockData (BDGeom _cnt sz) =
  BS.pack `fmap` replicateM (fromIntegral sz) byte

byte :: Gen Word8
byte = fromIntegral `fmap` choose (0 :: Int, 255)

-- | A hacky, inefficient-but-good-enough permuter
permute :: [a] -> Gen [a]
permute xs = do
  let len = fromIntegral $ length xs
  foldM rswap xs $ replicate len len
  where
    rswap [] _       = return []
    rswap (x:xs') len = do
      i <- choose (0, len - 1)
      return $ let (l,r) = splitAt i xs'
               in l ++ [x] ++ r

--------------------------------------------------------------------------------
-- Instances and helpers

-- instance Arbitrary BDGeom where
--   arbitrary = 
--     BDGeom
--     <$> powTwo 10 13   -- 1024..8192 sectors
--     <*> powTwo  8 12   -- 256b..4K sector size
--                        -- => 256K .. 32M filesystem siz

instance Arbitrary BDGeom where
 arbitrary = return $ BDGeom 64 4

instance Random Word64 where
  randomR = integralRandomR
  random  = randomR (minBound, maxBound)

integralRandomR :: (Integral a, RandomGen g) => (a,a) -> g -> (a,g)
integralRandomR (a,b) g = case randomR (fromIntegral a :: Integer,
                                        fromIntegral b :: Integer) g of
                            (x,g') -> (fromIntegral x, g')
