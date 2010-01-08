module Halfs.Utils where

import Halfs.Classes

fmapFst :: (a -> b) -> (a, c) -> (b, c)
fmapFst f (x,y) = (f x, y)

divCeil :: Integral a => a -> a -> a
divCeil a b = (a + (b - 1)) `div` b
