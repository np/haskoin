{-# LANGUAGE Trustworthy #-}
{-# LANGUAGE OverloadedStrings #-}

module Network.Haskoin.Crypto.Base58
( Address(..)
, addrToBase58
, base58ToAddr
, encodeBase58
, decodeBase58
, encodeBase58Check
, decodeBase58Check
) where

import safe Control.DeepSeq (NFData, rnf)
import safe Control.Monad (guard)
import safe Control.Applicative ((<$>),(<*>))

import {-unsafe-} Data.Aeson
    ( Value (String)
    , FromJSON
    , ToJSON
    , parseJSON
    , toJSON
    , withText 
    )

import safe Data.Char (ord, chr)
import safe Data.Word (Word8)
import safe Data.Maybe (fromJust, isJust, listToMaybe)
import safe Numeric (showIntAtBase, readInt)
import safe Data.String (fromString)

import safe qualified Data.ByteString as BS
import safe qualified Data.ByteString.Char8 as B8
import safe qualified Data.Text as T

import safe Network.Haskoin.Crypto.BigWord
import safe Network.Haskoin.Crypto.Hash
import safe Network.Haskoin.Constants
import safe Network.Haskoin.Util

b58Data :: BS.ByteString
b58Data = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

b58 :: Word8 -> Word8
b58 i = BS.index b58Data (fromIntegral i)

b58' :: Word8 -> Maybe Word8
b58' w = fromIntegral <$> BS.elemIndex w b58Data

encodeBase58I :: Integer -> BS.ByteString
encodeBase58I i = 
    fromString $ showIntAtBase (58 :: Integer) f (fromIntegral i) ""
  where
    f = chr . fromIntegral . b58 . fromIntegral

decodeBase58I :: BS.ByteString -> Maybe Integer
decodeBase58I s = case go of 
    Just (r,[]) -> Just r
    _           -> Nothing
  where
    c = b58' . fromIntegral . ord
    p = isJust . c 
    f = fromIntegral . fromJust . c
    go = listToMaybe $ readInt 58 p f (B8.unpack s)

-- | Encode a bytestring to a base 58 representation.
encodeBase58 :: BS.ByteString -> BS.ByteString
encodeBase58 bs = BS.append l r
  where 
    (z,b) = BS.span (== 0) bs
    l = BS.map b58 z -- preserve leading 0's
    r | BS.null b = BS.empty
      | otherwise = encodeBase58I $ bsToInteger b

-- | Decode a base 58 encoded bytestring. This can fail if the input bytestring
-- contains invalid base 58 characters such as 0,O,l,I
decodeBase58 :: BS.ByteString -> Maybe BS.ByteString
decodeBase58 bs = r >>= return . (BS.append prefix)
  where 
    (z,b)  = BS.span (== (b58 0)) bs
    prefix = BS.map (fromJust . b58') z -- preserve leading 1's
    r | BS.null b = Just BS.empty
      | otherwise = integerToBS <$> decodeBase58I b

-- | Computes a checksum for the input bytestring and encodes the input and
-- the checksum to a base 58 representation.
encodeBase58Check :: BS.ByteString -> BS.ByteString
encodeBase58Check bs = encodeBase58 $ BS.append bs chk
  where 
    chk = encode' $ chksum32 bs

-- | Decode a base 58 encoded bytestring that contains a checksum. This
-- function returns Nothing if the input bytestring contains invalid base 58
-- characters or if the checksum fails.
decodeBase58Check :: BS.ByteString -> Maybe BS.ByteString
decodeBase58Check bs = do
    rs <- decodeBase58 bs
    let (res,chk) = BS.splitAt ((BS.length rs) - 4) rs
    guard $ chk == (encode' $ chksum32 res)
    return res

-- |Data type representing a Bitcoin address
data Address 
    -- | Public Key Hash Address
    = PubKeyAddress { getAddrHash :: Word160 }
    -- | Script Hash Address
    | ScriptAddress { getAddrHash :: Word160 }
       deriving (Eq, Show, Read)

instance NFData Address where
    rnf (PubKeyAddress h) = rnf h
    rnf (ScriptAddress h) = rnf h

instance FromJSON Address where
    parseJSON = withText "address" $ \a -> do
        let s = T.unpack a
        maybe (fail $ "Not a Bitcoin address: " ++ s) return $ base58ToAddr s

instance ToJSON Address where
    toJSON = String . T.pack . addrToBase58

-- | Transforms an Address into a base58 encoded String
addrToBase58 :: Address -> String
addrToBase58 addr = bsToString $ encodeBase58Check $ case addr of
    PubKeyAddress i -> BS.cons addrPrefix $ encode' i
    ScriptAddress i -> BS.cons scriptPrefix $ encode' i

-- | Decodes an Address from a base58 encoded String. This function can fail
-- if the String is not properly encoded as base58 or the checksum fails.
base58ToAddr :: String -> Maybe Address
base58ToAddr str = do
    val <- decodeBase58Check $ stringToBS str
    let f | BS.head val == addrPrefix   = Just PubKeyAddress
          | BS.head val == scriptPrefix = Just ScriptAddress
          | otherwise = Nothing
    f <*> decodeToMaybe (BS.tail val)

